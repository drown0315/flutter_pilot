import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

import '../support/run_diff_fixtures.dart';

/// Verify Step alignment and Step finding behavior through Run Diff APIs.
void main() {
  test('reports passed-to-failed labeled Steps as Regressions', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'passed',
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'failed',
            failureReason: 'Finder matched no widgets.',
            durationMs: 10,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);

      expect(output, contains('Regressions:'));
      expect(output, contains('submit'));
      expect(output, contains('passed -> failed'));
      expect(output, contains('Finder matched no widgets.'));
    });
  });

  test('reports failed-to-passed labeled Steps as resolved Steps', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'failed',
            failureReason: 'Finder matched no widgets.',
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'passed',
            durationMs: 10,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);

      expect(output, contains('Resolved Steps:'));
      expect(output, contains('submit'));
      expect(output, contains('failed -> passed'));
      expect(output, contains('Finder matched no widgets.'));
    });
  });

  test('aligns labeled Steps by Step Label before Step index', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'failed',
            failureReason: 'Finder matched no widgets.',
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 2,
            label: 'submit',
            action: 'tap',
            status: 'passed',
            durationMs: 10,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);

      expect(output, contains('Resolved Steps:'));
      expect(output, contains('submit'));
      expect(output, isNot(contains('Added Steps:')));
      expect(output, isNot(contains('missing labeled Step')));
    });
  });

  test(
    'aligns unlabeled before Steps by index when after Step has a label',
    () async {
      await FileTestkit.runZoned(() async {
        final RunDiffRunPair runs = createMemoryRunPair();
        writeRunReport(
          runs.beforeRun,
          steps: <Map<String, Object?>>[
            stepReport(
              index: 1,
              action: 'tap',
              status: 'failed',
              failureReason: 'Finder matched no widgets.',
            ),
          ],
        );
        writeRunReport(
          runs.afterRun,
          steps: <Map<String, Object?>>[
            stepReport(
              index: 1,
              label: 'submit',
              action: 'tap',
              status: 'passed',
              durationMs: 10,
            ),
          ],
        );

        final RunDiff diff = RunDiffEngine.diffDirectories(
          beforeRunDirectory: runs.beforeRun,
          afterRunDirectory: runs.afterRun,
        );
        final String output = RunDiffTextRenderer.render(diff);

        expect(output, contains('Resolved Steps:'));
        expect(output, contains('Step 1'));
        expect(output, isNot(contains('Missing Steps:')));
        expect(output, isNot(contains('Added Steps:')));
      });
    },
  );

  test(
    'distinguishes missing labeled, missing unlabeled, and added Steps',
    () async {
      await FileTestkit.runZoned(() async {
        final RunDiffRunPair runs = createMemoryRunPair();
        writeRunReport(
          runs.beforeRun,
          steps: <Map<String, Object?>>[
            stepReport(
              index: 1,
              label: 'submit',
              action: 'tap',
              status: 'passed',
            ),
            stepReport(index: 2, action: 'capture', status: 'passed'),
          ],
        );
        writeRunReport(
          runs.afterRun,
          steps: <Map<String, Object?>>[
            stepReport(
              index: 3,
              label: 'confirmation',
              action: 'waitFor',
              status: 'passed',
              durationMs: 10,
            ),
          ],
        );

        final RunDiff diff = RunDiffEngine.diffDirectories(
          beforeRunDirectory: runs.beforeRun,
          afterRunDirectory: runs.afterRun,
        );
        final String output = RunDiffTextRenderer.render(diff);

        expect(output, contains('Regressions:'));
        expect(output, contains('missing labeled Step'));
        expect(output, contains('submit'));
        expect(output, contains('Missing Steps:'));
        expect(output, contains('Step 2'));
        expect(output, contains('Added Steps:'));
        expect(output, contains('confirmation'));
      });
    },
  );

  test('reports action changes and scenario-name warnings', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        scenarioName: 'login_error',
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'passed',
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        scenarioName: 'checkout_error',
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'waitFor',
            status: 'passed',
            durationMs: 10,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);

      expect(output, contains('Warnings:'));
      expect(output, contains('login_error vs checkout_error'));
      expect(output, contains('Action Changes:'));
      expect(output, contains('tap -> waitFor'));
    });
  });

  test('keeps Step failure reasons out of runtime failure diffs', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'failed',
            failureReason: 'Finder matched no widgets.',
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'tap',
            status: 'passed',
            durationMs: 10,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );

      expect(diff.resolvedSteps, hasLength(1));
      expect(diff.resolvedRuntimeFailures, isEmpty);
      expect(diff.newRuntimeFailures, isEmpty);
    });
  });
}
