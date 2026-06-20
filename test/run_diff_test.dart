import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verify Run Diff behavior through its public engine and renderer APIs.
///
/// The tests create in-memory run directories with `run_report.json` files so
/// they exercise report loading, Step alignment, and user-visible findings
/// without depending on a live Flutter app.
void main() {
  test('reports passed-to-failed labeled Steps as Regressions', () async {
    await FileTestkit.runZoned(() async {
      final Directory beforeRun = Directory('/runs/before')
        ..createSync(recursive: true);
      final Directory afterRun = Directory('/runs/after')
        ..createSync(recursive: true);
      _writeRunReport(
        beforeRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "passed",
  "durationMs": 12
}
''',
        ],
      );
      _writeRunReport(
        afterRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "failed",
  "durationMs": 10,
  "failureReason": "Finder matched no widgets."
}
''',
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: beforeRun,
        afterRunDirectory: afterRun,
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
      final Directory beforeRun = Directory('/runs/before')
        ..createSync(recursive: true);
      final Directory afterRun = Directory('/runs/after')
        ..createSync(recursive: true);
      _writeRunReport(
        beforeRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "failed",
  "durationMs": 12,
  "failureReason": "Finder matched no widgets."
}
''',
        ],
      );
      _writeRunReport(
        afterRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "passed",
  "durationMs": 10
}
''',
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: beforeRun,
        afterRunDirectory: afterRun,
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
      final Directory beforeRun = Directory('/runs/before')
        ..createSync(recursive: true);
      final Directory afterRun = Directory('/runs/after')
        ..createSync(recursive: true);
      _writeRunReport(
        beforeRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "failed",
  "durationMs": 12,
  "failureReason": "Finder matched no widgets."
}
''',
        ],
      );
      _writeRunReport(
        afterRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 2,
  "label": "submit",
  "action": "tap",
  "status": "passed",
  "durationMs": 10
}
''',
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: beforeRun,
        afterRunDirectory: afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);

      expect(output, contains('Resolved Steps:'));
      expect(output, contains('submit'));
      expect(output, isNot(contains('Added Steps:')));
      expect(output, isNot(contains('missing labeled Step')));
    });
  });

  test(
    'distinguishes missing labeled, missing unlabeled, and added Steps',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory beforeRun = Directory('/runs/before')
          ..createSync(recursive: true);
        final Directory afterRun = Directory('/runs/after')
          ..createSync(recursive: true);
        _writeRunReport(
          beforeRun,
          scenarioName: 'login_error',
          steps: const <String>[
            '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "passed",
  "durationMs": 12
}
''',
            '''
{
  "index": 2,
  "action": "capture",
  "status": "passed",
  "durationMs": 3
}
''',
          ],
        );
        _writeRunReport(
          afterRun,
          scenarioName: 'login_error',
          steps: const <String>[
            '''
{
  "index": 3,
  "label": "confirmation",
  "action": "waitFor",
  "status": "passed",
  "durationMs": 10
}
''',
          ],
        );

        final RunDiff diff = RunDiffEngine.diffDirectories(
          beforeRunDirectory: beforeRun,
          afterRunDirectory: afterRun,
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
      final Directory beforeRun = Directory('/runs/before')
        ..createSync(recursive: true);
      final Directory afterRun = Directory('/runs/after')
        ..createSync(recursive: true);
      _writeRunReport(
        beforeRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "passed",
  "durationMs": 12
}
''',
        ],
      );
      _writeRunReport(
        afterRun,
        scenarioName: 'checkout_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "waitFor",
  "status": "passed",
  "durationMs": 10
}
''',
        ],
      );

      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: beforeRun,
        afterRunDirectory: afterRun,
      );
      final String output = RunDiffTextRenderer.render(diff);

      expect(output, contains('Warnings:'));
      expect(output, contains('login_error vs checkout_error'));
      expect(output, contains('Action Changes:'));
      expect(output, contains('tap -> waitFor'));
    });
  });

  test('diff CLI exits zero when Step Regressions are present', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_diff_test_',
    );
    final Directory beforeRun = Directory('${tempDirectory.path}/before')
      ..createSync(recursive: true);
    final Directory afterRun = Directory('${tempDirectory.path}/after')
      ..createSync(recursive: true);
    try {
      _writeRunReport(
        beforeRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "passed",
  "durationMs": 12
}
''',
        ],
      );
      _writeRunReport(
        afterRun,
        scenarioName: 'login_error',
        steps: const <String>[
          '''
{
  "index": 1,
  "label": "submit",
  "action": "tap",
  "status": "failed",
  "durationMs": 10,
  "failureReason": "Finder matched no widgets."
}
''',
        ],
      );

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'bin/flutter_pilot.dart',
          'diff',
          beforeRun.path,
          afterRun.path,
        ],
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Regressions:'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'diff CLI reports missing and malformed run reports as execution errors',
    () async {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_diff_error_test_',
      );
      final Directory validRun = Directory('${tempDirectory.path}/valid')
        ..createSync(recursive: true);
      final Directory missingReportRun = Directory(
        '${tempDirectory.path}/missing',
      )..createSync(recursive: true);
      final Directory malformedRun = Directory(
        '${tempDirectory.path}/malformed',
      )..createSync(recursive: true);
      final Directory unsupportedRun = Directory(
        '${tempDirectory.path}/unsupported',
      )..createSync(recursive: true);
      try {
        _writeRunReport(validRun, scenarioName: 'login_error', steps: const []);
        // Malformed JSON exercises syntax failures before report shape checks.
        File('${malformedRun.path}/run_report.json').writeAsStringSync('{');
        // Unsupported JSON is syntactically valid but lacks required
        // `scenario.name` metadata for Run Diff.
        File(
          '${unsupportedRun.path}/run_report.json',
        ).writeAsStringSync('{"steps": []}');

        final ProcessResult missingDirectoryResult =
            await Process.run(Platform.resolvedExecutable, [
              'run',
              'bin/flutter_pilot.dart',
              'diff',
              '${tempDirectory.path}/does_not_exist',
              validRun.path,
            ]);
        final ProcessResult missingReportResult = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'bin/flutter_pilot.dart',
            'diff',
            missingReportRun.path,
            validRun.path,
          ],
        );
        final ProcessResult malformedResult = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'bin/flutter_pilot.dart',
            'diff',
            malformedRun.path,
            validRun.path,
          ],
        );
        final ProcessResult unsupportedResult = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'bin/flutter_pilot.dart',
            'diff',
            unsupportedRun.path,
            validRun.path,
          ],
        );

        expect(missingDirectoryResult.exitCode, isNonZero);
        expect(
          missingDirectoryResult.stderr,
          contains('Run directory does not exist'),
        );
        expect(missingReportResult.exitCode, isNonZero);
        expect(missingReportResult.stderr, contains('Missing run_report.json'));
        expect(malformedResult.exitCode, isNonZero);
        expect(malformedResult.stderr, contains('Malformed run_report.json'));
        expect(unsupportedResult.exitCode, isNonZero);
        expect(
          unsupportedResult.stderr,
          contains('Unsupported run_report.json shape'),
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    },
  );
}

/// Write the smallest run report shape accepted by the Run Diff engine.
void _writeRunReport(
  Directory runDirectory, {
  required String scenarioName,
  required List<String> steps,
}) {
  File('${runDirectory.path}/run_report.json').writeAsStringSync('''
{
  "scenario": {
    "name": "$scenarioName"
  },
  "status": "passed",
  "startedAt": "2026-06-13T10:00:00.000Z",
  "durationMs": 42,
  "runDirectory": "${runDirectory.path}",
  "artifacts": [],
  "steps": [
    ${steps.join(',\n')}
  ]
}
''');
}
