import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/run_diff_fixtures.dart';

/// Exercise `flutter_pilot diff` through real Dart subprocesses.
void main() {
  test('exits zero and reports unchanged Run Diff output', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_diff_test_',
    );
    final RunDiffRunPair runs = createTempRunPair(tempDirectory);
    try {
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

      final ProcessResult result = await _runDiff(runs);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Run Diff'));
      expect(result.stdout, contains('No Run Diff changes.'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('exits zero when Step Regressions are present', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_diff_test_',
    );
    final RunDiffRunPair runs = createTempRunPair(tempDirectory);
    try {
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

      final ProcessResult result = await _runDiff(runs);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Regressions:'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('prints machine-readable Run Diff JSON', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_diff_json_test_',
    );
    final RunDiffRunPair runs = createTempRunPair(tempDirectory);
    try {
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
            failureReason: 'Button stayed disabled.',
            durationMs: 10,
          ),
        ],
      );

      final ProcessResult result = await _runDiff(runs, json: true);
      final Map<String, Object?> output =
          jsonDecode(result.stdout as String) as Map<String, Object?>;

      expect(result.exitCode, 0);
      expect(output['beforeRunDirectory'], runs.beforeRun.path);
      expect(output['afterRunDirectory'], runs.afterRun.path);
      expect(output['outcome'], 'regressed');
      expect(output['regressions'], hasLength(1));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'reports missing and malformed run reports as execution errors',
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
        writeRunReport(validRun);
        File('${malformedRun.path}/run_report.json').writeAsStringSync('{');
        File(
          '${unsupportedRun.path}/run_report.json',
        ).writeAsStringSync('{"steps": []}');

        final ProcessResult missingDirectoryResult =
            await Process.run(Platform.resolvedExecutable, <String>[
              'run',
              'bin/flutter_pilot.dart',
              'diff',
              '${tempDirectory.path}/does_not_exist',
              validRun.path,
            ]);
        final ProcessResult missingReportResult = await Process.run(
          Platform.resolvedExecutable,
          <String>[
            'run',
            'bin/flutter_pilot.dart',
            'diff',
            missingReportRun.path,
            validRun.path,
          ],
        );
        final ProcessResult malformedResult = await Process.run(
          Platform.resolvedExecutable,
          <String>[
            'run',
            'bin/flutter_pilot.dart',
            'diff',
            malformedRun.path,
            validRun.path,
          ],
        );
        final ProcessResult unsupportedResult = await Process.run(
          Platform.resolvedExecutable,
          <String>[
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

/// Run `flutter_pilot diff` against a run pair.
Future<ProcessResult> _runDiff(RunDiffRunPair runs, {bool json = false}) {
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/flutter_pilot.dart',
    'diff',
    runs.beforeRun.path,
    runs.afterRun.path,
    if (json) '--json',
  ]);
}
