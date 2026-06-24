import 'dart:async';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies physical iOS recording through the public API and fake commands.
void main() {
  group('Physical iOS ScreenRecorder', () {
    test('lists physical iOS Recording Devices from helper output', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addHelperList(
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
id\tname\tmodel\tmanufacturer
ios-device-1\tDrown iPhone\tiOS Device\tApple Inc.
ios-device-2\tOffice iPhone\tiOS Device\tApple Inc.
''',
            stderr: '',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(devices, <RecordingDevice>[
        const RecordingDevice(
          id: 'ios-device-1',
          name: 'Drown iPhone',
          platform: RecordingDevicePlatform.iosPhysical,
        ),
        const RecordingDevice(
          id: 'ios-device-2',
          name: 'Office iPhone',
          platform: RecordingDevicePlatform.iosPhysical,
        ),
      ]);
    });

    test('resolves physical iOS devices by id, name, and name prefix',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;

      final RecordingSession byId = await recorder.startRecord(
        deviceSelector: 'ios-device-1',
        outputDirectory: outputDirectory,
        outputName: 'by_id',
      );
      await recorder.discardRecord(byId);

      final RecordingSession byName = await recorder.startRecord(
        deviceSelector: 'Drown iPhone',
        outputDirectory: outputDirectory,
        outputName: 'by_name',
      );
      await recorder.discardRecord(byName);

      final RecordingSession byPrefix = await recorder.startRecord(
        deviceSelector: 'dro',
        outputDirectory: outputDirectory,
        outputName: 'by_prefix',
      );
      await recorder.discardRecord(byPrefix);

      expect(byId.device.id, 'ios-device-1');
      expect(byName.device.id, 'ios-device-1');
      expect(byPrefix.device.id, 'ios-device-1');
      expect(
          commandRunner.startedCommands,
          contains(equals(<String>[
            commandRunner.helperPath,
            'record',
            '--device-id',
            'ios-device-1',
            '--output',
            byId.expectedOutputPath,
          ])));
      expect(byId.expectedOutputPath, endsWith('by_id.mov'));
    });

    test('stops physical iOS helper and returns a finalized mov result',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'Drown iPhone',
        outputDirectory: outputDirectory,
        outputName: 'physical_recording',
      );
      commandRunner.completeProcessWithFile(
        outputPath: session.expectedOutputPath,
        bytes: <int>[5, 4, 3, 2],
      );

      final RecordingResult result = await recorder.stopRecord(session);

      expect(result.outputPath, endsWith('physical_recording.mov'));
      expect(result.mimeType, 'video/quicktime');
      expect(File(result.outputPath).readAsBytesSync(), <int>[5, 4, 3, 2]);
      expect(result.fileSizeBytes, 4);
    });

    test(
        'reports missing Swift toolchain with missing-dependency code and raw output',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addRun(
          <String>['swiftc'],
          const ScreenRecorderCommandResult(
            exitCode: 1,
            stdout: '',
            stderr: 'xcrun: error: toolchain not found',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
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
                contains('toolchain not found'),
              ),
        ),
      );
    });

    test(
        'reports helper list failures with permission-denied code and raw output',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addHelperList(
          const ScreenRecorderCommandResult(
            exitCode: 3,
            stdout: '',
            stderr: 'camera permission denied',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );

      await expectLater(
        recorder.listDevices(),
        throwsA(
          isA<ScreenRecorderException>()
              .having(
                (ScreenRecorderException exception) => exception.code,
                'code',
                ScreenRecorderErrorCode.permissionDenied,
              )
              .having(
                (ScreenRecorderException exception) => exception.rawOutput,
                'rawOutput',
                contains('camera permission denied'),
              ),
        ),
      );
    });

    test('reports stop failure when physical iOS output is missing', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'Drown iPhone',
        outputDirectory: outputDirectory,
        outputName: 'missing_output',
      );

      await expectLater(
        recorder.stopRecord(session),
        throwsA(
          isA<ScreenRecorderException>().having(
            (ScreenRecorderException exception) => exception.code,
            'code',
            ScreenRecorderErrorCode.stopFailed,
          ),
        ),
      );
    });
  });
}

class _FakeCommandRunner implements ScreenRecorderCommandRunner {
  final Map<String, ScreenRecorderCommandResult> _runResults =
      <String, ScreenRecorderCommandResult>{};
  final List<List<String>> runCommands = <List<String>>[];
  final List<List<String>> startedCommands = <List<String>>[];
  final String helperPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}screen_recorder_ios_physical_capture';
  _FakeScreenRecorderProcess? _lastProcess;

  void addSwiftBuild() {
    addRun(
      <String>['swiftc'],
      const ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      ),
    );
  }

  void addRun(List<String> command, ScreenRecorderCommandResult result) {
    if (command.length == 1 && command.first == 'swiftc') {
      _runResults[_buildKey] = result;
      return;
    }
    _runResults[command.join('\u{1f}')] = result;
  }

  void addHelperList(ScreenRecorderCommandResult result) {
    _runResults['helper:list'] = result;
  }

  void addPhysicalDeviceList(Map<String, String> devicesById) {
    final StringBuffer buffer = StringBuffer('id\tname\tmodel\tmanufacturer\n');
    for (final MapEntry<String, String> entry in devicesById.entries) {
      buffer.writeln('${entry.key}\t${entry.value}\tiOS Device\tApple Inc.');
    }
    addHelperList(
      ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: buffer.toString(),
        stderr: '',
      ),
    );
  }

  @override
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    runCommands.add(<String>[executable, ...arguments]);
    if (executable == 'swiftc') {
      return _runResults[_buildKey] ??
          (throw StateError('Unexpected swift build command'));
    }
    if (arguments.length == 1 && arguments.first == 'list') {
      return _runResults['helper:list'] ??
          (throw StateError('Unexpected helper list command'));
    }
    throw StateError(
        'Unexpected command: ${<String>[executable, ...arguments]}');
  }

  @override
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startedCommands.add(<String>[executable, ...arguments]);
    final _FakeScreenRecorderProcess process = _FakeScreenRecorderProcess();
    _lastProcess = process;
    return process;
  }

  void completeProcessWithFile({
    required String outputPath,
    required List<int> bytes,
  }) {
    _lastProcess?.onKill = () {
      File(outputPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    };
  }

  static const String _buildKey = 'swiftc';
}

class _FakeScreenRecorderProcess implements ScreenRecorderProcess {
  final Completer<int> _exitCode = Completer<int>();
  void Function()? onKill;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill() {
    onKill?.call();
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
    return true;
  }
}
