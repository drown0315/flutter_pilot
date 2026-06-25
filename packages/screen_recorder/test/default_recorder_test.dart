import 'dart:async';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies default multi-backend device resolution through the public API.
void main() {
  group('Default ScreenRecorder', () {
    test('lists devices from all backends in default priority order', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addAndroidDeviceList(<String, String>{'android-1': 'Android Phone'})
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'iPhone Simulator',
        })
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Physical iPhone',
        });
      final ScreenRecorder recorder = ScreenRecorder.defaultRecorder(
        commandRunner: commandRunner,
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(
        devices.map((RecordingDevice device) => device.platform),
        <RecordingDevicePlatform>[
          RecordingDevicePlatform.android,
          RecordingDevicePlatform.iosSimulator,
          RecordingDevicePlatform.iosPhysical,
        ],
      );
      expect(
        devices.map((RecordingDevice device) => device.name),
        <String>['Android Phone', 'iPhone Simulator', 'Physical iPhone'],
      );
    });

    test('resolves Android before iOS Simulator and physical iOS', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addAndroidDeviceList(<String, String>{'android-1': 'Shared Phone'})
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'Shared Phone',
        })
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Shared Phone',
        });
      final ScreenRecorder recorder = ScreenRecorder.defaultRecorder(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_default_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'Shared',
        outputDirectory: outputDirectory,
        outputName: 'priority',
      );

      expect(session.device.platform, RecordingDevicePlatform.android);
      expect(session.device.id, 'android-1');
      expect(commandRunner.simctlListCount, 0);
      expect(commandRunner.helperListCount, 0);

      await recorder.discardRecord(session);
    });

    test('uses platform filter to select iOS Simulator when names overlap',
        () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addAndroidDeviceList(<String, String>{'android-1': 'Shared Phone'})
        ..addSimulatorDeviceList(<String, String>{
          '11111111-1111-1111-1111-111111111111': 'Shared Phone',
        })
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Shared Phone',
        });
      final ScreenRecorder recorder = ScreenRecorder.defaultRecorder(
        commandRunner: commandRunner,
        platform: RecordingDevicePlatform.iosSimulator,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_default_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'Shared',
        outputDirectory: outputDirectory,
        outputName: 'simulator_only',
      );

      expect(session.device.platform, RecordingDevicePlatform.iosSimulator);
      expect(session.expectedOutputPath, endsWith('simulator_only.mov'));
      expect(commandRunner.adbDevicesCount, 0);
      expect(commandRunner.helperListCount, 0);

      await recorder.discardRecord(session);
    });

    test('reports device-not-found when no default backend matches', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addAndroidDeviceList(<String, String>{})
        ..addSimulatorDeviceList(<String, String>{})
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{});
      final ScreenRecorder recorder = ScreenRecorder.defaultRecorder(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_default_test_')
          .path;

      await expectLater(
        recorder.startRecord(
          deviceSelector: 'missing',
          outputDirectory: outputDirectory,
          outputName: 'missing',
        ),
        throwsA(
          isA<ScreenRecorderException>().having(
            (ScreenRecorderException exception) => exception.code,
            'code',
            ScreenRecorderErrorCode.deviceNotFound,
          ),
        ),
      );
    });
  });
}

class _FakeCommandRunner implements ScreenRecorderCommandRunner {
  final Map<String, ScreenRecorderCommandResult> _runResults =
      <String, ScreenRecorderCommandResult>{};
  final List<List<String>> startedCommands = <List<String>>[];
  final String helperPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}screen_recorder_ios_physical_capture';
  int adbDevicesCount = 0;
  int simctlListCount = 0;
  int helperListCount = 0;
  _FakeScreenRecorderProcess? lastProcess;

  void addAndroidDeviceList(Map<String, String> devicesById) {
    final StringBuffer buffer = StringBuffer('List of devices attached\n');
    for (final MapEntry<String, String> entry in devicesById.entries) {
      buffer.writeln('${entry.key}\tdevice');
      addRun(
        <String>[
          'adb',
          '-s',
          entry.key,
          'shell',
          'getprop',
          'ro.product.model',
        ],
        ScreenRecorderCommandResult(
          exitCode: 0,
          stdout: '${entry.value}\n',
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

  void addSwiftBuild() {
    addRun(
      <String>['swiftc'],
      const ScreenRecorderCommandResult(exitCode: 0, stdout: '', stderr: ''),
    );
  }

  void addPhysicalDeviceList(Map<String, String> devicesById) {
    final StringBuffer buffer = StringBuffer('id\tname\tmodel\tmanufacturer\n');
    for (final MapEntry<String, String> entry in devicesById.entries) {
      buffer.writeln('${entry.key}\t${entry.value}\tiOS Device\tApple Inc.');
    }
    _runResults['helper:list'] = ScreenRecorderCommandResult(
      exitCode: 0,
      stdout: buffer.toString(),
      stderr: '',
    );
  }

  void addRun(List<String> command, ScreenRecorderCommandResult result) {
    if (command.length == 1 && command.first == 'swiftc') {
      _runResults['swiftc'] = result;
      return;
    }
    _runResults[_key(command)] = result;
  }

  @override
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    if (executable == 'adb' &&
        arguments.length == 1 &&
        arguments.first == 'devices') {
      adbDevicesCount++;
    }
    if (executable == 'swiftc') {
      final ScreenRecorderCommandResult? result = _runResults['swiftc'];
      if (result == null) {
        throw StateError('Unexpected swift build command');
      }
      return result;
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
          exitCode: 0, stdout: '', stderr: '');
    }
    if (executable == 'adb' &&
        arguments.length == 6 &&
        arguments[2] == 'shell' &&
        arguments[3] == 'rm' &&
        arguments[4] == '-f') {
      return const ScreenRecorderCommandResult(
          exitCode: 0, stdout: '', stderr: '');
    }
    if (executable == 'xcrun' &&
        arguments.length == 3 &&
        arguments[0] == 'simctl' &&
        arguments[1] == 'list' &&
        arguments[2] == 'devices') {
      simctlListCount++;
    }
    if (executable == helperPath &&
        arguments.length == 1 &&
        arguments.first == 'list') {
      helperListCount++;
      return _runResults['helper:list'] ??
          (throw StateError('Unexpected helper list command'));
    }
    final ScreenRecorderCommandResult? result =
        _runResults[_key(<String>[executable, ...arguments])];
    if (result == null) {
      throw StateError(
          'Unexpected command: ${<String>[executable, ...arguments]}');
    }
    return result;
  }

  @override
  Future<ScreenRecorderByteCommandResult> runBytes(
    String executable,
    List<String> arguments,
  ) async {
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
    lastProcess = _FakeScreenRecorderProcess();
    return lastProcess!;
  }

  String _key(List<String> command) => command.join('\u{1f}');
}

class _FakeScreenRecorderProcess implements ScreenRecorderProcess {
  final Completer<int> _exitCode = Completer<int>();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<String> get stdout async => '';

  @override
  Future<String> get stderr async => '';

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    complete();
    return true;
  }

  void complete() {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
  }
}
