import 'dart:async';
import 'dart:convert';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies the shared Test Execution Session lifecycle without launching a
/// real Flutter app.
void main() {
  test(
    'starts without Target Device discovery when Flutter default is allowed',
    () async {
      final FakeDeviceDiscovery discovery = FakeDeviceDiscovery();
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final TestExecutionSessionFactory factory =
          DefaultTestExecutionSessionFactory(
            deviceDiscovery: discovery,
            launcher: TargetAppLauncher(starter: starter),
          );

      final Future<TestExecutionSession> sessionFuture = factory.start(
        deviceSelector: null,
        flavor: 'staging',
        target: 'lib/main_staging.dart',
        recordingRequired: false,
        launchHeartbeatEnabled: false,
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.started',
          'params': <String, Object?>{'appId': 'app-1', 'deviceId': 'pixel-8'},
        }),
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );

      final TestExecutionSession session = await sessionFuture;
      expect(discovery.flutterDeviceListCount, 0);
      expect(discovery.recordingDeviceListCount, 0);
      expect(starter.startedArguments, <String>[
        'run',
        '--machine',
        '--flavor',
        'staging',
        '--target',
        'lib/main_staging.dart',
      ]);
      expect(
        session.runtimeTarget.vmServiceUri.toString(),
        'ws://127.0.0.1:1234/token=/ws',
      );
      expect(session.runtimeTarget.deviceId, 'pixel-8');
      expect(session.targetDevice, isNull);

      await session.close();
      expect(process.stdinWrites, <String>['q\n']);
    },
  );
}

class FakeDeviceDiscovery implements TestDeviceDiscovery {
  int flutterDeviceListCount = 0;
  int recordingDeviceListCount = 0;

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    flutterDeviceListCount++;
    return const <FlutterDevice>[];
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    recordingDeviceListCount++;
    return const <RecordingDeviceIdentity>[];
  }
}

class FakeTargetAppProcessStarter implements TargetAppProcessStarter {
  FakeTargetAppProcessStarter(this.process);

  final FakeTargetAppProcess process;
  List<String> startedArguments = const <String>[];

  @override
  Future<TargetAppProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startedArguments = arguments;
    return process;
  }
}

class FakeTargetAppProcess implements TargetAppProcess {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  final List<String> stdinWrites = <String>[];

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void emitStdout(String line) {
    _stdoutController.add(utf8.encode('$line\n'));
  }

  @override
  void writeStdin(String text) {
    stdinWrites.add(text);
    if (text == 'q\n' && !_exitCodeCompleter.isCompleted) {
      _stdoutController.close();
      _stderrController.close();
      _exitCodeCompleter.complete(0);
    }
  }

  @override
  bool kill() {
    return true;
  }
}
