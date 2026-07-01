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
      expect(executor.onProgress, isNull);
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
    'default executor forwards Step progress events to the runner',
    () async {
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
        deviceDiscovery: const FakeDeviceDiscovery(),
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
          deviceDiscovery: const FakeDeviceDiscovery(),
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
          deviceDiscovery: const FakeDeviceDiscovery(),
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
          deviceDiscovery: const FakeDeviceDiscovery(),
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
  void Function(StepProgressEvent event)? onProgress;

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    this.scenario = scenario;
    this.onProgress = onProgress;
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
  }) {
    this.scenario = scenario;
    this.onProgress = onProgress;
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
    stdinWrites.add(text);
  }

  @override
  bool kill() {
    return true;
  }
}
