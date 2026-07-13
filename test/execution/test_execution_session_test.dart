import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  test('keeps Target and Recording Device selectors separate', () async {
    final FakeDeviceDiscovery discovery = FakeDeviceDiscovery(
      flutterDevices: const <FlutterDevice>[
        FlutterDevice(
          id: 'flutter-udid',
          name: 'Test iPhone',
          targetPlatform: 'ios',
          isSupported: true,
          emulator: false,
          sdk: 'iOS 15.8.8',
        ),
      ],
      recordingDevices: const <RecordingDeviceIdentity>[
        RecordingDeviceIdentity(id: 'avfoundation-id', name: 'Test iPhone'),
      ],
    );
    final FakeTargetAppProcess process = FakeTargetAppProcess();
    final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
      process,
    );
    final TestExecutionSessionFactory factory =
        DefaultTestExecutionSessionFactory(
          deviceDiscovery: discovery,
          launcher: TargetAppLauncher(starter: starter),
          recordingControllerFactory:
              ({
                required String deviceSelector,
                required Directory outputDirectory,
              }) => _EventRecordingController(<String>[]),
        );

    final Future<TestExecutionSession> sessionFuture = factory.start(
      deviceSelector: 'flutter-udid',
      flavor: null,
      target: null,
      recordingRequired: true,
      launchHeartbeatEnabled: false,
    );
    process.emitStdout(
      jsonEncode(<String, Object?>{
        'event': 'app.debugPort',
        'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
      }),
    );

    final TestExecutionSession session = await sessionFuture;

    expect(starter.startedArguments, <String>[
      'run',
      '--machine',
      '--device-id',
      'flutter-udid',
    ]);
    expect(session.targetDevice?.id, 'flutter-udid');
    expect(session.recordingDeviceSelector, 'avfoundation-id');

    await session.close();
  });

  test(
    'prepares recording before launch and disposes after app cleanup',
    () async {
      final List<String> events = <String>[];
      final FakeDeviceDiscovery discovery = FakeDeviceDiscovery(
        flutterDevices: const <FlutterDevice>[
          FlutterDevice(
            id: 'flutter-udid',
            name: 'Test iPhone',
            targetPlatform: 'ios',
            isSupported: true,
            emulator: false,
            sdk: 'iOS 15.8.8',
          ),
        ],
        recordingDevices: const <RecordingDeviceIdentity>[
          RecordingDeviceIdentity(id: 'avfoundation-id', name: 'Test iPhone'),
        ],
      );
      final FakeTargetAppProcess process = FakeTargetAppProcess(events: events);
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
        events: events,
      );
      final TestExecutionSessionFactory factory =
          DefaultTestExecutionSessionFactory(
            deviceDiscovery: discovery,
            launcher: TargetAppLauncher(starter: starter),
            recordingControllerFactory:
                ({
                  required String deviceSelector,
                  required Directory outputDirectory,
                }) {
                  events.add('recording-controller:$deviceSelector');
                  return _EventRecordingController(events);
                },
          );

      final Future<TestExecutionSession> sessionFuture = factory.start(
        deviceSelector: 'flutter-udid',
        flavor: null,
        target: null,
        recordingRequired: true,
        launchHeartbeatEnabled: false,
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>[
        'recording-controller:avfoundation-id',
        'prepare',
        'launch',
      ]);

      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );
      final TestExecutionSession session = await sessionFuture;

      await session.close();

      expect(events, <String>[
        'recording-controller:avfoundation-id',
        'prepare',
        'launch',
        'app-close',
        'dispose',
      ]);
    },
  );
}

class FakeDeviceDiscovery implements TestDeviceDiscovery {
  FakeDeviceDiscovery({
    this.flutterDevices = const <FlutterDevice>[],
    this.recordingDevices = const <RecordingDeviceIdentity>[],
  });

  final List<FlutterDevice> flutterDevices;
  final List<RecordingDeviceIdentity> recordingDevices;
  int flutterDeviceListCount = 0;
  int recordingDeviceListCount = 0;

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    flutterDeviceListCount++;
    return flutterDevices;
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    recordingDeviceListCount++;
    return recordingDevices;
  }
}

class FakeTargetAppProcessStarter implements TargetAppProcessStarter {
  FakeTargetAppProcessStarter(this.process, {this.events});

  final FakeTargetAppProcess process;
  final List<String>? events;
  List<String> startedArguments = const <String>[];

  @override
  Future<TargetAppProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    events?.add('launch');
    startedArguments = arguments;
    return process;
  }
}

class FakeTargetAppProcess implements TargetAppProcess {
  FakeTargetAppProcess({this.events});

  final List<String>? events;
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
      events?.add('app-close');
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

class _EventRecordingController implements RecordingController {
  _EventRecordingController(this.events);

  final List<String> events;

  @override
  Future<void> prepare() async {
    events.add('prepare');
  }

  @override
  Future<void> start(Scenario scenario) async {}

  @override
  Future<RecordingResult> stop() async {
    return const RecordingResult(path: 'recording.mov');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}
