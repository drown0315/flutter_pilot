import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_command_fakes.dart';

/// Verifies Project Run execution through `DefaultProjectRunExecutor`.
void main() {
  test(
    'default Project Run executor reuses one launch with hot restart',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner firstRunner = FakeScenarioRunner(
          passedScenarioRunReportFor('login'),
        );
        final FakeScenarioRunner secondRunner = FakeScenarioRunner(
          passedScenarioRunReportFor('checkout'),
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            firstRunner,
            secondRunner,
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/login.yaml',
            relativePath: 'login.yaml',
            scenario: scenarioFixture('login'),
          ),
          ProjectScenarioFile(
            path: 'pilot/checkout.yaml',
            relativePath: 'checkout.yaml',
            scenario: scenarioFixture('checkout'),
          ),
        ];

        final Future<ProjectRunResult> reportFuture = executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: null,
            flavor: null,
            target: null,
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
        while (process.stdinWrites.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(secondRunner.onProgress, isNull);
        process.emitStdout(
          jsonEncode(<String, Object?>{'id': 0, 'result': true}),
        );

        final ProjectRunResult report = await reportFuture;

        expect(report.passed, isTrue);
        expect(starter.startCount, 1);
        expect(process.stdinWrites, <String>[
          '[{"id":0,"method":"app.restart","params":{"appId":"app-1","fullRestart":true}}]\n',
          'q\n',
        ]);
        expect(firstRunner.scenario.name, 'login');
        expect(secondRunner.scenario.name, 'checkout');
        expect(
          firstRunner.runArtifactWriter?.runDirectory.path,
          p.join(
            Directory.current.path,
            '.runs',
            '2026-07-01_09-30_project-run',
            '2026-07-01_09-30_login',
          ),
        );
        expect(
          secondRunner.runArtifactWriter?.runDirectory.path,
          p.join(
            Directory.current.path,
            '.runs',
            '2026-07-01_09-30_project-run',
            '2026-07-01_09-30_checkout',
          ),
        );
      });
    },
  );

  test(
    'default Project Run executor reuses one Test Execution Session',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTestExecutionSession session = FakeTestExecutionSession(
          runtimeTarget: RuntimeTarget(
            vmServiceUri: Uri.parse('ws://127.0.0.1:1234/token=/ws'),
            deviceId: 'pixel-8',
          ),
        );
        final FakeTestExecutionSessionFactory sessionFactory =
            FakeTestExecutionSessionFactory(session);
        final FakeScenarioRunner firstRunner = FakeScenarioRunner(
          passedScenarioRunReportFor('login'),
        );
        final FakeScenarioRunner secondRunner = FakeScenarioRunner(
          passedScenarioRunReportFor('checkout'),
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          sessionFactory: sessionFactory,
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            firstRunner,
            secondRunner,
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/login.yaml',
            relativePath: 'login.yaml',
            scenario: scenarioFixture('login'),
          ),
          ProjectScenarioFile(
            path: 'pilot/checkout.yaml',
            relativePath: 'checkout.yaml',
            scenario: scenarioFixture('checkout'),
          ),
        ];

        final ProjectRunResult result = await executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: null,
            flavor: 'staging',
            target: 'lib/main_staging.dart',
            jsonOutput: false,
          ),
        );

        expect(result.status, ProjectRunStatus.passed);
        expect(sessionFactory.startCount, 1);
        expect(sessionFactory.flavor, 'staging');
        expect(sessionFactory.target, 'lib/main_staging.dart');
        expect(session.hotRestartCount, 1);
        expect(session.runWithInterruptCount, 2);
        expect(session.closeCount, 1);
        expect(firstRunner.runtimeTarget.deviceId, 'pixel-8');
        expect(secondRunner.runtimeTarget.deviceId, 'pixel-8');
      });
    },
  );

  test(
    'default Project Run executor resolves explicit Target Device before launch',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReportFor('login'),
        );
        final FakeDeviceDiscovery deviceDiscovery = FakeDeviceDiscovery(
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
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          deviceDiscovery: deviceDiscovery,
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            runner,
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/login.yaml',
            relativePath: 'login.yaml',
            scenario: scenarioFixture('login'),
          ),
        ];

        final Future<ProjectRunResult> reportFuture = executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: 'Pixel',
            flavor: 'staging',
            target: 'lib/main_staging.dart',
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
        while (process.stdinWrites.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        process.emitStdout(
          jsonEncode(<String, Object?>{'id': 0, 'result': true}),
        );

        final ProjectRunResult report = await reportFuture;

        expect(report.passed, isTrue);
        expect(deviceDiscovery.flutterDeviceListCount, 1);
        expect(starter.startedArguments, <String>[
          'run',
          '--machine',
          '--device-id',
          'pixel-8',
          '--flavor',
          'staging',
          '--target',
          'lib/main_staging.dart',
        ]);
        expect(runner.targetDevice?.id, 'pixel-8');
      });
    },
  );

  test(
    'default Project Run executor resolves recordable Target Device before launch',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReportFor('recorded'),
        );
        final FakeDeviceDiscovery deviceDiscovery = FakeDeviceDiscovery(
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
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          deviceDiscovery: deviceDiscovery,
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            runner,
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );
        final List<TargetAppLaunchProgressEvent> launchEvents =
            <TargetAppLaunchProgressEvent>[];
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/recorded.yaml',
            relativePath: 'recorded.yaml',
            scenario: Scenario(
              name: 'recorded',
              recording: const ScenarioRecording(enabled: true),
              steps: const <ScenarioStep>[
                ScenarioStep(
                  index: 1,
                  action: CaptureAction(
                    screenshot: false,
                    snapshot: false,
                    widgetTree: false,
                    logs: false,
                  ),
                ),
              ],
            ),
          ),
        ];

        final Future<ProjectRunResult> reportFuture = executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: null,
            flavor: null,
            target: null,
            jsonOutput: false,
          ),
          onLaunchProgress: launchEvents.add,
        );
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );

        final ProjectRunResult report = await reportFuture;

        expect(report.passed, isTrue);
        expect(deviceDiscovery.flutterDeviceListCount, 1);
        expect(deviceDiscovery.recordingDeviceListCount, 1);
        expect(starter.startedArguments, <String>[
          'run',
          '--machine',
          '--device-id',
          'pixel-8',
        ]);
        expect(runner.targetDevice?.id, 'pixel-8');
        expect(runner.recordingController, isNotNull);
        final TargetAppLaunchStartedEvent startedEvent = launchEvents
            .whereType<TargetAppLaunchStartedEvent>()
            .single;
        expect(
          startedEvent.choices.selectionReason,
          isA<AutoSelectedForRecordingTargetDeviceSelectionReason>(),
        );
      });
    },
  );

  test(
    'default Project Run executor rejects ambiguous recording-required selection',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeDeviceDiscovery deviceDiscovery = FakeDeviceDiscovery(
          flutterDevices: <FlutterDevice>[
            FlutterDevice(
              id: 'pixel-8',
              name: 'Pixel 8',
              targetPlatform: 'android-arm64',
              isSupported: true,
              emulator: true,
              sdk: 'Android 35',
            ),
            FlutterDevice(
              id: 'iphone-15',
              name: 'iPhone 15',
              targetPlatform: 'ios',
              isSupported: true,
              emulator: false,
              sdk: 'iOS 18',
            ),
          ],
          recordingDevices: <RecordingDeviceIdentity>[
            const RecordingDeviceIdentity(id: 'pixel-8'),
            const RecordingDeviceIdentity(id: 'iphone-15'),
          ],
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          deviceDiscovery: deviceDiscovery,
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            FakeScenarioRunner(passedScenarioRunReportFor('recorded')),
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/recorded.yaml',
            relativePath: 'recorded.yaml',
            scenario: Scenario(
              name: 'recorded',
              recording: const ScenarioRecording(enabled: true),
              steps: const <ScenarioStep>[
                ScenarioStep(
                  index: 1,
                  action: CaptureAction(
                    screenshot: false,
                    snapshot: false,
                    widgetTree: false,
                    logs: false,
                  ),
                ),
              ],
            ),
          ),
        ];

        final ProjectRunResult report = await executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: null,
            flavor: null,
            target: null,
            jsonOutput: false,
          ),
        );

        expect(report.status, ProjectRunStatus.environmentFailed);
        final File projectRunReport = File(report.projectRunReportPath);
        final Map<String, Object?> reportJson =
            jsonDecode(projectRunReport.readAsStringSync())
                as Map<String, Object?>;
        expect(reportJson['environmentFailure'], <String, Object?>{
          'phase': 'targetDeviceResolution',
          'message':
              'Multiple recordable Target Devices are available. Pass --device with one of: pixel-8 (Pixel 8), iphone-15 (iPhone 15).',
        });
        expect(deviceDiscovery.flutterDeviceListCount, 1);
        expect(deviceDiscovery.recordingDeviceListCount, 1);
        expect(starter.startedArguments, isEmpty);
      });
    },
  );

  test(
    'default Project Run executor reports device discovery failure',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeDeviceDiscovery deviceDiscovery = FakeDeviceDiscovery(
          flutterDeviceListException: const DeviceDiscoveryException(
            'flutter devices failed',
          ),
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          deviceDiscovery: deviceDiscovery,
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            FakeScenarioRunner(passedScenarioRunReportFor('login')),
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );

        final ProjectRunResult report = await executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: <ProjectScenarioFile>[
              ProjectScenarioFile(
                path: 'pilot/login.yaml',
                relativePath: 'login.yaml',
                scenario: scenarioFixture('login'),
              ),
            ],
            device: 'pixel',
            flavor: null,
            target: null,
            jsonOutput: false,
          ),
        );

        expect(report.status, ProjectRunStatus.environmentFailed);
        final File projectRunReport = File(report.projectRunReportPath);
        final Map<String, Object?> reportJson =
            jsonDecode(projectRunReport.readAsStringSync())
                as Map<String, Object?>;
        expect(reportJson['environmentFailure'], <String, Object?>{
          'phase': 'targetDeviceResolution',
          'message': 'flutter devices failed',
        });
        expect(starter.startedArguments, isEmpty);
      });
    },
  );

  test('default Project Run executor emits launch progress once', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final FakeScenarioRunner runner = FakeScenarioRunner(
        passedScenarioRunReportFor('login'),
      );
      final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
        launcher: TargetAppLauncher(starter: starter),
        runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[runner]),
        outputDirectory: Directory.current,
        clock: () => DateTime.utc(2026, 7, 1, 9, 30),
      );
      final List<TargetAppLaunchProgressEvent> launchEvents =
          <TargetAppLaunchProgressEvent>[];
      final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
        ProjectScenarioFile(
          path: 'pilot/login.yaml',
          relativePath: 'login.yaml',
          scenario: scenarioFixture('login'),
        ),
      ];

      final Future<ProjectRunResult> reportFuture = executor.run(
        ProjectRunOptions(
          discoveryRootPath: 'pilot',
          scenarios: scenarios,
          device: null,
          flavor: null,
          target: null,
          jsonOutput: false,
        ),
        onLaunchProgress: launchEvents.add,
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );

      final ProjectRunResult report = await reportFuture;

      expect(report.passed, isTrue);
      expect(
        launchEvents.whereType<TargetAppLaunchStartedEvent>(),
        hasLength(1),
      );
      expect(
        launchEvents.whereType<TargetAppLaunchSucceededEvent>(),
        hasLength(1),
      );
    });
  });

  test('default Project Run executor cleans up when interrupted', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final HangingScenarioRunner runner = HangingScenarioRunner();
      final StreamController<void> interruptController =
          StreamController<void>();
      final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
        launcher: TargetAppLauncher(starter: starter),
        runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[runner]),
        interruptSignals: interruptController.stream,
        outputDirectory: Directory.current,
        clock: () => DateTime.utc(2026, 7, 1, 9, 30),
      );

      final Future<ProjectRunResult> reportFuture = executor.run(
        ProjectRunOptions(
          discoveryRootPath: 'pilot',
          scenarios: <ProjectScenarioFile>[
            ProjectScenarioFile(
              path: 'pilot/login.yaml',
              relativePath: 'login.yaml',
              scenario: scenarioFixture('login'),
            ),
          ],
          device: null,
          flavor: null,
          target: null,
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
      interruptController.add(null);

      await expectLater(
        reportFuture,
        throwsA(
          isA<TestCommandException>()
              .having(
                (TestCommandException error) => error.message,
                'message',
                contains('interrupted'),
              )
              .having(
                (TestCommandException error) => error.exitCode,
                'exitCode',
                130,
              ),
        ),
      );
      expect(process.stdinWrites, <String>['q\n']);
      await interruptController.close();
    });
  });

  test(
    'default Project Run executor emits launch heartbeat until success',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          passedScenarioRunReportFor('login'),
        );
        final StreamController<void> ticks = StreamController<void>();
        DateTime now = DateTime.utc(2026, 7, 1, 9, 30);
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            runner,
          ]),
          outputDirectory: Directory.current,
          clock: () => now,
          launchHeartbeatTicks: ticks.stream,
        );
        final List<TargetAppLaunchProgressEvent> launchEvents =
            <TargetAppLaunchProgressEvent>[];
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/login.yaml',
            relativePath: 'login.yaml',
            scenario: scenarioFixture('login'),
          ),
        ];

        final Future<ProjectRunResult> reportFuture = executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: null,
            flavor: null,
            target: null,
            jsonOutput: false,
          ),
          onLaunchProgress: launchEvents.add,
          launchHeartbeatEnabled: true,
        );
        while (starter.startedArguments.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        now = DateTime.utc(2026, 7, 1, 9, 30, 10);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        process.emitStdout(
          jsonEncode(<String, Object?>{
            'event': 'app.debugPort',
            'params': <String, Object?>{
              'wsUri': 'ws://127.0.0.1:1234/token=/ws',
            },
          }),
        );
        await reportFuture;
        now = DateTime.utc(2026, 7, 1, 9, 30, 20);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        await ticks.close();

        expect(
          launchEvents.whereType<TargetAppLaunchHeartbeatEvent>(),
          hasLength(1),
        );
      });
    },
  );

  test(
    'default Project Run executor continues after a failed Scenario',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner firstRunner = FailingScenarioRunner(
          failingScenarioRunReportFor('login'),
        );
        final FakeScenarioRunner secondRunner = FakeScenarioRunner(
          passedScenarioRunReportFor('checkout'),
        );
        final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
          launcher: TargetAppLauncher(starter: starter),
          runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
            firstRunner,
            secondRunner,
          ]),
          outputDirectory: Directory.current,
          clock: () => DateTime.utc(2026, 7, 1, 9, 30),
        );
        final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
          ProjectScenarioFile(
            path: 'pilot/login.yaml',
            relativePath: 'login.yaml',
            scenario: scenarioFixture('login'),
          ),
          ProjectScenarioFile(
            path: 'pilot/checkout.yaml',
            relativePath: 'checkout.yaml',
            scenario: scenarioFixture('checkout'),
          ),
        ];

        final Future<ProjectRunResult> reportFuture = executor.run(
          ProjectRunOptions(
            discoveryRootPath: 'pilot',
            scenarios: scenarios,
            device: null,
            flavor: null,
            target: null,
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
        while (process.stdinWrites.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        process.emitStdout(
          jsonEncode(<String, Object?>{'id': 0, 'result': true}),
        );

        final ProjectRunResult report = await reportFuture;

        expect(report.passed, isFalse);
        expect(starter.startCount, 1);
        expect(process.stdinWrites, <String>[
          '[{"id":0,"method":"app.restart","params":{"appId":"app-1","fullRestart":true}}]\n',
          'q\n',
        ]);
        expect(firstRunner.scenario.name, 'login');
        expect(secondRunner.scenario.name, 'checkout');
      });
    },
  );

  test('default Project Run executor stops on hot restart failure', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess()
        ..stdinException = StateError('restart failed')
        ..stdinExceptionOnce = true;
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final FakeScenarioRunner firstRunner = FailingScenarioRunner(
        failingScenarioRunReportFor('login'),
      );
      final FakeScenarioRunner secondRunner = FakeScenarioRunner(
        passedScenarioRunReportFor('checkout'),
      );
      final DefaultProjectRunExecutor executor = DefaultProjectRunExecutor(
        launcher: TargetAppLauncher(starter: starter),
        runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
          firstRunner,
          secondRunner,
        ]),
        outputDirectory: Directory.current,
        clock: () => DateTime.utc(2026, 7, 1, 9, 30),
      );
      final List<ProjectScenarioFile> scenarios = <ProjectScenarioFile>[
        ProjectScenarioFile(
          path: 'pilot/login.yaml',
          relativePath: 'login.yaml',
          scenario: scenarioFixture('login'),
        ),
        ProjectScenarioFile(
          path: 'pilot/checkout.yaml',
          relativePath: 'checkout.yaml',
          scenario: scenarioFixture('checkout'),
        ),
      ];

      final Future<ProjectRunResult> reportFuture = executor.run(
        ProjectRunOptions(
          discoveryRootPath: 'pilot',
          scenarios: scenarios,
          device: null,
          flavor: null,
          target: null,
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

      final ProjectRunResult report = await reportFuture;

      expect(report.passed, isFalse);
      expect(starter.startCount, 1);
      expect(process.stdinWrites, <String>['q\n']);
      expect(firstRunner.scenario.name, 'login');
      expect(secondRunner.onProgress, isNull);
    });
  });
}
