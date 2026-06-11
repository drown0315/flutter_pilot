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

      final File reportFile = File('${outputDirectory.path}/run_report.json');
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

      final File reportFile = File('${outputDirectory.path}/run_report.json');
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

      final File reportFile = File('${outputDirectory.path}/run_report.json');
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

      final File reportFile = File('${outputDirectory.path}/run_report.json');
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

      final File reportFile = File('${outputDirectory.path}/run_report.json');
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

      final File reportFile = File('${outputDirectory.path}/run_report.json');
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason":"Initialize failed."'),
      );
    });
  });
}
