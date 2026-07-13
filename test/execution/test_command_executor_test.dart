import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;
import 'package:test/test.dart';

import '../support/test_command_fakes.dart';

/// Verifies single Entry Scenario execution through `DefaultTestCommandExecutor`.
void main() {
  test('default executor launches app, runs scenario, and cleans up', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final FakeScenarioRunner runner = FakeScenarioRunner(
        passedScenarioRunReport(),
      );
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        deviceDiscovery: FakeDeviceDiscovery(),
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
      expect(runner.runtimeTarget.deviceId, 'pixel-8');
      expect(runner.scenario.name, 'launched');
      expect(process.stdinWrites, <String>['q\n']);
    });
  });

  test(
    'default executor runs one Scenario inside one Test Execution Session',
    () async {
      final FakeTestExecutionSession session = FakeTestExecutionSession(
        runtimeTarget: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/token=/ws'),
          deviceId: 'pixel-8',
        ),
      );
      final FakeTestExecutionSessionFactory sessionFactory =
          FakeTestExecutionSessionFactory(session);
      final FakeScenarioRunner runner = FakeScenarioRunner(
        passedScenarioRunReport(),
      );
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        sessionFactory: sessionFactory,
        runnerFactory: FakeScenarioRunnerFactory(runner),
      );
      final Scenario scenario = Scenario(
        name: 'session_backed',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
        ],
      );

      final ScenarioRunReport report = await executor.run(
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

      expect(report.status, ScenarioRunStatus.passed);
      expect(sessionFactory.startCount, 1);
      expect(sessionFactory.flavor, 'staging');
      expect(sessionFactory.target, 'lib/main_staging.dart');
      expect(runner.runtimeTarget.deviceId, 'pixel-8');
      expect(session.runWithInterruptCount, 1);
      expect(session.closeCount, 1);
    },
  );

  test(
    'default executor reports close recording failure after successful run',
    () async {
      final FakeTestExecutionSession session = FakeTestExecutionSession(
        runtimeTarget: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/token=/ws'),
          deviceId: 'pixel-8',
        ),
        closeException: const TestExecutionRecordingException(
          'recording dispose failed',
        ),
      );
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        sessionFactory: FakeTestExecutionSessionFactory(session),
        runnerFactory: FakeScenarioRunnerFactory(
          FakeScenarioRunner(passedScenarioRunReport()),
        ),
      );

      await expectLater(
        executor.run(
          TestCommandOptions(
            scenario: scenarioFixture('close_recording_failure'),
            device: null,
            flavor: null,
            target: null,
            stopPoint: null,
            printDiagnostics: const <PrintDiagnostic>{},
            jsonOutput: false,
          ),
        ),
        throwsA(
          isA<TestCommandException>().having(
            (TestCommandException error) => error.message,
            'message',
            'recording dispose failed',
          ),
        ),
      );
    },
  );

  test(
    'default executor preserves primary failure when close recording fails',
    () async {
      final FakeTestExecutionSession session = FakeTestExecutionSession(
        runtimeTarget: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/token=/ws'),
          deviceId: 'pixel-8',
        ),
        closeException: const TestExecutionRecordingException(
          'recording dispose failed',
        ),
      );
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        sessionFactory: FakeTestExecutionSessionFactory(session),
        runnerFactory: const ThrowingScenarioRunnerFactory(
          RuntimeAdapterSelectionException('runtime selection failed'),
        ),
      );

      await expectLater(
        executor.run(
          TestCommandOptions(
            scenario: scenarioFixture('primary_failure'),
            device: null,
            flavor: null,
            target: null,
            stopPoint: null,
            printDiagnostics: const <PrintDiagnostic>{},
            jsonOutput: false,
          ),
        ),
        throwsA(
          isA<TestCommandException>().having(
            (TestCommandException error) => error.message,
            'message',
            'runtime selection failed',
          ),
        ),
      );
      expect(session.closeCount, 1);
    },
  );

  test(
    'default executor reports invalid hidden runtime switch values',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: const ThrowingScenarioRunnerFactory(
            RuntimeAdapterSelectionException(
              'Invalid FLUTTER_PILOT_RUNTIME value "other_runtime".',
            ),
          ),
        );
        final Scenario scenario = Scenario(
          name: 'invalid_runtime_switch',
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

        await expectLater(
          reportFuture,
          throwsA(
            isA<TestCommandException>().having(
              (TestCommandException error) => error.message,
              'message',
              contains('FLUTTER_PILOT_RUNTIME'),
            ),
          ),
        );
        expect(process.stdinWrites, <String>['q\n']);
      });
    },
  );

  test(
    'default executor forwards Step progress events to the runner',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReport(),
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(runner),
        );
        final Scenario scenario = Scenario(
          name: 'forwarded_progress',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );
        final List<StepProgressEvent> progressEvents = <StepProgressEvent>[];

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
          onProgress: progressEvents.add,
        );
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'appId': 'app-1',
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        process.exit(0);
        await reportFuture;

        expect(runner.onProgress, isNotNull);
        expect(progressEvents, hasLength(2));
        expect(progressEvents.first, isA<StepStartedEvent>());
        expect(progressEvents.last, isA<StepFinishedEvent>());
      });
    },
  );

  test('default executor emits launch progress before Step progress', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final FakeScenarioRunner runner = FakeScenarioRunner(
        passedScenarioRunReport(),
      );
      final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
        deviceDiscovery: FakeDeviceDiscovery(),
        launcher: TargetAppLauncher(starter: starter),
        runnerFactory: FakeScenarioRunnerFactory(runner),
      );
      final Scenario scenario = Scenario(
        name: 'launch_then_steps',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
        ],
      );
      final List<String> progressOrder = <String>[];

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
        onLaunchProgress: (TargetAppLaunchProgressEvent event) {
          progressOrder.add(event.runtimeType.toString());
        },
        onProgress: (StepProgressEvent event) {
          progressOrder.add(event.runtimeType.toString());
        },
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      process.exit(0);
      await reportFuture;

      expect(progressOrder, <String>[
        'TargetAppLaunchStartedEvent',
        'TargetAppLaunchSucceededEvent',
        'StepStartedEvent',
        'StepFinishedEvent',
      ]);
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
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReport(),
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(
            flutterDevices: <FlutterDevice>[
              FlutterDevice(
                id: 'flutter-udid',
                name: 'Test iPhone',
                targetPlatform: 'ios',
                isSupported: true,
                emulator: false,
                sdk: 'iOS 15.8.8',
              ),
            ],
            recordingDevices: <RecordingDeviceIdentity>[
              RecordingDeviceIdentity(
                id: 'avfoundation-id',
                name: 'Test iPhone',
              ),
            ],
          ),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(runner),
          recordingControllerFactory: _fakeRecordingControllerFactory,
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
              'appId': 'app-1',
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
          'flutter-udid',
        ]);
        expect(runner.targetDevice?.id, 'flutter-udid');
        expect(
          (runner.recordingController as ScreenRecorderRecordingController)
              .deviceSelector,
          'avfoundation-id',
        );
      });
    },
  );

  test(
    'default executor reports explicit Target Device launch choices',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReport(),
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(
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
          ),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(runner),
          recordingControllerFactory: _fakeRecordingControllerFactory,
        );
        final Scenario scenario = Scenario(
          name: 'explicit_device',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );
        TargetAppLaunchChoices? launchChoices;

        final Future<ScenarioRunReport> reportFuture = executor.run(
          TestCommandOptions(
            scenario: scenario,
            device: 'Pixel',
            flavor: null,
            target: null,
            stopPoint: null,
            printDiagnostics: const <PrintDiagnostic>{},
            jsonOutput: false,
          ),
          onLaunchProgress: (TargetAppLaunchProgressEvent event) {
            if (event is TargetAppLaunchStartedEvent) {
              launchChoices = event.choices;
            }
          },
        );
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'appId': 'app-1',
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        process.exit(0);
        await reportFuture;

        expect(launchChoices?.targetDevice?.id, 'pixel-8');
        expect(
          launchChoices?.selectionReason,
          isA<ExplicitTargetDeviceSelectionReason>().having(
            (ExplicitTargetDeviceSelectionReason reason) => reason.selector,
            'selector',
            'Pixel',
          ),
        );
      });
    },
  );

  test(
    'default executor reports recording auto-selected launch choices',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReport(),
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(
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
              RecordingDeviceIdentity(id: 'pixel-8', name: 'Pixel 8'),
            ],
          ),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(runner),
          recordingControllerFactory: _fakeRecordingControllerFactory,
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
        TargetAppLaunchChoices? launchChoices;

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
          onLaunchProgress: (TargetAppLaunchProgressEvent event) {
            if (event is TargetAppLaunchStartedEvent) {
              launchChoices = event.choices;
            }
          },
        );
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'appId': 'app-1',
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        process.exit(0);
        await reportFuture;

        expect(launchChoices?.targetDevice?.id, 'pixel-8');
        expect(
          launchChoices?.selectionReason,
          isA<AutoSelectedForRecordingTargetDeviceSelectionReason>(),
        );
      });
    },
  );

  test(
    'default executor reports flavor and entrypoint launch choices',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReport(),
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(runner),
        );
        final Scenario scenario = Scenario(
          name: 'flavored',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );
        TargetAppLaunchChoices? launchChoices;

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
          onLaunchProgress: (TargetAppLaunchProgressEvent event) {
            if (event is TargetAppLaunchStartedEvent) {
              launchChoices = event.choices;
            }
          },
        );
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'appId': 'app-1',
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        process.exit(0);
        await reportFuture;

        expect(launchChoices?.flavor, 'staging');
        expect(launchChoices?.target, 'lib/main_staging.dart');
      });
    },
  );

  test(
    'default executor emits launch failure progress with stderr tail',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(
            FakeScenarioRunner(passedScenarioRunReport()),
          ),
        );
        final Scenario scenario = Scenario(
          name: 'launch_failure',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );
        final List<TargetAppLaunchProgressEvent> launchEvents =
            <TargetAppLaunchProgressEvent>[];

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
          onLaunchProgress: launchEvents.add,
        );
        for (int index = 1; index <= 45; index++) {
          process.emitStderr('stderr line $index');
        }
        process.exit(1);

        await expectLater(reportFuture, throwsA(isA<TestCommandException>()));
        final TargetAppLaunchFailedEvent failedEvent = launchEvents
            .whereType<TargetAppLaunchFailedEvent>()
            .single;
        expect(
          failedEvent.message,
          contains('Flutter exited before Runtime Target URI was available.'),
        );
        expect(failedEvent.stderrLines, hasLength(40));
        expect(failedEvent.stderrLines, isNot(contains('stderr line 5')));
        expect(failedEvent.stderrLines, contains('stderr line 6'));
        expect(failedEvent.stderrLines, contains('stderr line 45'));
      });
    },
  );

  test(
    'default executor emits non-interactive launch heartbeat until success',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final StreamController<void> ticks = StreamController<void>();
        DateTime now = DateTime.utc(2026, 6, 30, 12);
        final DefaultTestCommandExecutor executor = DefaultTestCommandExecutor(
          deviceDiscovery: FakeDeviceDiscovery(),
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: FakeScenarioRunnerFactory(
            FakeScenarioRunner(passedScenarioRunReport()),
          ),
          launchHeartbeatTicks: ticks.stream,
          launchClock: () => now,
        );
        final Scenario scenario = Scenario(
          name: 'launch_heartbeat',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );
        final List<TargetAppLaunchProgressEvent> launchEvents =
            <TargetAppLaunchProgressEvent>[];

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
          onLaunchProgress: launchEvents.add,
          launchHeartbeatEnabled: true,
        );
        while (starter.startedArguments.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        now = DateTime.utc(2026, 6, 30, 12, 0, 10);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'appId': 'app-1',
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        process.exit(0);
        await reportFuture;
        now = DateTime.utc(2026, 6, 30, 12, 0, 20);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        await ticks.close();

        expect(
          launchEvents.whereType<TargetAppLaunchHeartbeatEvent>(),
          hasLength(1),
        );
        expect(
          launchEvents.whereType<TargetAppLaunchSucceededEvent>(),
          hasLength(1),
        );
      });
    },
  );

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
        deviceDiscovery: FakeDeviceDiscovery(),
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

RecordingController _fakeRecordingControllerFactory({
  required String deviceSelector,
  required Directory outputDirectory,
}) {
  return ScreenRecorderRecordingController(
    recorder: screen_recorder.ScreenRecorder.fake(
      devices: <screen_recorder.RecordingDevice>[
        screen_recorder.RecordingDevice(
          id: deviceSelector,
          name: deviceSelector,
          platform: screen_recorder.RecordingDevicePlatform.android,
        ),
      ],
    ),
    deviceSelector: deviceSelector,
    outputDirectory: outputDirectory,
  );
}
