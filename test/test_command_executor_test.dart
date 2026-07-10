import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Verifies `test` command orchestration through injectable dependencies.
///
/// These tests avoid launching a real Flutter app while still exercising the
/// command path that parses a Scenario, builds launch options, runs through an
/// executor, prints report paths, and performs cleanup.
void main() {
  test('test command delegates no-argument Project Run from pilot', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');
      final FakeProjectRunCommandExecutor projectExecutor =
          FakeProjectRunCommandExecutor(report: _passedProjectReport());

      final int exitCode = await FlutterPilotCli(
        projectRunCommandExecutor: projectExecutor,
      ).run(<String>['test']);

      expect(exitCode, 0);
      expect(projectExecutor.options.discoveryRootPath, 'pilot');
      expect(
        projectExecutor.options.scenarios.map(
          (ProjectScenarioFile file) => file.relativePath,
        ),
        <String>['login.yaml'],
      );
    });
  });

  test(
    'test command delegates directory input as a focused Project Run',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('flows').createSync();
        File('flows/checkout.yaml').writeAsStringSync('''
scenario:
  name: checkout
steps:
  - capture: {}
''');
        final FakeProjectRunCommandExecutor projectExecutor =
            FakeProjectRunCommandExecutor(report: _passedProjectReport());

        final int exitCode = await FlutterPilotCli(
          projectRunCommandExecutor: projectExecutor,
        ).run(<String>['test', 'flows']);

        expect(exitCode, 0);
        expect(projectExecutor.options.discoveryRootPath, 'flows');
        expect(
          projectExecutor.options.scenarios.map(
            (ProjectScenarioFile file) => file.relativePath,
          ),
          <String>['checkout.yaml'],
        );
      });
    },
  );

  test('Project Run output renders deterministic all-passed summary', () {
    const ProjectRunCommandReport report = ProjectRunCommandReport(
      passed: true,
      status: ProjectRunStatus.passed,
      projectRunReportPath:
          '.runs/2026-07-01_09-30_project-run/project_run_report.json',
      scenarioReports: <ProjectRunScenarioOutputReport>[
        ProjectRunScenarioOutputReport(
          scenarioPath: 'checkout.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_checkout/run_report.json',
          htmlReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_checkout/timeline.html',
        ),
        ProjectRunScenarioOutputReport(
          scenarioPath: 'login.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_login/run_report.json',
          htmlReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_login/timeline.html',
        ),
      ],
    );

    final String rendered = TestCommandOutput.renderProjectRunSummary(report);

    expect(rendered, '''
Project Run: passed
Project Run report: .runs/2026-07-01_09-30_project-run/project_run_report.json
Scenario: checkout.yaml (passed)
Run report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_checkout/run_report.json
HTML report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_checkout/timeline.html
Scenario: login.yaml (passed)
Run report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_login/run_report.json
HTML report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_login/timeline.html
''');
  });

  test('Project Run output renders partially failed summary', () {
    const ProjectRunCommandReport report = ProjectRunCommandReport(
      passed: false,
      status: ProjectRunStatus.failed,
      projectRunReportPath: '.runs/project-run/project_run_report.json',
      scenarioReports: <ProjectRunScenarioOutputReport>[
        ProjectRunScenarioOutputReport(
          scenarioPath: 'login.yaml',
          status: ProjectScenarioRunStatus.failed,
          runReportPath: '.runs/project-run/login/run_report.json',
          htmlReportPath: '.runs/project-run/login/timeline.html',
        ),
        ProjectRunScenarioOutputReport(
          scenarioPath: 'checkout.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath: '.runs/project-run/checkout/run_report.json',
          htmlReportPath: '.runs/project-run/checkout/timeline.html',
        ),
      ],
    );

    final String rendered = TestCommandOutput.renderProjectRunSummary(report);

    expect(rendered, contains('Project Run: failed'));
    expect(rendered, contains('Scenario: login.yaml (failed)'));
    expect(rendered, contains('Scenario: checkout.yaml (passed)'));
  });

  test('Project Run output renders environment-level failure summary', () {
    const ProjectRunCommandReport report = ProjectRunCommandReport(
      passed: false,
      status: ProjectRunStatus.environmentFailed,
      projectRunReportPath: '.runs/project-run/project_run_report.json',
      scenarioReports: <ProjectRunScenarioOutputReport>[],
    );

    final String rendered = TestCommandOutput.renderProjectRunSummary(report);

    expect(rendered, '''
Project Run: environmentFailed
Project Run report: .runs/project-run/project_run_report.json
''');
  });

  test('test command keeps file input in single Entry Scenario mode', () async {
    await FileTestkit.runZoned(() async {
      final File scenarioFile = File('scenario.yaml')
        ..writeAsStringSync('''
steps:
  - capture: {}
''');
      final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
        report: _passedReport(),
      );
      final FakeProjectRunCommandExecutor projectExecutor =
          FakeProjectRunCommandExecutor(report: _passedProjectReport());

      final int exitCode = await FlutterPilotCli(
        testCommandExecutor: executor,
        projectRunCommandExecutor: projectExecutor,
      ).run(<String>['test', scenarioFile.path]);

      expect(exitCode, 0);
      expect(executor.options.scenario.name, 'scenario');
      expect(projectExecutor.ran, isFalse);
    });
  });

  test('test command rejects multiple positional inputs', () async {
    await FileTestkit.runZoned(() async {
      File('a.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');
      File('b.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        'a.yaml',
        'b.yaml',
      ]);

      expect(exitCode, 64);
    });
  });

  test('test command does not introduce glob-style inputs', () async {
    await FileTestkit.runZoned(() async {
      File('scenario.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        '*.yaml',
      ]);

      expect(exitCode, 64);
    });
  });

  test(
    'test command reports empty Project Run discovery before launch',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('pilot').createSync();
        File('pilot/library.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');
        final FakeProjectRunCommandExecutor projectExecutor =
            FakeProjectRunCommandExecutor(report: _passedProjectReport());

        final int exitCode = await FlutterPilotCli(
          projectRunCommandExecutor: projectExecutor,
        ).run(<String>['test']);

        expect(exitCode, 64);
        expect(projectExecutor.ran, isFalse);
      });
    },
  );

  test('test command rejects --until in Project Run mode', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        '--until',
        '1',
      ]);

      expect(exitCode, 64);
    });
  });

  test('test command rejects --print in Project Run mode', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        '--print',
        'widget-tree',
      ]);

      expect(exitCode, 64);
    });
  });

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
            'widget-tree',
            '--json',
          ]);

      expect(exitCode, 0);
      expect(executor.options.scenario.name, 'delegated');
      expect(executor.options.device, 'Pixel');
      expect(executor.options.flavor, 'staging');
      expect(executor.options.target, 'lib/main_staging.dart');
      expect(executor.options.stopPoint, isA<StepLabelStopPoint>());
      expect(executor.options.printDiagnostics, <PrintDiagnostic>{
        PrintDiagnostic.widgetTree,
      });
      expect(executor.options.jsonOutput, isTrue);
      expect(executor.onProgress, isNull);
    });
  });

  test('test command rejects empty Project Run launch options', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');
      final List<List<String>> optionCases = <List<String>>[
        <String>['--device', ' '],
        <String>['--flavor', ' '],
        <String>['--target', ' '],
      ];

      for (final List<String> optionCase in optionCases) {
        final FakeProjectRunCommandExecutor projectExecutor =
            FakeProjectRunCommandExecutor(report: _passedProjectReport());

        final int exitCode = await FlutterPilotCli(
          projectRunCommandExecutor: projectExecutor,
        ).run(<String>['test', ...optionCase]);

        expect(exitCode, 64);
        expect(projectExecutor.ran, isFalse);
      }
    });
  });

  test(
    'test command enables Step progress for human-readable output',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: progress
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: _passedReport(),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path]);

        expect(exitCode, 0);
        expect(executor.onProgress, isNotNull);
      });
    },
  );

  test('test command enables Step progress for Project Run output', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: project_step_progress
steps:
  - capture: {}
''');
      final FakeProjectRunCommandExecutor projectExecutor =
          FakeProjectRunCommandExecutor(report: _passedProjectReport());

      final int exitCode = await FlutterPilotCli(
        projectRunCommandExecutor: projectExecutor,
      ).run(<String>['test']);

      expect(exitCode, 0);
      expect(projectExecutor.onProgress, isNotNull);
    });
  });

  test(
    'test command enables Target App Launch Progress for human-readable output',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: launch_progress
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: _passedReport(),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path]);

        expect(exitCode, 0);
        expect(executor.onLaunchProgress, isNotNull);
      });
    },
  );

  test(
    'test command enables Target App Launch Progress for Project Run output',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('pilot').createSync();
        File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: project_launch_progress
steps:
  - capture: {}
''');
        final FakeProjectRunCommandExecutor projectExecutor =
            FakeProjectRunCommandExecutor(report: _passedProjectReport());

        final int exitCode = await FlutterPilotCli(
          projectRunCommandExecutor: projectExecutor,
        ).run(<String>['test']);

        expect(exitCode, 0);
        expect(projectExecutor.onLaunchProgress, isNotNull);
        expect(projectExecutor.launchHeartbeatEnabled, isTrue);
      });
    },
  );

  test(
    'test command keeps Project Run --json scoped to progress suppression',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('pilot').createSync();
        File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: project_json
steps:
  - capture: {}
''');
        final FakeProjectRunCommandExecutor projectExecutor =
            FakeProjectRunCommandExecutor(report: _passedProjectReport());

        final int exitCode = await FlutterPilotCli(
          projectRunCommandExecutor: projectExecutor,
        ).run(<String>['test', '--json']);

        expect(exitCode, 0);
        expect(projectExecutor.options.jsonOutput, isTrue);
        expect(projectExecutor.onProgress, isNull);
        expect(projectExecutor.onLaunchProgress, isNull);
      });
    },
  );

  test(
    'test command suppresses Target App Launch Progress for JSON output',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: launch_progress_json
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: _passedReport(),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path, '--json']);

        expect(exitCode, 0);
        expect(executor.onLaunchProgress, isNull);
      });
    },
  );

  test(
    'test command suppresses JSON launch failure progress but preserves failure',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: launch_progress_failure_json
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: _passedReport(),
          exception: const TestCommandException(
            message: 'Flutter exited before Runtime Target URI was available.',
            exitCode: 1,
          ),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path, '--json']);

        expect(exitCode, 1);
        expect(executor.onLaunchProgress, isNull);
      });
    },
  );

  test('test command does not duplicate rendered launch failure', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('launch_failure.log');
      final IOSink sink = output.openWrite();
      final File scenarioFile = File('scenario.yaml')
        ..writeAsStringSync('''
scenario:
  name: launch_failure
steps:
  - tap:
      byText: Continue
''');
      final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
        report: _passedReport(),
        exception: const TestCommandException(
          message: 'Flutter exited before Runtime Target URI was available.',
          exitCode: 1,
          alreadyRendered: true,
        ),
      );

      final int exitCode = await runZoned(
        () => FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path]),
        zoneValues: <Object?, Object?>{#stderr: sink},
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(exitCode, 1);
      expect(rendered, isNot(contains('Runtime Target URI')));
    });
  });

  test('plain launch progress renders before Step progress', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('progress.log');
      final IOSink sink = output.openWrite();
      final TargetAppLaunchProgressRenderer launchRenderer =
          TargetAppLaunchProgressRenderer(
            sink: sink,
            clock: () => DateTime.utc(2026, 6, 30, 12, 0, 38),
          );
      final StepProgressRenderer stepRenderer = StepProgressRenderer(
        sink: sink,
      );

      launchRenderer.render(
        TargetAppLaunchStartedEvent(startedAt: DateTime.utc(2026, 6, 30, 12)),
      );
      launchRenderer.render(
        TargetAppLaunchSucceededEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
          finishedAt: DateTime.utc(2026, 6, 30, 12, 0, 38),
        ),
      );
      stepRenderer.render(
        const StepStartedEvent(
          scenarioName: 'launch_progress',
          totalSteps: 1,
          step: ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
          action: 'tap',
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('> Target App Launch'));
      expect(rendered, contains('Launching Target App Package... elapsed 38s'));
      expect(rendered, contains('Target App launched in 38s'));
      expect(rendered, contains('Scenario: launch_progress (1 steps)'));
      expect(
        rendered.indexOf('Target App launched in 38s'),
        lessThan(rendered.indexOf('Scenario: launch_progress (1 steps)')),
      );
    });
  });

  test(
    'plain launch progress shows explicit Target Device selection',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(
            startedAt: DateTime.utc(2026, 6, 30, 12),
            choices: const TargetAppLaunchChoices(
              targetDevice: TargetDevice(
                id: 'pixel-8',
                name: 'Pixel 8',
                targetPlatform: 'android-arm64',
                emulator: true,
                sdk: 'Android 35',
              ),
              selectionReason: TargetDeviceSelectionReason.explicit(
                selector: 'Pixel',
              ),
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(
          rendered,
          contains(
            'Target Device: pixel-8 (Pixel 8, android-arm64, Android 35)',
          ),
        );
        expect(rendered, contains('Selection: --device Pixel'));
      });
    },
  );

  test(
    'test command chooses interactive progress only for terminals',
    () async {
      await FileTestkit.runZoned(() async {
        final IOSink sink = File('progress.log').openWrite();
        try {
          final StepProgressRenderer? jsonRenderer =
              TestCommandOutput.stepProgressRenderer(
                sink: sink,
                jsonOutput: true,
                stderrHasTerminal: true,
              );
          final StepProgressRenderer? terminalRenderer =
              TestCommandOutput.stepProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: true,
              );
          final StepProgressRenderer? redirectedRenderer =
              TestCommandOutput.stepProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: false,
              );
          final TargetAppLaunchProgressRenderer? terminalLaunchRenderer =
              TestCommandOutput.targetAppLaunchProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: true,
              );
          final TargetAppLaunchProgressRenderer? redirectedLaunchRenderer =
              TestCommandOutput.targetAppLaunchProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: false,
              );

          expect(jsonRenderer, isNull);
          expect(terminalRenderer?.interactive, isTrue);
          expect(redirectedRenderer?.interactive, isFalse);
          expect(terminalLaunchRenderer?.interactive, isTrue);
          expect(redirectedLaunchRenderer?.interactive, isFalse);
        } finally {
          await sink.close();
        }
      });
    },
  );

  test('default executor launches app, runs scenario, and cleans up', () async {
    await FileTestkit.runZoned(() async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
        final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
      final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
        final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
          'pixel-8',
        ]);
        expect(runner.targetDevice?.id, 'pixel-8');
        expect(runner.recordingController, isNotNull);
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
        final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
    'plain launch progress shows recording auto-selected Target Device',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(
            startedAt: DateTime.utc(2026, 6, 30, 12),
            choices: const TargetAppLaunchChoices(
              targetDevice: TargetDevice(
                id: 'pixel-8',
                name: 'Pixel 8',
                targetPlatform: 'android-arm64',
                emulator: true,
                sdk: 'Android 35',
              ),
              selectionReason:
                  TargetDeviceSelectionReason.autoSelectedForRecording(),
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(
          rendered,
          contains(
            'Target Device: pixel-8 (Pixel 8, android-arm64, Android 35)',
          ),
        );
        expect(rendered, contains('Selection: auto-selected for recording'));
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
        final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
    'plain launch progress shows Flutter default without placeholders',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(startedAt: DateTime.utc(2026, 6, 30, 12)),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(rendered, contains('Target Device: Flutter default'));
        expect(rendered, isNot(contains('Selection:')));
        expect(rendered, isNot(contains('Flavor:')));
        expect(rendered, isNot(contains('Entrypoint:')));
      });
    },
  );

  test(
    'plain launch progress shows flavor and entrypoint when provided',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(
            startedAt: DateTime.utc(2026, 6, 30, 12),
            choices: const TargetAppLaunchChoices(
              flavor: 'staging',
              target: 'lib/main_staging.dart',
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(rendered, contains('Flavor: staging'));
        expect(rendered, contains('Entrypoint: lib/main_staging.dart'));
      });
    },
  );

  test('plain launch progress shows bounded failure details', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('progress.log');
      final IOSink sink = output.openWrite();
      final TargetAppLaunchProgressRenderer renderer =
          TargetAppLaunchProgressRenderer(sink: sink);

      renderer.render(
        TargetAppLaunchFailedEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
          failedAt: DateTime.utc(2026, 6, 30, 12, 0, 4),
          message: 'Flutter exited before Runtime Target URI was available.',
          stderrLines: const <String>['stderr line 6', 'stderr line 45'],
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('Target App launch failed after 4s'));
      expect(
        rendered,
        contains('Flutter exited before Runtime Target URI was available.'),
      );
      expect(rendered, contains('Flutter stderr tail:'));
      expect(rendered, contains('stderr line 6'));
      expect(rendered, contains('stderr line 45'));
    });
  });

  test('redraws the interactive launch panel in place', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('launch_refresh.log');
      final IOSink sink = output.openWrite();
      DateTime now = DateTime.utc(2026, 6, 30, 12, 0, 1);
      final TargetAppLaunchProgressRenderer renderer =
          TargetAppLaunchProgressRenderer(
            sink: sink,
            interactive: true,
            clock: () => now,
          );
      final TargetAppLaunchStartedEvent started = TargetAppLaunchStartedEvent(
        startedAt: DateTime.utc(2026, 6, 30, 12),
        choices: const TargetAppLaunchChoices(flavor: 'staging'),
      );

      renderer.render(started);
      now = DateTime.utc(2026, 6, 30, 12, 0, 2);
      renderer.render(started);
      renderer.render(
        TargetAppLaunchSucceededEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
          finishedAt: DateTime.utc(2026, 6, 30, 12, 0, 3),
          choices: started.choices,
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('\u001b['));
      final String plain = TerminalStyle.stripAnsi(rendered);
      expect(plain, contains('> Target App Launch'));
      expect(plain, contains('⏳ Waiting for Runtime Target... elapsed 2s'));
      expect(plain, contains('Flavor: staging'));
      expect(plain, contains('Target App launched in 3s'));
      expect(plain, isNot(contains('%')));
    });
  });

  test('interactive launch heartbeat refreshes elapsed time', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('launch_heartbeat_refresh.log');
      final IOSink sink = output.openWrite();
      DateTime now = DateTime.utc(2026, 6, 30, 12, 0, 1);
      final TargetAppLaunchProgressRenderer renderer =
          TargetAppLaunchProgressRenderer(
            sink: sink,
            interactive: true,
            clock: () => now,
          );
      final TargetAppLaunchStartedEvent started = TargetAppLaunchStartedEvent(
        startedAt: DateTime.utc(2026, 6, 30, 12),
      );

      renderer.render(started);
      now = DateTime.utc(2026, 6, 30, 12, 0, 11);
      renderer.render(
        TargetAppLaunchHeartbeatEvent(
          startedAt: started.startedAt,
          heartbeatAt: now,
          choices: started.choices,
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('\u001b['));
      final String plain = TerminalStyle.stripAnsi(rendered);
      expect(plain, contains('⏳ Waiting for Runtime Target... elapsed 11s'));
    });
  });

  test(
    'non-interactive launch heartbeat prints every ten seconds until stopped',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('launch_heartbeat.log');
        final IOSink sink = output.openWrite();
        DateTime now = DateTime.utc(2026, 6, 30, 12);
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink, clock: () => now);
        final StreamController<void> ticks = StreamController<void>();
        final TargetAppLaunchHeartbeat heartbeat = TargetAppLaunchHeartbeat(
          ticks: ticks.stream,
          onProgress: renderer.render,
          clock: () => now,
        );
        final TargetAppLaunchStartedEvent started = TargetAppLaunchStartedEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
        );

        heartbeat.start(started);
        now = DateTime.utc(2026, 6, 30, 12, 0, 9);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        now = DateTime.utc(2026, 6, 30, 12, 0, 10);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        await heartbeat.stop();
        now = DateTime.utc(2026, 6, 30, 12, 0, 20);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        await ticks.close();
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(
          rendered
              .split('\n')
              .where(
                (String line) =>
                    line.contains('Launching Target App Package... elapsed'),
              )
              .toList(),
          <String>['Launching Target App Package... elapsed 10s'],
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
        final FakeScenarioRunner runner = FakeScenarioRunner(_passedReport());
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
            FakeScenarioRunner(_passedReport()),
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
            FakeScenarioRunner(_passedReport()),
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

  test(
    'default Project Run executor reuses one launch with hot restart',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner firstRunner = FakeScenarioRunner(
          _passedReportFor('login'),
        );
        final FakeScenarioRunner secondRunner = FakeScenarioRunner(
          _passedReportFor('checkout'),
        );
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
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
            scenario: _scenario('login'),
          ),
          ProjectScenarioFile(
            path: 'pilot/checkout.yaml',
            relativePath: 'checkout.yaml',
            scenario: _scenario('checkout'),
          ),
        ];

        final Future<ProjectRunCommandReport> reportFuture = executor.run(
          ProjectRunCommandOptions(
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

        final ProjectRunCommandReport report = await reportFuture;

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
    'default Project Run executor resolves explicit Target Device before launch',
    () async {
      await FileTestkit.runZoned(() async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final FakeScenarioRunner runner = FakeScenarioRunner(
          _passedReportFor('login'),
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
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
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
            scenario: _scenario('login'),
          ),
        ];

        final Future<ProjectRunCommandReport> reportFuture = executor.run(
          ProjectRunCommandOptions(
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

        final ProjectRunCommandReport report = await reportFuture;

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
          _passedReportFor('recorded'),
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
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
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

        final Future<ProjectRunCommandReport> reportFuture = executor.run(
          ProjectRunCommandOptions(
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

        final ProjectRunCommandReport report = await reportFuture;

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
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
              deviceDiscovery: deviceDiscovery,
              launcher: TargetAppLauncher(starter: starter),
              runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
                FakeScenarioRunner(_passedReportFor('recorded')),
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

        final ProjectRunCommandReport report = await executor.run(
          ProjectRunCommandOptions(
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
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
              deviceDiscovery: deviceDiscovery,
              launcher: TargetAppLauncher(starter: starter),
              runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
                FakeScenarioRunner(_passedReportFor('login')),
              ]),
              outputDirectory: Directory.current,
              clock: () => DateTime.utc(2026, 7, 1, 9, 30),
            );

        final ProjectRunCommandReport report = await executor.run(
          ProjectRunCommandOptions(
            discoveryRootPath: 'pilot',
            scenarios: <ProjectScenarioFile>[
              ProjectScenarioFile(
                path: 'pilot/login.yaml',
                relativePath: 'login.yaml',
                scenario: _scenario('login'),
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
        _passedReportFor('login'),
      );
      final DefaultProjectRunCommandExecutor executor =
          DefaultProjectRunCommandExecutor(
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
          path: 'pilot/login.yaml',
          relativePath: 'login.yaml',
          scenario: _scenario('login'),
        ),
      ];

      final Future<ProjectRunCommandReport> reportFuture = executor.run(
        ProjectRunCommandOptions(
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

      final ProjectRunCommandReport report = await reportFuture;

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
      final DefaultProjectRunCommandExecutor executor =
          DefaultProjectRunCommandExecutor(
            launcher: TargetAppLauncher(starter: starter),
            runnerFactory: QueueScenarioRunnerFactory(<FakeScenarioRunner>[
              runner,
            ]),
            interruptSignals: interruptController.stream,
            outputDirectory: Directory.current,
            clock: () => DateTime.utc(2026, 7, 1, 9, 30),
          );

      final Future<ProjectRunCommandReport> reportFuture = executor.run(
        ProjectRunCommandOptions(
          discoveryRootPath: 'pilot',
          scenarios: <ProjectScenarioFile>[
            ProjectScenarioFile(
              path: 'pilot/login.yaml',
              relativePath: 'login.yaml',
              scenario: _scenario('login'),
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
          _passedReportFor('login'),
        );
        final StreamController<void> ticks = StreamController<void>();
        DateTime now = DateTime.utc(2026, 7, 1, 9, 30);
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
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
            scenario: _scenario('login'),
          ),
        ];

        final Future<ProjectRunCommandReport> reportFuture = executor.run(
          ProjectRunCommandOptions(
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
          _failingReportFor('login'),
        );
        final FakeScenarioRunner secondRunner = FakeScenarioRunner(
          _passedReportFor('checkout'),
        );
        final DefaultProjectRunCommandExecutor executor =
            DefaultProjectRunCommandExecutor(
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
            scenario: _scenario('login'),
          ),
          ProjectScenarioFile(
            path: 'pilot/checkout.yaml',
            relativePath: 'checkout.yaml',
            scenario: _scenario('checkout'),
          ),
        ];

        final Future<ProjectRunCommandReport> reportFuture = executor.run(
          ProjectRunCommandOptions(
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

        final ProjectRunCommandReport report = await reportFuture;

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
        _failingReportFor('login'),
      );
      final FakeScenarioRunner secondRunner = FakeScenarioRunner(
        _passedReportFor('checkout'),
      );
      final DefaultProjectRunCommandExecutor executor =
          DefaultProjectRunCommandExecutor(
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
          scenario: _scenario('login'),
        ),
        ProjectScenarioFile(
          path: 'pilot/checkout.yaml',
          relativePath: 'checkout.yaml',
          scenario: _scenario('checkout'),
        ),
      ];

      final Future<ProjectRunCommandReport> reportFuture = executor.run(
        ProjectRunCommandOptions(
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

      final ProjectRunCommandReport report = await reportFuture;

      expect(report.passed, isFalse);
      expect(starter.startCount, 1);
      expect(process.stdinWrites, <String>['q\n']);
      expect(firstRunner.scenario.name, 'login');
      expect(secondRunner.onProgress, isNull);
    });
  });
}

class FakeTestCommandExecutor implements TestCommandExecutor {
  FakeTestCommandExecutor({required this.report, this.exception});

  final ScenarioRunReport report;
  final TestCommandException? exception;
  late TestCommandOptions options;
  void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress;
  bool? launchHeartbeatEnabled;
  void Function(StepProgressEvent event)? onProgress;

  @override
  Future<ScenarioRunReport> run(
    TestCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    this.options = options;
    this.onLaunchProgress = onLaunchProgress;
    this.launchHeartbeatEnabled = launchHeartbeatEnabled;
    this.onProgress = onProgress;
    final TestCommandException? exception = this.exception;
    if (exception != null) {
      throw exception;
    }
    return report;
  }
}

class FakeProjectRunCommandExecutor implements ProjectRunCommandExecutor {
  FakeProjectRunCommandExecutor({required this.report});

  final ProjectRunCommandReport report;
  late ProjectRunCommandOptions options;
  bool ran = false;
  void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress;
  bool? launchHeartbeatEnabled;
  void Function(StepProgressEvent event)? onProgress;

  @override
  Future<ProjectRunCommandReport> run(
    ProjectRunCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    this.options = options;
    ran = true;
    this.onLaunchProgress = onLaunchProgress;
    this.launchHeartbeatEnabled = launchHeartbeatEnabled;
    this.onProgress = onProgress;
    return report;
  }
}

ProjectRunCommandReport _passedProjectReport() {
  return const ProjectRunCommandReport(
    passed: true,
    status: ProjectRunStatus.passed,
    projectRunReportPath: '.runs/project-run/project_run_report.json',
    scenarioReports: <ProjectRunScenarioOutputReport>[],
  );
}

ScenarioRunReport _passedReport({TargetDevice? targetDevice}) {
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
    targetDevice: targetDevice,
  );
}

ScenarioRunReport _passedReportFor(String scenarioName) {
  return ScenarioRunReport(
    scenarioName: scenarioName,
    scenarioDescription: null,
    totalSteps: 1,
    status: ScenarioRunStatus.passed,
    startedAt: DateTime.utc(2026, 7, 1, 9, 30),
    durationMs: 1,
    steps: const <StepRunReport>[
      StepRunReport(
        index: 1,
        label: null,
        action: 'capture',
        status: StepStatus.passed,
        durationMs: 1,
      ),
    ],
    runDirectoryPath: '.runs/child',
    artifacts: const <ArtifactReport>[
      ArtifactReport(type: ArtifactType.runReport, path: 'run_report.json'),
      ArtifactReport(type: ArtifactType.htmlReport, path: 'timeline.html'),
    ],
  );
}

ScenarioRunReport _failingReportFor(String scenarioName) {
  return ScenarioRunReport(
    scenarioName: scenarioName,
    scenarioDescription: null,
    totalSteps: 1,
    status: ScenarioRunStatus.failed,
    startedAt: DateTime.utc(2026, 7, 1, 9, 30),
    durationMs: 1,
    steps: const <StepRunReport>[
      StepRunReport(
        index: 1,
        label: null,
        action: 'capture',
        status: StepStatus.failed,
        durationMs: 1,
        failureReason: 'failed',
      ),
    ],
    runDirectoryPath: '.runs/child',
    artifacts: const <ArtifactReport>[],
  );
}

Scenario _scenario(String name) {
  return Scenario(
    name: name,
    steps: const <ScenarioStep>[
      ScenarioStep(
        index: 1,
        action: CaptureAction(
          screenshot: true,
          snapshot: true,
          widgetTree: false,
          logs: true,
        ),
      ),
    ],
  );
}

class FakeDeviceDiscovery implements TestDeviceDiscovery {
  FakeDeviceDiscovery({
    this.flutterDevices = const <FlutterDevice>[],
    this.recordingDevices = const <RecordingDeviceIdentity>[],
    this.flutterDeviceListException,
    this.recordingDeviceListException,
  });

  final List<FlutterDevice> flutterDevices;
  final List<RecordingDeviceIdentity> recordingDevices;
  final DeviceDiscoveryException? flutterDeviceListException;
  final DeviceDiscoveryException? recordingDeviceListException;
  int flutterDeviceListCount = 0;
  int recordingDeviceListCount = 0;

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    flutterDeviceListCount++;
    final DeviceDiscoveryException? exception = flutterDeviceListException;
    if (exception != null) {
      throw exception;
    }
    return flutterDevices;
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    recordingDeviceListCount++;
    final DeviceDiscoveryException? exception = recordingDeviceListException;
    if (exception != null) {
      throw exception;
    }
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

class ThrowingScenarioRunnerFactory implements TestScenarioRunnerFactory {
  const ThrowingScenarioRunnerFactory(this.exception);

  final Exception exception;

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    throw exception;
  }
}

class QueueScenarioRunnerFactory implements TestScenarioRunnerFactory {
  QueueScenarioRunnerFactory(this.runners);

  final List<FakeScenarioRunner> runners;
  int _index = 0;

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    final FakeScenarioRunner runner = runners[_index++];
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
  void Function(StepProgressEvent event)? onProgress;
  RunArtifactWriter? runArtifactWriter;

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) async {
    this.scenario = scenario;
    this.onProgress = onProgress;
    this.runArtifactWriter = runArtifactWriter;
    onProgress?.call(
      StepStartedEvent(
        scenarioName: scenario.name,
        totalSteps: scenario.steps.length,
        step: scenario.steps.first,
        action: 'tap',
      ),
    );
    onProgress?.call(
      StepFinishedEvent(
        scenarioName: scenario.name,
        totalSteps: scenario.steps.length,
        report: StepRunReport(
          index: scenario.steps.first.index,
          label: scenario.steps.first.label,
          action: 'tap',
          status: StepStatus.passed,
          durationMs: 1,
        ),
      ),
    );
    return report;
  }
}

class FailingScenarioRunner extends FakeScenarioRunner {
  FailingScenarioRunner(super.report);

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) async {
    this.scenario = scenario;
    this.runArtifactWriter = runArtifactWriter;
    return ScenarioRunReport(
      scenarioName: scenario.name,
      scenarioDescription: null,
      totalSteps: scenario.steps.length,
      status: ScenarioRunStatus.failed,
      startedAt: DateTime.utc(2026, 7, 1, 9, 30),
      durationMs: 1,
      steps: const <StepRunReport>[],
      runDirectoryPath: '.runs/child',
      artifacts: const <ArtifactReport>[],
    );
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
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) {
    this.scenario = scenario;
    this.onProgress = onProgress;
    this.runArtifactWriter = runArtifactWriter;
    return _completer.future;
  }
}

class FakeTargetAppProcessStarter implements TargetAppProcessStarter {
  FakeTargetAppProcessStarter(this.process);

  final FakeTargetAppProcess process;
  List<String> startedArguments = const <String>[];
  int startCount = 0;

  @override
  Future<TargetAppProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startCount++;
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
  Object? stdinException;
  bool stdinExceptionOnce = false;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void emitStdout(String line) {
    _stdoutController.add(utf8.encode('$line\n'));
  }

  void emitStderr(String line) {
    _stderrController.add(utf8.encode('$line\n'));
  }

  void exit(int exitCode) {
    _stdoutController.close();
    _stderrController.close();
    _exitCodeCompleter.complete(exitCode);
  }

  @override
  void writeStdin(String text) {
    final Object? exception = stdinException;
    if (exception != null) {
      if (stdinExceptionOnce) {
        stdinException = null;
        stdinExceptionOnce = false;
      }
      throw exception;
    }
    stdinWrites.add(text);
  }

  @override
  bool kill() {
    return true;
  }
}
