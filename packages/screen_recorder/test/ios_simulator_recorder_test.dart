import 'dart:async';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies iOS Simulator recording through the public API and fake commands.
void main() {
  group('iOS Simulator ScreenRecorder', () {
    test('lists iOS Simulator Recording Devices from simctl output', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addRun(
          <String>['xcrun', 'simctl', 'list', 'devices'],
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
== Devices ==
-- iOS 18.2 --
    iPhone 16 Pro (11111111-1111-1111-1111-111111111111) (Booted)
    iPhone SE (22222222-2222-2222-2222-222222222222) (Shutdown)
    Unavailable Phone (33333333-3333-3333-3333-333333333333) (Shutdown) (unavailable, runtime profile not found)
-- tvOS 18.2 --
    Apple TV (44444444-4444-4444-4444-444444444444) (Shutdown)
''',
            stderr: '',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosSimulator(
        commandRunner: commandRunner,
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(devices, <RecordingDevice>[
        const RecordingDevice(
          id: '11111111-1111-1111-1111-111111111111',
          name: 'iPhone 16 Pro',
          platform: RecordingDevicePlatform.iosSimulator,
        ),
        const RecordingDevice(
          id: '22222222-2222-2222-2222-222222222222',
          name: 'iPhone SE',
          platform: RecordingDevicePlatform.iosSimulator,
        ),
      ]);
    });

    test('resolves simulators by UDID, name, and name prefix', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'iPhone 16 Pro',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosSimulator(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_simulator_test_')
          .path;

      final RecordingSession byId = await recorder.startRecord(
        deviceSelector: '11111111-1111-1111-1111-111111111111',
        outputDirectory: outputDirectory,
        outputName: 'by_id',
      );
      await recorder.discardRecord(byId);

      final RecordingSession byName = await recorder.startRecord(
        deviceSelector: 'iPhone 16 Pro',
        outputDirectory: outputDirectory,
        outputName: 'by_name',
      );
      await recorder.discardRecord(byName);

      final RecordingSession byPrefix = await recorder.startRecord(
        deviceSelector: 'iph',
        outputDirectory: outputDirectory,
        outputName: 'by_prefix',
      );
      await recorder.discardRecord(byPrefix);

      expect(byId.device.id, '11111111-1111-1111-1111-111111111111');
      expect(byName.device.id, '11111111-1111-1111-1111-111111111111');
      expect(byPrefix.device.id, '11111111-1111-1111-1111-111111111111');
      expect(
          commandRunner.startedCommands,
          contains(equals(<String>[
            'xcrun',
            'simctl',
            'io',
            '11111111-1111-1111-1111-111111111111',
            'recordVideo',
            byId.expectedOutputPath,
          ])));
      expect(byId.expectedOutputPath, endsWith('by_id.mov'));
    });

    test('stops simulator recordVideo and returns a finalized mov result',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'iPhone 16 Pro',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosSimulator(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_simulator_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'iPhone 16 Pro',
        outputDirectory: outputDirectory,
        outputName: 'sim_recording',
      );
      commandRunner.completeProcessWithFile(
        outputPath: session.expectedOutputPath,
        bytes: <int>[9, 8, 7, 6],
      );

      final RecordingResult result = await recorder.stopRecord(session);

      expect(result.outputPath, endsWith('sim_recording.mov'));
      expect(result.mimeType, 'video/quicktime');
      expect(File(result.outputPath).readAsBytesSync(), <int>[9, 8, 7, 6]);
      expect(result.fileSizeBytes, 4);
    });

    test('discards simulator recording and removes local output', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'iPhone 16 Pro',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosSimulator(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_simulator_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'iPhone 16 Pro',
        outputDirectory: outputDirectory,
        outputName: 'discarded_sim',
      );
      File(session.expectedOutputPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 1, 1]);

      await recorder.discardRecord(session);

      expect(File(session.expectedOutputPath).existsSync(), isFalse);
    });

    test(
        'reports simctl discovery failures with missing-dependency code and raw output',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addRun(
          <String>['xcrun', 'simctl', 'list', 'devices'],
          const ScreenRecorderCommandResult(
            exitCode: 72,
            stdout: '',
            stderr: 'xcrun: error: unable to find utility "simctl"',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosSimulator(
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
                contains('unable to find utility'),
              ),
        ),
      );
    });

    test('reports stop failure when simulator output is missing', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'iPhone 16 Pro',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosSimulator(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_simulator_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'iPhone 16 Pro',
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
  _FakeScreenRecorderProcess? _lastProcess;

  void addRun(List<String> command, ScreenRecorderCommandResult result) {
    _runResults[_key(command)] = result;
  }

  void addSimulatorDeviceList(Map<String, String> devicesById) {
    final StringBuffer buffer = StringBuffer('''
== Devices ==
-- iOS 18.2 --
''');
    for (final MapEntry<String, String> entry in devicesById.entries) {
      buffer.writeln('    ${entry.value} (${entry.key}) (Booted)');
    }
    addRun(
      <String>['xcrun', 'simctl', 'list', 'devices'],
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
    final String key = _key(<String>[executable, ...arguments]);
    final ScreenRecorderCommandResult? result = _runResults[key];
    if (result == null) {
      throw StateError('Unexpected command: $key');
    }
    return result;
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

  String _key(List<String> command) => command.join('\u{1f}');
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
