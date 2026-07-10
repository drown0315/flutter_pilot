import 'dart:convert';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

import '../support/run_diff_fixtures.dart';

/// Verify Screenshot artifact Run Diff behavior.
void main() {
  test('reports changed screenshots without creating Regressions', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeBinaryArtifact(
        runs.beforeRun,
        'captures/0001_submit_screenshot.png',
        <int>[1, 2, 3],
      );
      writeBinaryArtifact(
        runs.afterRun,
        'captures/0001_submit_screenshot.png',
        <int>[1, 2, 4],
      );
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'capture',
            status: 'passed',
            artifacts: <Map<String, Object?>>[
              artifactReport(
                type: 'screenshot',
                path: 'captures/0001_submit_screenshot.png',
              ),
            ],
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'capture',
            status: 'passed',
            artifacts: <Map<String, Object?>>[
              artifactReport(
                type: 'screenshot',
                path: 'captures/0001_submit_screenshot.png',
              ),
            ],
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;
      final List<Object?> screenshotChanges =
          json['screenshotChanges'] as List<Object?>;
      final Map<String, Object?> change =
          screenshotChanges.single as Map<String, Object?>;

      expect(output, contains('Screenshot Changes:'));
      expect(output, contains('Step 1 "submit": screenshot changed'));
      expect(json['outcome'], 'changed');
      expect(json['regressions'], isEmpty);
      expect(screenshotChanges, hasLength(1));
      expect(change['kind'], 'changed');
      expect(change['stepKey'], 'label:submit');
      expect(change['beforePath'], 'captures/0001_submit_screenshot.png');
      expect(change['afterPath'], 'captures/0001_submit_screenshot.png');
      expect(change['beforeHash'], isA<String>());
      expect(change['afterHash'], isA<String>());
      expect(change['beforeHash'], isNot(change['afterHash']));
    });
  });

  test('reports added and missing screenshots as neutral changes', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeBinaryArtifact(
        runs.beforeRun,
        'captures/0001_submit_screenshot.png',
        <int>[1, 1, 1],
      );
      writeBinaryArtifact(
        runs.afterRun,
        'captures/0002_banner_screenshot.png',
        <int>[2, 2, 2],
      );
      writeBinaryArtifact(
        runs.afterRun,
        'captures/0003_confirmation_screenshot.png',
        <int>[3, 3, 3],
      );
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'capture',
            status: 'passed',
            artifacts: <Map<String, Object?>>[
              artifactReport(
                type: 'screenshot',
                path: 'captures/0001_submit_screenshot.png',
              ),
            ],
          ),
          stepReport(
            index: 2,
            label: 'banner',
            action: 'capture',
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
            action: 'capture',
            status: 'passed',
          ),
          stepReport(
            index: 2,
            label: 'banner',
            action: 'capture',
            status: 'passed',
            artifacts: <Map<String, Object?>>[
              artifactReport(
                type: 'screenshot',
                path: 'captures/0002_banner_screenshot.png',
              ),
            ],
          ),
          stepReport(
            index: 3,
            label: 'confirmation',
            action: 'capture',
            status: 'passed',
            artifacts: <Map<String, Object?>>[
              artifactReport(
                type: 'screenshot',
                path: 'captures/0003_confirmation_screenshot.png',
              ),
            ],
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;
      final List<Object?> screenshotChanges =
          json['screenshotChanges'] as List<Object?>;

      expect(output, contains('Step 1 "submit": screenshot missing'));
      expect(output, contains('Step 2 "banner": screenshot added'));
      expect(
        output,
        contains('Step 3 "confirmation": screenshot added in after run'),
      );
      expect(json['outcome'], 'changed');
      expect(json['regressions'], isEmpty);
      expect(
        screenshotChanges.map(
          (Object? change) => (change as Map<String, Object?>)['kind'],
        ),
        <String>['missing', 'added', 'added'],
      );
    });
  });

  test('warns for missing referenced screenshot artifacts', () async {
    await FileTestkit.runZoned(() async {
      final RunDiffRunPair runs = createMemoryRunPair();
      writeRunReport(
        runs.beforeRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'capture',
            status: 'passed',
            artifacts: <Map<String, Object?>>[
              artifactReport(
                type: 'screenshot',
                path: 'captures/missing_screenshot.png',
              ),
            ],
          ),
        ],
      );
      writeRunReport(
        runs.afterRun,
        steps: <Map<String, Object?>>[
          stepReport(
            index: 1,
            label: 'submit',
            action: 'capture',
            status: 'passed',
          ),
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: runs.beforeRun,
        afterRunDirectory: runs.afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);
      final Map<String, Object?> json =
          jsonDecode(RunDiffJsonRenderer.render(diff)) as Map<String, Object?>;

      expect(output, contains('Warnings:'));
      expect(output, contains('Missing screenshot artifact'));
      expect(output, contains('captures/missing_screenshot.png'));
      expect(json['outcome'], 'changed');
      expect(
        json['warnings'],
        contains(contains('Missing screenshot artifact')),
      );
    });
  });
}
