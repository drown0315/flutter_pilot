import 'dart:convert';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

import 'support/run_diff_fixtures.dart';

/// Verify visible text and runtime failure Run Diff behavior.
void main() {
  test('reports visible text and runtime failures from summaries', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        diagnosticSummary: diagnosticSummary(
          visibleText: <String>['Email', 'Retry'],
          runtimeFailures: <String>['RenderFlex overflowed by 12 pixels'],
        ),
      );
      writeRunReport(
        runs.afterRun,
        diagnosticSummary: diagnosticSummary(
          visibleText: <String>['Email', 'Continue'],
          runtimeFailures: <String>['setState() called after dispose()'],
        ),
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;

      expect(output, contains('Visible Text Added:'));
      expect(output, contains('Continue'));
      expect(output, contains('Visible Text Removed:'));
      expect(output, contains('Retry'));
      expect(output, contains('Resolved Runtime Failures:'));
      expect(output, contains('RenderFlex overflowed by 12 pixels'));
      expect(output, contains('Regressions:'));
      expect(output, contains('setState() called after dispose()'));
      expect(json['outcome'], 'regressed');
      expect(json['visibleTextAdded'], <String>['Continue']);
      expect(json['visibleTextRemoved'], <String>['Retry']);
      expect(json['resolvedRuntimeFailures'], <String>[
        'RenderFlex overflowed by 12 pixels',
      ]);
      expect(json['newRuntimeFailures'], <String>[
        'setState() called after dispose()',
      ]);
    });
  });

  test(
    'falls back to Snapshot and Logs artifacts when summaries are absent',
    () async {
      await FileTestkit.runZoned(() async {
        final RunDiffRunPair runs = createMemoryRunPair();
        writeJsonArtifact(
          runs.beforeRun,
          'captures/before_snapshot.json',
          <String, Object?>{
            'nodes': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'Retry'},
              <String, Object?>{'type': 'text', 'text': 'Email'},
            ],
          },
        );
        writeJsonArtifact(
          runs.beforeRun,
          'captures/before_logs.json',
          <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{
                'level': 'error',
                'message': 'RenderFlex overflowed by 12 pixels',
              },
            ],
          },
        );
        writeJsonArtifact(
          runs.afterRun,
          'captures/after_snapshot.json',
          <String, Object?>{
            'nodes': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'Continue'},
              <String, Object?>{'type': 'text', 'text': 'Email'},
            ],
          },
        );
        writeJsonArtifact(
          runs.afterRun,
          'captures/after_logs.json',
          <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{
                'level': 'error',
                'message': 'setState() called after dispose()',
              },
            ],
          },
        );
        writeRunReport(
          runs.beforeRun,
          artifacts: <Map<String, Object?>>[
            artifactReport(
              type: 'snapshot',
              path: 'captures/before_snapshot.json',
            ),
            artifactReport(type: 'logs', path: 'captures/before_logs.json'),
          ],
        );
        writeRunReport(
          runs.afterRun,
          artifacts: <Map<String, Object?>>[
            artifactReport(
              type: 'snapshot',
              path: 'captures/after_snapshot.json',
            ),
            artifactReport(type: 'logs', path: 'captures/after_logs.json'),
          ],
        );

        final RunDiff diff = RunDiffEngine.diffDirectories(
          beforeRunDirectory: runs.beforeRun,
          afterRunDirectory: runs.afterRun,
        );
        final Map<String, Object?> json =
            jsonDecode(RunDiffJsonRenderer.render(diff))
                as Map<String, Object?>;

        expect(json['visibleTextAdded'], <String>['Continue']);
        expect(json['visibleTextRemoved'], <String>['Retry']);
        expect(json['resolvedRuntimeFailures'], <String>[
          'RenderFlex overflowed by 12 pixels',
        ]);
        expect(json['newRuntimeFailures'], <String>[
          'setState() called after dispose()',
        ]);
      });
    },
  );

  test('warns for missing referenced diagnostic artifacts', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        artifacts: <Map<String, Object?>>[
          artifactReport(
            type: 'snapshot',
            path: 'captures/missing_snapshot.json',
          ),
          artifactReport(type: 'logs', path: 'captures/missing_logs.json'),
        ],
      );
      writeRunReport(runs.afterRun);

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;

      expect(output, contains('Warnings:'));
      expect(output, contains('Missing snapshot artifact'));
      expect(output, contains('captures/missing_snapshot.json'));
      expect(output, contains('Missing logs artifact'));
      expect(output, contains('captures/missing_logs.json'));
      expect(json['outcome'], 'changed');
      expect(json['warnings'], contains(contains('Missing snapshot artifact')));
      expect(json['warnings'], contains(contains('Missing logs artifact')));
    });
  });
}
