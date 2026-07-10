import 'dart:convert';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

import '../support/run_diff_fixtures.dart';

/// Verify stable machine-readable Run Diff JSON output.
void main() {
  test('prints machine-readable Run Diff JSON', () async {
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
          stepReport(
            index: 2,
            label: 'banner',
            action: 'waitFor',
            status: 'failed',
            failureReason: 'Finder matched no widgets.',
            durationMs: 15,
          ),
          stepReport(index: 3, action: 'capture', status: 'passed'),
          stepReport(
            index: 4,
            label: 'refresh',
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
            action: 'tap',
            status: 'failed',
            failureReason: 'Button stayed disabled.',
            durationMs: 10,
          ),
          stepReport(
            index: 2,
            label: 'banner',
            action: 'waitFor',
            status: 'passed',
            durationMs: 8,
          ),
          stepReport(
            index: 4,
            label: 'refresh',
            action: 'waitFor',
            status: 'passed',
            durationMs: 7,
          ),
          stepReport(
            index: 5,
            label: 'confirmation',
            action: 'waitFor',
            status: 'passed',
            durationMs: 6,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;
      final List<Object?> regressions = json['regressions'] as List<Object?>;
      final List<Object?> resolvedSteps =
          json['resolvedSteps'] as List<Object?>;
      final List<Object?> missingSteps = json['missingSteps'] as List<Object?>;
      final List<Object?> addedSteps = json['addedSteps'] as List<Object?>;
      final List<Object?> actionChanges =
          json['actionChanges'] as List<Object?>;

      expect(json['beforeRunDirectory'], runs.beforeRun.path);
      expect(json['afterRunDirectory'], runs.afterRun.path);
      expect(json['outcome'], 'regressed');
      expect(
        json['warnings'],
        contains('Scenario names differ: login_error vs checkout_error.'),
      );
      expect(regressions, hasLength(1));
      expect(
        regressions.single,
        containsPair('failureReason', 'Button stayed disabled.'),
      );
      expect(
        regressions.single,
        containsPair('before', <String, Object?>{
          'index': 1,
          'label': 'submit',
          'action': 'tap',
          'status': 'passed',
        }),
      );
      expect(
        regressions.single,
        containsPair('after', <String, Object?>{
          'index': 1,
          'label': 'submit',
          'action': 'tap',
          'status': 'failed',
          'failureReason': 'Button stayed disabled.',
        }),
      );
      expect(resolvedSteps, hasLength(1));
      expect(missingSteps, hasLength(1));
      expect(addedSteps, hasLength(1));
      expect(actionChanges, hasLength(1));
    });
  });

  test('outcome is improved for resolved Steps only', () async {
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
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;

      expect(json['outcome'], 'improved');
      expect(json['resolvedSteps'], hasLength(1));
      expect(json['regressions'], isEmpty);
    });
  });

  test('outcome is changed for neutral-only Step changes', () async {
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
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;

      expect(json['outcome'], 'changed');
      expect(json['actionChanges'], hasLength(1));
      expect(json['regressions'], isEmpty);
      expect(json['resolvedSteps'], isEmpty);
    });
  });

  test('outcome is unchanged when there are no findings or warnings', () async {
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
            status: 'passed',
            durationMs: 10,
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;

      expect(json['outcome'], 'unchanged');
      expect(json['warnings'], isEmpty);
      expect(json['regressions'], isEmpty);
      expect(json['resolvedSteps'], isEmpty);
      expect(json['missingSteps'], isEmpty);
      expect(json['addedSteps'], isEmpty);
      expect(json['actionChanges'], isEmpty);
    });
  });
}
