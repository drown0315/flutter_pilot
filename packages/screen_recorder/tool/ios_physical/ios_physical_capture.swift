import AVFoundation
import CoreMediaIO
import Foundation

struct IOSCaptureDevice {
    let id: String
    let name: String
    let model: String
    let manufacturer: String
    let device: AVCaptureDevice
}

func enableIOSScreenCaptureDevices() {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        UInt32(MemoryLayout.size(ofValue: allow)),
        &allow
    )
    Thread.sleep(forTimeInterval: 1.0)
}

func discoverIOSDevices() -> [IOSCaptureDevice] {
    enableIOSScreenCaptureDevices()
    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external, .builtInWideAngleCamera],
        mediaType: nil,
        position: .unspecified
    )
    return session.devices
        .filter { device in
            device.modelID == "iOS Device" && device.manufacturer == "Apple Inc."
        }
        .map { device in
            IOSCaptureDevice(
                id: device.uniqueID,
                name: device.localizedName,
                model: device.modelID,
                manufacturer: device.manufacturer,
                device: device
            )
        }
}

func printDeviceList() {
    print("id\tname\tmodel\tmanufacturer")
    for item in discoverIOSDevices() {
        print("\(item.id)\t\(item.name)\t\(item.model)\t\(item.manufacturer)")
    }
}

final class MovieRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Mode {
        case record
        case serve
    }

    enum State {
        case preparing
        case ready
        case recording
        case finalizing
        case closed
    }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "screen-recorder.ios-physical.video")
    private let mode: Mode
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var state: State = .preparing
    private var shutdownRequested = false
    private var finished = false
    private var wroteFrames = false
    private var startedEmitted = false

    init(mode: Mode) {
        self.mode = mode
    }

    func start(device: AVCaptureDevice, outputURL: URL?) throws {
        self.outputURL = outputURL

        session.beginConfiguration()
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "screen_recorder_ios", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot add iOS capture input"])
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else {
            throw NSError(domain: "screen_recorder_ios", code: 11, userInfo: [NSLocalizedDescriptionKey: "Cannot add video data output"])
        }
        session.addOutput(videoOutput)
        session.commitConfiguration()

        if let outputURL, FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        signal(SIGTERM) { _ in
            RecorderSignalBridge.shared.shutdown()
        }
        signal(SIGINT) { _ in
            RecorderSignalBridge.shared.shutdown()
        }
        RecorderSignalBridge.shared.recorder = self

        session.startRunning()
        if mode == .serve {
            readCommands()
        }
        RunLoop.main.run()
    }

    func shutdown() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.finished { return }
            self.shutdownRequested = true
            switch self.state {
            case .recording:
                self.stopSegment(exitWhenFinished: true)
            case .finalizing:
                return
            default:
                self.finish(exitCode: 0)
            }
        }
    }

    private func readCommands() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine() {
                self?.handleCommandLine(line)
            }
        }
    }

    private func handleCommandLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            emitError("Command was not valid UTF-8.")
            return
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let operation = object["operation"] as? String else {
                emitError("Command must be a JSON object with an operation.")
                return
            }
            switch operation {
            case "start":
                guard let outputPath = object["outputPath"] as? String else {
                    emitError("start command requires outputPath.")
                    return
                }
                startSegment(outputURL: URL(fileURLWithPath: outputPath))
            case "stop":
                queue.async { [weak self] in
                    self?.stopSegment(exitWhenFinished: false)
                }
            case "shutdown":
                shutdown()
            default:
                emitError("Unsupported operation: \(operation)")
            }
        } catch {
            emitError("Command JSON parse failed: \(error.localizedDescription)")
        }
    }

    private func startSegment(outputURL: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.state == .ready else {
                self.emitError("Cannot start segment while state is \(self.state).")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                self.outputURL = outputURL
                self.writer = nil
                self.writerInput = nil
                self.wroteFrames = false
                self.startedEmitted = false
                self.state = .recording
            } catch {
                self.emitError("Failed to prepare output file: \(error.localizedDescription)")
            }
        }
    }

    private func stopSegment(exitWhenFinished: Bool) {
        guard state == .recording else {
            if mode == .record {
                eprint("No video frames were received from the iOS capture device.")
                finish(exitCode: 7)
            } else {
                emitError("Cannot stop segment while state is \(state).")
            }
            return
        }
        state = .finalizing
        guard let writer = writer else {
            if mode == .record {
                eprint("No video frames were received from the iOS capture device.")
                finish(exitCode: 7)
            } else {
                emitError("No video frames were received from the iOS capture device.")
                state = .ready
            }
            return
        }
        writerInput?.markAsFinished()
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.finished, self.state == .finalizing else { return }
            eprint("Timed out while finalizing the movie file.")
            writer.cancelWriting()
            self.finish(exitCode: 8)
        }
        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.queue.async {
                if let error = writer.error {
                    if self.mode == .record {
                        eprint("Movie finalization failed: \(error.localizedDescription)")
                        self.finish(exitCode: 8)
                    } else {
                        self.emitError("Movie finalization failed: \(error.localizedDescription)")
                        self.state = .ready
                    }
                    return
                }
                let savedURL = self.outputURL
                self.writer = nil
                self.writerInput = nil
                self.outputURL = nil
                self.state = .ready
                if self.mode == .record || exitWhenFinished || self.shutdownRequested {
                    self.finish(exitCode: self.wroteFrames ? 0 : 7)
                    return
                }
                if self.wroteFrames {
                    self.emitEvent(["event": "saved", "outputPath": savedURL?.path ?? ""])
                } else {
                    self.emitError("No video frames were received from the iOS capture device.")
                }
            }
        }
    }

    private func finish(exitCode: Int32) {
        finished = true
        state = .closed
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
        DispatchQueue.main.async {
            Foundation.exit(exitCode)
        }
    }

    private func prepareWriter(sampleBuffer: CMSampleBuffer) throws {
        guard writer == nil else { return }
        guard let outputURL else {
            throw NSError(domain: "screen_recorder_ios", code: 12, userInfo: [NSLocalizedDescriptionKey: "Missing output path"])
        }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(domain: "screen_recorder_ios", code: 13, userInfo: [NSLocalizedDescriptionKey: "First frame did not contain an image buffer"])
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(domain: "screen_recorder_ios", code: 14, userInfo: [NSLocalizedDescriptionKey: "Cannot add movie writer input"])
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "screen_recorder_ios", code: 15, userInfo: [NSLocalizedDescriptionKey: "Movie writer failed to start"])
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startSession(atSourceTime: timestamp)
        self.writer = writer
        self.writerInput = input
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        do {
            if state == .preparing {
                state = .ready
                if mode == .serve {
                    emitEvent(["event": "ready"])
                    return
                }
                state = .recording
            }
            guard state == .recording else { return }
            try prepareWriter(sampleBuffer: sampleBuffer)
            guard let input = writerInput, input.isReadyForMoreMediaData else {
                return
            }
            if mode == .serve && !startedEmitted {
                emitEvent(["event": "started"])
                startedEmitted = true
            }
            if !input.append(sampleBuffer) {
                eprint("Failed to append video frame: \(writer?.error?.localizedDescription ?? "unknown error")")
                if mode == .record {
                    shutdown()
                } else {
                    emitError("Failed to append video frame: \(writer?.error?.localizedDescription ?? "unknown error")")
                }
            } else {
                wroteFrames = true
            }
        } catch {
            eprint("Recording failed: \(error.localizedDescription)")
            if mode == .record {
                shutdown()
            } else {
                emitError("Recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func emitError(_ message: String) {
        emitEvent(["event": "error", "message": message])
    }

    private func emitEvent(_ object: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        print(line)
        fflush(stdout)
    }
}

final class RecorderSignalBridge {
    static let shared = RecorderSignalBridge()
    weak var recorder: MovieRecorder?

    func shutdown() {
        recorder?.shutdown()
    }
}

func eprint(_ string: String) {
    if let data = (string + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

func usage() -> Never {
    print("""
    Usage:
      ios_physical_capture list
      ios_physical_capture record --device-id ID --output PATH
      ios_physical_capture serve --device-id ID
    """)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "list":
    printDeviceList()

case "record":
    guard let deviceID = value(after: "--device-id", in: args) else { usage() }
    guard let outputPath = value(after: "--output", in: args) else { usage() }
    let devices = discoverIOSDevices()
    guard let selected = devices.first(where: { $0.id == deviceID }) else {
        eprint("No physical iOS capture device matched id \(deviceID).")
        exit(4)
    }
    do {
        let recorder = MovieRecorder(mode: .record)
        try recorder.start(device: selected.device, outputURL: URL(fileURLWithPath: outputPath))
    } catch {
        eprint("Recording failed: \(error.localizedDescription)")
        exit(6)
    }

case "serve":
    guard let deviceID = value(after: "--device-id", in: args) else { usage() }
    let devices = discoverIOSDevices()
    guard let selected = devices.first(where: { $0.id == deviceID }) else {
        eprint("No physical iOS capture device matched id \(deviceID).")
        exit(4)
    }
    do {
        let recorder = MovieRecorder(mode: .serve)
        try recorder.start(device: selected.device, outputURL: nil)
    } catch {
        eprint("Capture failed: \(error.localizedDescription)")
        exit(6)
    }

default:
    usage()
}
