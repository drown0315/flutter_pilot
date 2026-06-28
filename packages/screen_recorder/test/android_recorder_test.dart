import 'dart:async';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies Android recording behavior through the public API and fake commands.
void main() {
  group('Android ScreenRecorder', () {
    test('lists Android Recording Devices from adb output', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addRun(
          <String>['adb', 'devices'],
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
List of devices attached
emulator-5554\tdevice
PHK110\tdevice
offline-1\toffline
''',
            stderr: '',
          ),
        )
        ..addRun(
          <String>[
            'adb',
            '-s',
            'emulator-5554',
            'shell',
            'getprop',
            'ro.product.model',
          ],
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: 'Pixel_9\n',
            stderr: '',
          ),
        )
        ..addRun(
          <String>[
            'adb',
            '-s',
            'PHK110',
            'shell',
            'getprop',
            'ro.product.model',
          ],
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: 'OnePlus 13\n',
            stderr: '',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.android(
        commandRunner: commandRunner,
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(devices, <RecordingDevice>[
        const RecordingDevice(
          id: 'emulator-5554',
          name: 'Pixel_9',
          platform: RecordingDevicePlatform.android,
        ),
        const RecordingDevice(
          id: 'PHK110',
          name: 'OnePlus 13',
          platform: RecordingDevicePlatform.android,
        ),
      ]);
    });

    test('resolves Android devices by id, name, and name prefix', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addAndroidDeviceList(<String, String>{'PHK110': 'OnePlus 13'});
      final ScreenRecorder recorder = ScreenRecorder.android(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_android_test_')
          .path;

      final RecordingSession byId = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'by_id',
      );
      await recorder.discardRecord(byId);

      final RecordingSession byName = await recorder.startRecord(
        deviceSelector: 'OnePlus 13',
        outputDirectory: outputDirectory,
        outputName: 'by_name',
      );
      await recorder.discardRecord(byName);

      final RecordingSession byPrefix = await recorder.startRecord(
        deviceSelector: 'one',
        outputDirectory: outputDirectory,
        outputName: 'by_prefix',
      );
      await recorder.discardRecord(byPrefix);

      expect(byId.device.id, 'PHK110');
      expect(byName.device.id, 'PHK110');
      expect(byPrefix.device.id, 'PHK110');
    });

    test('records Android devices through scrcpy when available', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addAndroidDeviceList(<String, String>{'PHK110': 'OnePlus 13'});
      final ScreenRecorder recorder = ScreenRecorder.android(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_android_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'android_recording',
      );
      final RecordingResult result = await recorder.stopRecord(session);

      expect(result.outputPath, endsWith('android_recording.mp4'));
      expect(File(result.outputPath).readAsBytesSync(), <int>[6, 7, 8, 9, 10]);
      expect(result.fileSizeBytes, 5);
      expect(
        commandRunner.startedCommands,
        contains(
          equals(<String>[
            'scrcpy',
            '--serial',
            'PHK110',
            '--no-audio',
            '--no-playback',
            '--no-window',
            '--record=${session.expectedOutputPath}',
          ]),
        ),
      );
      expect(
        commandRunner.lastProcess?.killedWithSignal,
        ProcessSignal.sigterm,
      );
      expect(
        commandRunner.runCommands.any(
          (List<String> command) => command.contains('pull'),
        ),
        isFalse,
      );
    });

    test(
      'falls back to native screenrecord when scrcpy exits immediately',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addAndroidDeviceList(<String, String>{'PHK110': 'OnePlus 13'})
          ..scrcpyStartFailure = 'scrcpy failed';
        final ScreenRecorder recorder = ScreenRecorder.android(
          commandRunner: commandRunner,
        );
        final String outputDirectory = Directory.systemTemp
            .createTempSync('screen_recorder_android_test_')
            .path;

        final RecordingSession session = await recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'native_recording',
        );
        commandRunner.addPullForSession(
          session: session,
          bytes: <int>[1, 2, 3, 4, 5],
        );
        final RecordingResult result = await recorder.stopRecord(session);

        expect(File(result.outputPath).readAsBytesSync(), <int>[1, 2, 3, 4, 5]);
        expect(
          commandRunner.runCommands,
          contains(
            equals(<String>[
              'adb',
              '-s',
              'PHK110',
              'pull',
              '/sdcard/screen_recorder_${session.id}.mp4',
              result.outputPath,
            ]),
          ),
        );
        expect(
          commandRunner.runCommands,
          contains(
            equals(<String>[
              'adb',
              '-s',
              'PHK110',
              'shell',
              'rm',
              '-f',
              '/sdcard/screen_recorder_${session.id}.mp4',
            ]),
          ),
        );
      },
    );

    test(
      'falls back to host frame capture when screenrecord cannot open output',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addAndroidDeviceList(<String, String>{'PHK110': 'OnePlus 13'})
          ..scrcpyStartFailure = 'scrcpy failed'
          ..screenrecordStartFailure = 'Unable to open file: Permission denied';
        final ScreenRecorder recorder = ScreenRecorder.android(
          commandRunner: commandRunner,
        );
        final String outputDirectory = Directory.systemTemp
            .createTempSync('screen_recorder_android_test_')
            .path;

        final RecordingSession session = await recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'android_fallback',
        );
        final RecordingResult result = await recorder.stopRecord(session);

        expect(result.outputPath, endsWith('android_fallback.mp4'));
        expect(File(result.outputPath).readAsBytesSync(), <int>[9, 8, 7, 6]);
        expect(commandRunner.runBytesCommands, isNotEmpty);
        expect(commandRunner.runBytesCommands.first, <String>[
          'adb',
          '-s',
          'PHK110',
          'exec-out',
          'screencap',
          '-p',
        ]);
        expect(
          commandRunner.runCommands,
          contains(
            allOf(
              contains('ffmpeg'),
              contains('-framerate'),
              contains('4'),
              contains(result.outputPath),
            ),
          ),
        );
        expect(
          commandRunner.runCommands.any(
            (List<String> command) => command.contains('pull'),
          ),
          isFalse,
        );
      },
    );

    test(
      'discards Android screenrecord without pulling a local file',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addAndroidDeviceList(<String, String>{'PHK110': 'OnePlus 13'})
          ..scrcpyStartFailure = 'scrcpy failed';
        final ScreenRecorder recorder = ScreenRecorder.android(
          commandRunner: commandRunner,
        );
        final String outputDirectory = Directory.systemTemp
            .createTempSync('screen_recorder_android_test_')
            .path;

        final RecordingSession session = await recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'discarded_android',
        );
        await recorder.discardRecord(session);

        expect(File(session.expectedOutputPath).existsSync(), isFalse);
        expect(
          commandRunner.runCommands.any(
            (List<String> command) => command.contains('pull'),
          ),
          isFalse,
        );
        expect(
          commandRunner.runCommands,
          contains(
            equals(<String>[
              'adb',
              '-s',
              'PHK110',
              'shell',
              'rm',
              '-f',
              '/sdcard/screen_recorder_${session.id}.mp4',
            ]),
          ),
        );
      },
    );

    test(
      'reports adb discovery failures with missing-dependency code and raw output',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addRun(
            <String>['adb', 'devices'],
            const ScreenRecorderCommandResult(
              exitCode: 127,
              stdout: '',
              stderr: 'adb: command not found',
            ),
          );
        final ScreenRecorder recorder = ScreenRecorder.android(
          commandRunner: commandRunner,
        );

        await expectLater(
          recorder.listDevices(),
          throwsA(
            isA<ScreenRecorderException>()
                .having(
                  (ScreenRecorderException exception) => exception.code,
                  'code',
                  ScreenRecorderErrorCode.missingDependency,
                )
                .having(
                  (ScreenRecorderException exception) => exception.rawOutput,
                  'rawOutput',
                  contains('adb: command not found'),
                ),
          ),
        );
      },
    );

    test(
      'reports Android pull failures with stop-failed code and raw output',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addAndroidDeviceList(<String, String>{'PHK110': 'OnePlus 13'})
          ..scrcpyStartFailure = 'scrcpy failed';
        final ScreenRecorder recorder = ScreenRecorder.android(
          commandRunner: commandRunner,
        );
        final String outputDirectory = Directory.systemTemp
            .createTempSync('screen_recorder_android_test_')
            .path;

        final RecordingSession session = await recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'pull_failure',
        );
        commandRunner.addRun(
          <String>[
            'adb',
            '-s',
            'PHK110',
            'pull',
            '/sdcard/screen_recorder_${session.id}.mp4',
            session.expectedOutputPath,
          ],
          const ScreenRecorderCommandResult(
            exitCode: 1,
            stdout: '',
            stderr: 'remote object does not exist',
          ),
        );

        await expectLater(
          recorder.stopRecord(session),
          throwsA(
            isA<ScreenRecorderException>()
                .having(
                  (ScreenRecorderException exception) => exception.code,
                  'code',
                  ScreenRecorderErrorCode.stopFailed,
                )
                .having(
                  (ScreenRecorderException exception) => exception.rawOutput,
                  'rawOutput',
                  contains('remote object does not exist'),
                ),
          ),
        );
        expect(
          commandRunner.runCommands,
          contains(
            equals(<String>[
              'adb',
              '-s',
              'PHK110',
              'shell',
              'rm',
              '-f',
              '/sdcard/screen_recorder_${session.id}.mp4',
            ]),
          ),
        );
      },
    );
  });
}

class _FakeCommandRunner implements ScreenRecorderCommandRunner {
  final Map<String, ScreenRecorderCommandResult> _runResults =
      <String, ScreenRecorderCommandResult>{};
  final Map<String, List<int>> _pullBytes = <String, List<int>>{};
  final List<List<String>> runCommands = <List<String>>[];
  final List<List<String>> runBytesCommands = <List<String>>[];
  final List<List<String>> startedCommands = <List<String>>[];
  String? scrcpyStartFailure;
  String? screenrecordStartFailure;
  _FakeScreenRecorderProcess? lastProcess;

  void addRun(List<String> command, ScreenRecorderCommandResult result) {
    _runResults[_key(command)] = result;
  }

  void addAndroidDeviceList(Map<String, String> devicesById) {
    final StringBuffer buffer = StringBuffer('List of devices attached\n');
    for (final String deviceId in devicesById.keys) {
      buffer.writeln('$deviceId\tdevice');
      addRun(
        <String>['adb', '-s', deviceId, 'shell', 'getprop', 'ro.product.model'],
        ScreenRecorderCommandResult(
          exitCode: 0,
          stdout: '${devicesById[deviceId]}\n',
          stderr: '',
        ),
      );
    }
    addRun(
      <String>['adb', 'devices'],
      ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: buffer.toString(),
        stderr: '',
      ),
    );
  }

  void addPullForSession({
    required RecordingSession session,
    required List<int> bytes,
  }) {
    _pullBytes[_key(<String>[
      'adb',
      '-s',
      session.device.id,
      'pull',
      '/sdcard/screen_recorder_${session.id}.mp4',
      session.expectedOutputPath,
    ])] = bytes;
  }

  @override
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    runCommands.add(<String>[executable, ...arguments]);
    final String key = _key(<String>[executable, ...arguments]);
    final List<int>? pullBytes = _pullBytes[key];
    if (pullBytes != null) {
      File(arguments.last)
        ..createSync(recursive: true)
        ..writeAsBytesSync(pullBytes);
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
    }
    if (executable == 'adb' &&
        arguments.length == 5 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'ps' &&
        arguments[4] == '-A') {
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: 'shell        1234  1  screenrecord\n',
        stderr: '',
      );
    }
    if (executable == 'adb' &&
        arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'ls' &&
        arguments[4] == '-l') {
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: '-rw-rw---- 1 shell sdcard_rw 5 screen_recorder.mp4\n',
        stderr: '',
      );
    }
    if (executable == 'adb' &&
        arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'kill' &&
        arguments[4] == '-2') {
      lastProcess?.complete();
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
    }
    final ScreenRecorderCommandResult? result = _runResults[key];
    if (result == null &&
        executable == 'adb' &&
        arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'rm' &&
        arguments[4] == '-f') {
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
    }
    if (executable == 'ffmpeg' &&
        arguments.length == 1 &&
        arguments.first == '-version') {
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: 'ffmpeg version test\n',
        stderr: '',
      );
    }
    if (executable == 'ffmpeg' &&
        arguments.any(
          (String argument) => argument.endsWith('frame_%06d.png'),
        )) {
      File(arguments.last)
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[9, 8, 7, 6]);
      return const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
    }
    if (result == null) {
      throw StateError('Unexpected command: $key');
    }
    return result;
  }

  @override
  Future<ScreenRecorderByteCommandResult> runBytes(
    String executable,
    List<String> arguments,
  ) async {
    runBytesCommands.add(<String>[executable, ...arguments]);
    if (executable == 'adb' &&
        arguments.length == 5 &&
        arguments[2] == 'exec-out' &&
        arguments[3] == 'screencap' &&
        arguments[4] == '-p') {
      return const ScreenRecorderByteCommandResult(
        exitCode: 0,
        stdoutBytes: <int>[137, 80, 78, 71],
        stderr: '',
      );
    }
    throw StateError(
      'Unexpected byte command: ${<String>[executable, ...arguments]}',
    );
  }

  @override
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startedCommands.add(<String>[executable, ...arguments]);
    if (executable == 'scrcpy') {
      final String outputPath = arguments
          .firstWhere((String argument) => argument.startsWith('--record='))
          .substring('--record='.length);
      lastProcess = _FakeScreenRecorderProcess(
        immediateError: scrcpyStartFailure,
        outputPathOnKill: scrcpyStartFailure == null ? outputPath : null,
      );
      return lastProcess!;
    }
    lastProcess = _FakeScreenRecorderProcess(
      immediateError: screenrecordStartFailure,
    );
    return lastProcess!;
  }

  String _key(List<String> command) => command.join('\u{1f}');
}

class _FakeScreenRecorderProcess implements ScreenRecorderProcess {
  _FakeScreenRecorderProcess({String? immediateError, this.outputPathOnKill})
      : _stderr = immediateError ?? '' {
    if (immediateError != null) {
      _exitCode.complete(1);
    }
  }

  final Completer<int> _exitCode = Completer<int>();
  final String _stderr;
  final String? outputPathOnKill;
  ProcessSignal? killedWithSignal;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<String> get stdout async => '';

  @override
  Future<String> get stderr async => _stderr;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killedWithSignal = signal;
    final String? outputPath = outputPathOnKill;
    if (outputPath != null) {
      File(outputPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[6, 7, 8, 9, 10]);
    }
    complete();
    return true;
  }

  void complete() {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
  }
}
