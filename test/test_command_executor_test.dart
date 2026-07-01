import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies `test` command orchestration through injectable dependencies.
///
/// These tests avoid launching a real Flutter app while still exercising the
/// command path that parses a Scenario, builds launch options, runs through an
/// executor, prints report paths, and performs cleanup.
void main() {
  test('test command delegates validated options to the executor', () async {
    await FileTestkit.runZoned(() async {
      final File scenarioFile = File('scenario.yaml')
        ..writeAsStringSync('''
scenario:
  name: delegated
steps:
  - label: submit
    tap:
      byText: Continue
''');
      final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
        report: _passedReport(),
      );

      final int exitCode = await FlutterPilotCli(testCommandExecutor: executor)
          .run(<String>[
            'test',
            scenarioFile.path,
            '--device',
            'Pixel',
            '--flavor',
            'staging',
            '--target',
            'lib/main_staging.dart',
            '--until',
            'submit',
            '--print',
            'snapshot',
            '--json',
          ]);

      expect(exitCode, 0);
      expect(executor.options.scenario.name, 'delegated');
      expect(executor.options.device, 'Pixel');
      expect(executor.options.flavor, 'staging');
      expect(executor.options.target, 'lib/main_staging.dart');
      expect(executor.options.stopPoint, isA<StepLabelStopPoint>());
      expect(executor.options.printDiagnostics, <PrintDiagnostic>{
        PrintDiagnostic.snapshot,
      });
      expect(executor.options.jsonOutput, isTrue);
    });
  });

  test('default executor launches app, runs scenario, and cleans up', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        deviceDiscovery: const FakeDeviceDiscovery(),
        launcher: TargetAppLauncher(starter: starter),
        runnerFactory: FakeScenarioRunnerFactory(runner),
      );
      final Scenario scenario = Scenario(
        name: 'launched',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
        ],
      );

      final Future<ScenarioRunReport> reportFuture = executor.run(
        TestCommandOptions(
          scenario: scenario,
          device: null,
          flavor: 'staging',
          target: 'lib/main_staging.dart',
          stopPoint: null,
          printDiagnostics: const <PrintDiagnostic>{},
          jsonOutput: false,
        ),
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      process.exit(0);
      final ScenarioRunReport report = await reportFuture;

      expect(report.status, ScenarioRunStatus.passed);
      expect(starter.startedArguments, <String>[
        'run',
        '--machine',
        '--flavor',
        'staging',
        '--target',
        'lib/main_staging.dart',
      ]);
      expect(
        runner.runtimeTarget.vmServiceUri.toString(),
        'ws://127.0.0.1:1234/token=/ws',
      );
      expect(runner.scenario.name, 'launched');
      expect(process.stdinWrites, <String>['q\n']);
    });
  });

  test(
    'default executor resolves recordable Target Device before launch',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: const FakeDeviceDiscovery(
            flutterDevices: <FlutterDevice>[
              FlutterDevice(
                id: 'pixel-8',
                name: 'Pixel 8',
                targetPlatform: 'android-arm64',
                isSupported: true,
                emulator: true,
                sdk: 'Android 35',
              ),
            ],
            recordingDevices: <RecordingDeviceIdentity>[
              RecordingDeviceIdentity(id: 'pixel-8'),
            ],
          ),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(runner),
        );
        final Scenario scenario = Scenario(
          name: 'recorded',
          recording: const ScenarioRecording(enabled: true),
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );

        final Future<ScenarioRunReport> reportFuture = executor.run(
          TestCommandOptions(
            scenario: scenario,
            device: null,
            flavor: null,
            target: null,
            stopPoint: null,
            printDiagnostics: const <PrintDiagnostic>{},
            jsonOutput: false,
          ),
        );
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        process.exit(0);
        await reportFuture;

        expect(starter.startedArguments, <String>[
          'run',
          '--machine',
          '--device-id',
          'pixel-8',
        ]);
        expect(runner.targetDevice?.id, 'pixel-8');
        expect(runner.recordingController, isNotNull);
      });
    },
  );

  test('renders resolved Target Device output', () {
    expect(
      TestCommandOutput.targetDeviceLine(
        const TargetDevice(
          id: 'pixel-8',
          name: 'Pixel 8',
          targetPlatform: 'android-arm64',
          emulator: true,
          sdk: 'Android 35',
        ),
      ),
      'Target Device: pixel-8 (Pixel 8, android-arm64, Android 35)',
    );
  });

  test('default executor cleans up launched app when interrupted', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final HangingScenarioRunner runner = HangingScenarioRunner();
      final StreamController<void> interruptController =
          StreamController<void>();
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        deviceDiscovery: const FakeDeviceDiscovery(),
        launcher: TargetAppLauncher(starter: starter),
        runnerFactory: FakeScenarioRunnerFactory(runner),
        interruptSignals: interruptController.stream,
      );
      final Scenario scenario = Scenario(
        name: 'interrupt',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
        ],
      );

      final Future<ScenarioRunReport> reportFuture = executor.run(
        TestCommandOptions(
          scenario: scenario,
          device: null,
          flavor: null,
          target: null,
          stopPoint: null,
          printDiagnostics: const <PrintDiagnostic>{},
          jsonOutput: false,
        ),
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      interruptController.add(null);

      await expectLater(
        reportFuture,
        throwsA(
          isA<TestCommandException>().having(
            (TestCommandException error) => error.message,
            'message',
            contains('interrupted'),
          ),
        ),
      );
      expect(process.stdinWrites, <String>['q\n']);
      await interruptController.close();
    });
  });
}

class FakeTestCommandExecutor implements TestCommandExecutor {
  FakeTestCommandExecutor({required this.report});

  final ScenarioRunReport report;
  late TestCommandOptions options;

  @override
  Future<ScenarioRunReport> run(TestCommandOptions options) async {
    this.options = options;
    return report;
  }
}

ScenarioRunReport _passedReport() {
  return ScenarioRunReport(
    scenarioName: 'delegated',
    scenarioDescription: null,
    totalSteps: 0,
    status: ScenarioRunStatus.passed,
    startedAt: DateTime.utc(2026, 6, 30),
    durationMs: 1,
    steps: const <StepRunReport>[],
    runDirectoryPath: '.runs/delegated',
    artifacts: const <ArtifactReport>[],
  );
}

class FakeDeviceDiscovery implements TestDeviceDiscovery {
  const FakeDeviceDiscovery({
    this.flutterDevices = const <FlutterDevice>[],
    this.recordingDevices = const <RecordingDeviceIdentity>[],
  });

  final List<FlutterDevice> flutterDevices;
  final List<RecordingDeviceIdentity> recordingDevices;

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    return flutterDevices;
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    return recordingDevices;
  }
}

class FakeScenarioRunnerFactory implements TestScenarioRunnerFactory {
  const FakeScenarioRunnerFactory(this.runner);

  final FakeScenarioRunner runner;

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    runner.runtimeTarget = runtimeTarget;
    runner.targetDevice = targetDevice;
    runner.recordingController = recordingController;
    return runner;
  }
}

class FakeScenarioRunner implements TestScenarioRunner {
  FakeScenarioRunner(this.report);

  final ScenarioRunReport report;
  late RuntimeTarget runtimeTarget;
  TargetDevice? targetDevice;
  RecordingController? recordingController;
  late Scenario scenario;

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
  }) async {
    this.scenario = scenario;
    return report;
  }
}

class HangingScenarioRunner extends FakeScenarioRunner {
  HangingScenarioRunner() : super(_passedReport());

  final Completer<ScenarioRunReport> _completer =
      Completer<ScenarioRunReport>();

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
  }) {
    this.scenario = scenario;
    return _completer.future;
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

  void exit(int exitCode) {
    _stdoutController.close();
    _stderrController.close();
    _exitCodeCompleter.complete(exitCode);
  }

  @override
  void writeStdin(String text) {
    stdinWrites.add(text);
  }

  @override
  bool kill() {
    return true;
  }
}
