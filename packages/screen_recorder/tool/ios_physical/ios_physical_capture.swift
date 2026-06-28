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
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "screen-recorder.ios-physical.video")
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var stopping = false
    private var finished = false
    private var wroteFrames = false

    func start(device: AVCaptureDevice, outputURL: URL) throws {
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

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        signal(SIGTERM) { _ in
            RecorderSignalBridge.shared.stop()
        }
        signal(SIGINT) { _ in
            RecorderSignalBridge.shared.stop()
        }
        RecorderSignalBridge.shared.recorder = self

        session.startRunning()
        RunLoop.main.run()
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.stopping { return }
            self.stopping = true
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            guard let writer = self.writer else {
                eprint("No video frames were received from the iOS capture device.")
                self.finish(exitCode: 7)
                return
            }
            self.writerInput?.markAsFinished()
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, !self.finished else { return }
                eprint("Timed out while finalizing the movie file.")
                writer.cancelWriting()
                self.finish(exitCode: 8)
            }
            writer.finishWriting { [weak self] in
                guard let self else { return }
                if let error = writer.error {
                    eprint("Movie finalization failed: \(error.localizedDescription)")
                    self.finish(exitCode: 8)
                    return
                }
                self.finish(exitCode: self.wroteFrames ? 0 : 7)
            }
        }
    }

    private func finish(exitCode: Int32) {
        finished = true
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
        if stopping { return }
        do {
            try prepareWriter(sampleBuffer: sampleBuffer)
            guard let input = writerInput, input.isReadyForMoreMediaData else {
                return
            }
            if !input.append(sampleBuffer) {
                eprint("Failed to append video frame: \(writer?.error?.localizedDescription ?? "unknown error")")
                stop()
            } else {
                wroteFrames = true
            }
        } catch {
            eprint("Recording failed: \(error.localizedDescription)")
            stop()
        }
    }
}

final class RecorderSignalBridge {
    static let shared = RecorderSignalBridge()
    weak var recorder: MovieRecorder?

    func stop() {
        recorder?.stop()
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
        let recorder = MovieRecorder()
        try recorder.start(device: selected.device, outputURL: URL(fileURLWithPath: outputPath))
    } catch {
        eprint("Recording failed: \(error.localizedDescription)")
        exit(6)
    }

default:
    usage()
}
