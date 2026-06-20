import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies checked-in Run Diff acceptance fixtures.
void main() {
  group('Run Diff acceptance fixtures', () {
    test('cover unchanged, improved, regressed, and changed outcomes', () {
      final Map<String, String> expectedOutcomes = <String, String>{
        'unchanged': 'unchanged',
        'improved': 'improved',
        'regressed': 'regressed',
        'changed': 'changed',
      };

      for (final MapEntry<String, String> entry in expectedOutcomes.entries) {
        final RunDiff diff = _diffFixture(entry.key);

        expect(diff.outcome, entry.value, reason: entry.key);
      }
    });

    test('include malformed and partial-artifact runs', () {
      expect(() => _diffFixture('malformed'), throwsA(isA<RunDiffException>()));

      final RunDiff partialArtifactDiff = _diffFixture('partial_artifact');

      expect(partialArtifactDiff.outcome, 'changed');
      expect(partialArtifactDiff.warnings, isNotEmpty);
      expect(
        partialArtifactDiff.warnings,
        contains(contains('Missing snapshot artifact')),
      );
      expect(
        partialArtifactDiff.warnings,
        contains(contains('Missing logs artifact')),
      );
      expect(
        partialArtifactDiff.warnings,
        contains(contains('Missing screenshot artifact')),
      );
    });

    test('preserve representative details for acceptance review', () {
      final RunDiff improvedDiff = _diffFixture('improved');
      final RunDiff regressedDiff = _diffFixture('regressed');
      final RunDiff changedDiff = _diffFixture('changed');

      expect(improvedDiff.resolvedSteps, hasLength(1));
      expect(improvedDiff.resolvedRuntimeFailures, <String>[
        'RenderFlex overflowed by 12 pixels',
      ]);
      expect(regressedDiff.regressions, hasLength(1));
      expect(regressedDiff.newRuntimeFailures, <String>[
        'setState() called after dispose()',
      ]);
      expect(changedDiff.screenshotChanges, hasLength(1));
      expect(changedDiff.visibleTextAdded, <String>['Continue']);
      expect(changedDiff.visibleTextRemoved, <String>['Retry']);
    });
  });
}

RunDiff _diffFixture(String name) {
  return RunDiffEngine.diffDirectories(
    beforeRunDirectory: Directory('test/fixtures/run_diff/$name/before'),
    afterRunDirectory: Directory('test/fixtures/run_diff/$name/after'),
  );
}
