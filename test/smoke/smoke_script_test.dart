import 'dart:convert';
import 'dart:io';

import 'package:flutter_pilot/src/smoke/smoke_verifier.dart';
import 'package:test/test.dart';

/// Verifies the real-runtime smoke report contract.
void main() {
  group('SmokeRunVerifier', () {
    test('extracts the run report path from Flutter Pilot stdout', () {
      final String? reportPath = SmokeRunVerifier.runReportPathFromStdout('''
Run report: .runs/2026-06-19_10-20_smoke_runtime/run_report.json
HTML report: .runs/2026-06-19_10-20_smoke_runtime/timeline.html
''');

      expect(
        reportPath,
        '.runs/2026-06-19_10-20_smoke_runtime/run_report.json',
      );
    });

    test('passes when required smoke Steps are valid', () {
      final Directory runDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_smoke_report_',
      );
      try {
        final File reportFile = _writeSmokeReport(
          runDirectory: runDirectory,
          status: 'passed',
          stepStatuses: const <String, String>{
            'wait_for_smoke_form': 'passed',
            'enter_email': 'passed',
            'submit_form': 'passed',
            'wait_for_error': 'passed',
          },
        );

        final SmokeVerificationResult result =
            SmokeRunVerifier.verifyReportFile(reportFile);

        expect(result.passed, isTrue);
        expect(result.errors, isEmpty);
      } finally {
        runDirectory.deleteSync(recursive: true);
      }
    });

    test('fails when a Finder Step failed', () {
      final Directory runDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_smoke_report_',
      );
      try {
        final File reportFile = _writeSmokeReport(
          runDirectory: runDirectory,
          status: 'failed',
          stepStatuses: const <String, String>{
            'wait_for_smoke_form': 'passed',
            'enter_email': 'passed',
            'submit_form': 'failed',
            'wait_for_error': 'skipped',
          },
        );

        final SmokeVerificationResult result =
            SmokeRunVerifier.verifyReportFile(reportFile);

        expect(result.passed, isFalse);
        expect(
          result.errors,
          contains('Expected run status passed, got failed.'),
        );
        expect(
          result.errors,
          contains('Expected Finder Step submit_form to pass, got failed.'),
        );
      } finally {
        runDirectory.deleteSync(recursive: true);
      }
    });

    test('fails when a required smoke Step is missing', () {
      final Directory runDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_smoke_report_',
      );
      try {
        final File reportFile = _writeSmokeReport(
          runDirectory: runDirectory,
          status: 'passed',
          stepStatuses: const <String, String>{
            'wait_for_smoke_form': 'passed',
            'enter_email': 'passed',
            'submit_form': 'passed',
          },
        );

        final SmokeVerificationResult result =
            SmokeRunVerifier.verifyReportFile(reportFile);

        expect(result.passed, isFalse);
        expect(result.errors, contains('Missing Finder Step: wait_for_error.'));
      } finally {
        runDirectory.deleteSync(recursive: true);
      }
    });
  });
}

/// Write a representative smoke `run_report.json` for verifier tests.
File _writeSmokeReport({
  required Directory runDirectory,
  required String status,
  required Map<String, String> stepStatuses,
}) {
  final File reportFile = File('${runDirectory.path}/run_report.json');
  reportFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'scenario': <String, Object?>{'name': 'smoke_runtime'},
      'status': status,
      'startedAt': '2026-06-19T10:20:00.000Z',
      'durationMs': 42,
      'runDirectory': runDirectory.path,
      'artifacts': const <Object?>[],
      'steps': <Object?>[
        if (stepStatuses.containsKey('wait_for_smoke_form'))
          _stepJson(
            label: 'wait_for_smoke_form',
            action: 'waitFor',
            status: stepStatuses,
          ),
        if (stepStatuses.containsKey('enter_email'))
          _stepJson(label: 'enter_email', action: 'type', status: stepStatuses),
        if (stepStatuses.containsKey('submit_form'))
          _stepJson(label: 'submit_form', action: 'tap', status: stepStatuses),
        if (stepStatuses.containsKey('wait_for_error'))
          _stepJson(
            label: 'wait_for_error',
            action: 'waitFor',
            status: stepStatuses,
          ),
      ],
    }),
  );
  return reportFile;
}

/// Return one Step object in the run report fixture.
Map<String, Object?> _stepJson({
  required String label,
  required String action,
  required Map<String, String> status,
}) {
  return <String, Object?>{
    'index': status.keys.toList().indexOf(label) + 1,
    'label': label,
    'action': action,
    'status': status[label],
    'durationMs': 1,
  };
}
