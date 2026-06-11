import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises Scenario execution through the public runner API.
///
/// These tests use the fake Runtime Adapter so they can verify step execution
/// and report output without requiring a live Flutter app.
void main() {
  test('executes successful Scenario steps and writes run report', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('runner_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[
            FinderMatch(id: 'tap-match', debugLabel: 'TextButton("Log in")'),
          ],
          'email_input': const <FinderMatch>[
            FinderMatch(id: 'type-match', debugLabel: 'EditableText'),
          ],
          'scrollable': const <FinderMatch>[
            FinderMatch(id: 'scroll-match', debugLabel: 'ListView'),
          ],
          'loading_done': const <FinderMatch>[
            FinderMatch(id: 'wait-match', debugLabel: 'Text("Done")'),
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'login_error',
        description: 'Reproduces the login validation error',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'submit_login',
            action: TapAction(finder: Finder(byKey: 'login_button')),
          ),
          ScenarioStep(
            index: 2,
            action: TypeAction(
              finder: Finder(byKey: 'email_input'),
              text: 'bad@example.com',
            ),
          ),
          ScenarioStep(
            index: 3,
            action: ScrollAction(
              finder: Finder(byKey: 'scrollable'),
              deltaX: 0,
              deltaY: -500,
            ),
          ),
          ScenarioStep(
            index: 4,
            action: WaitForAction(
              finder: Finder(byKey: 'loading_done'),
              timeoutMs: 3000,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.passed);
      expect(report.scenarioName, 'login_error');
      expect(
        report.steps.map((StepRunReport step) => step.status),
        <StepStatus>[
          StepStatus.passed,
          StepStatus.passed,
          StepStatus.passed,
          StepStatus.passed,
        ],
      );

      final File reportFile = _runReportFile(report);
      expect(reportFile.existsSync(), isTrue);
      expect(reportFile.readAsStringSync(), contains('"name":"login_error"'));
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.performTap,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.replaceText,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.performScroll,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test('creates a stable run directory with scenario metadata', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('artifact_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'capture_checkpoint',
        description: 'Collect diagnostics at a checkpoint',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'checkpoint',
            action: CaptureAction(
              screenshot: false,
              snapshot: false,
              widgetTree: false,
              logs: false,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      final Directory runsDirectory = Directory(
        '${outputDirectory.path}/.runs',
      );
      final List<Directory> runDirectories = runsDirectory
          .listSync()
          .whereType<Directory>()
          .toList(growable: false);
      expect(runDirectories, hasLength(1));

      final Directory runDirectory = runDirectories.single;
      expect(
        runDirectory.path,
        matches(
          r'artifact_output/\.runs/\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}_capture_checkpoint$',
        ),
      );
      expect(report.runDirectoryPath, runDirectory.path);

      final File scenarioFile = File('${runDirectory.path}/scenario.json');
      final File stepFile = File(
        '${runDirectory.path}/steps/0001_checkpoint.json',
      );
      final File reportFile = File('${runDirectory.path}/run_report.json');
      expect(scenarioFile.existsSync(), isTrue);
      expect(stepFile.existsSync(), isTrue);
      expect(reportFile.existsSync(), isTrue);
      expect(scenarioFile.readAsStringSync(), contains('"capture_checkpoint"'));
      expect(stepFile.readAsStringSync(), contains('"label":"checkpoint"'));
      expect(reportFile.readAsStringSync(), contains('"path":"scenario.json"'));
      expect(
        reportFile.readAsStringSync(),
        contains('"path":"steps/0001_checkpoint.json"'),
      );
    });
  });

  test(
    'executes default capture operations without artifact storage',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('capture_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
        final Scenario scenario = Scenario(
          name: 'capture_checkpoint',
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

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario);

        expect(report.status, ScenarioRunStatus.passed);
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.captureScreenshot,
            RuntimeOperation.captureSnapshot,
            RuntimeOperation.collectLogs,
            RuntimeOperation.dispose,
          ],
        );
      });
    },
  );

  test('waits until a Finder has exactly one match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('wait_for_success_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResultSequences: <String, List<List<FinderMatch>>>{
          'loading_done': <List<FinderMatch>>[
            const <FinderMatch>[],
            const <FinderMatch>[
              FinderMatch(id: 'wait-match', debugLabel: 'Text("Done")'),
            ],
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'wait_for_widget',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: WaitForAction(
              finder: Finder(byKey: 'loading_done'),
              timeoutMs: 100,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.passed);
      expect(report.steps.single.status, StepStatus.passed);
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test('fails waitFor when timeout expires with no matches', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('wait_for_timeout_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'wait_for_timeout',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: WaitForAction(
              finder: Finder(byKey: 'missing_loading_done'),
              timeoutMs: 1,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(
        report.steps.single.failureReason,
        'Finder matched no widgets before timeout.',
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        containsAllInOrder(<RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ]),
      );
    });
  });

  test('fails waitFor when multiple widgets match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('wait_for_multiple_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'loading_done': const <FinderMatch>[
            FinderMatch(id: 'first-match', debugLabel: 'Text("Done")'),
            FinderMatch(id: 'second-match', debugLabel: 'Text("Done")'),
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'wait_for_ambiguous_widget',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: WaitForAction(
              finder: Finder(byKey: 'loading_done'),
              timeoutMs: 100,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(
        report.steps.single.failureReason,
        'Finder matched multiple widgets.',
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test('fails a Finder action when no widgets match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('zero_match_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'missing_button',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byKey: 'missing_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(report.steps.single.failureReason, 'Finder matched no widgets.');
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );

      final File reportFile = _runReportFile(report);
      expect(reportFile.readAsStringSync(), contains('"status":"failed"'));
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason":"Finder matched no widgets."'),
      );
    });
  });

  test('fails a Finder action when multiple widgets match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('multiple_match_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[
            FinderMatch(id: 'first-match', debugLabel: 'TextButton("Log in")'),
            FinderMatch(id: 'second-match', debugLabel: 'Text("Log in")'),
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'ambiguous_button',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byKey: 'login_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(
        report.steps.single.failureReason,
        'Finder matched multiple widgets.',
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test('preserves Step failure report when dispose also fails', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory(
        'dispose_after_failure_output',
      );
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.dispose: const RuntimeOperationException(
            operation: RuntimeOperation.dispose,
            message: 'Dispose failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'missing_button',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byKey: 'missing_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.failureReason, 'Finder matched no widgets.');

      final File reportFile = _runReportFile(report);
      expect(
        reportFile.readAsStringSync(),
        contains('Finder matched no widgets'),
      );
    });
  });

  test('records dispose failure when cleanup is the only failure', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('dispose_failure_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[FinderMatch(id: 'tap-match')],
        },
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.dispose: const RuntimeOperationException(
            operation: RuntimeOperation.dispose,
            message: 'Dispose failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'dispose_failure',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byKey: 'login_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.failureReason, 'Dispose failed.');
      expect(report.steps.single.status, StepStatus.passed);

      final File reportFile = _runReportFile(report);
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason":"Dispose failed."'),
      );
    });
  });

  test('records runtime operation failures as failed Steps', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('runtime_failure_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[FinderMatch(id: 'tap-match')],
        },
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.performTap: const RuntimeOperationException(
            operation: RuntimeOperation.performTap,
            message: 'Tap RPC failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'tap_failure',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byKey: 'login_button')),
          ),
          ScenarioStep(
            index: 2,
            action: CaptureAction(
              screenshot: true,
              snapshot: true,
              widgetTree: false,
              logs: true,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.failureReason, 'Tap RPC failed.');
      expect(report.steps.single.status, StepStatus.failed);
      expect(report.steps.single.failureReason, 'Tap RPC failed.');
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );

      final File reportFile = _runReportFile(report);
      expect(reportFile.readAsStringSync(), contains('Tap RPC failed.'));
    });
  });

  test('records initialize failure as a run-level failure', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('initialize_failure_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.initialize: const RuntimeOperationException(
            operation: RuntimeOperation.initialize,
            message: 'Initialize failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'initialize_failure',
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

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.failureReason, 'Initialize failed.');
      expect(report.steps, isEmpty);

      final File reportFile = _runReportFile(report);
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason":"Initialize failed."'),
      );
    });
  });
}

/// Return the report file written for a completed Scenario run.
File _runReportFile(ScenarioRunReport report) {
  return File('${report.runDirectoryPath}/run_report.json');
}
