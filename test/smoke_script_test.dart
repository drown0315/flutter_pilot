import 'dart:convert';
import 'dart:io';

import 'package:flutter_pilot/src/smoke_verifier.dart';
import 'package:test/test.dart';

/// Verifies the real-runtime smoke script command-line contract.
///
/// The live Flutter app path is intentionally not part of default unit tests;
/// this test only checks that the script fails clearly before external runtime
/// work begins.
void main() {
  test('smoke script requires a VM service URI', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/run_mcp_flutter_smoke.dart'],
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Usage:'));
  });

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

    test('passes when Finder Steps and capture artifacts are valid', () {
      final Directory runDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_smoke_report_',
      );
      try {
        final File reportFile = _writeSmokeReport(
          runDirectory: runDirectory,
          status: 'passed',
          stepStatuses: const <String, String>{
            'enter_email': 'passed',
            'submit_form': 'passed',
            'wait_for_error': 'passed',
            'capture_runtime': 'passed',
          },
          createArtifactFiles: true,
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
            'enter_email': 'passed',
            'submit_form': 'failed',
            'wait_for_error': 'skipped',
            'capture_runtime': 'skipped',
          },
          createArtifactFiles: true,
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

    test('fails when a required capture artifact file is missing', () {
      final Directory runDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_smoke_report_',
      );
      try {
        final File reportFile = _writeSmokeReport(
          runDirectory: runDirectory,
          status: 'passed',
          stepStatuses: const <String, String>{
            'enter_email': 'passed',
            'submit_form': 'passed',
            'wait_for_error': 'passed',
            'capture_runtime': 'passed',
          },
          createArtifactFiles: false,
        );

        final SmokeVerificationResult result =
            SmokeRunVerifier.verifyReportFile(reportFile);

        expect(result.passed, isFalse);
        expect(
          result.errors,
          contains(
            'Missing capture artifact file for screenshot: '
            '${runDirectory.path}/captures/0005_capture_runtime_screenshot.png',
          ),
        );
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
  required bool createArtifactFiles,
}) {
  final List<Map<String, Object?>> captureArtifacts = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'screenshot',
      'path': 'captures/0005_capture_runtime_screenshot.png',
      'purpose': 'capture',
    },
    <String, Object?>{
      'type': 'widgetTree',
      'path': 'captures/0005_capture_runtime_widget_tree.json',
      'purpose': 'capture',
    },
    <String, Object?>{
      'type': 'logs',
      'path': 'captures/0005_capture_runtime_logs.json',
      'purpose': 'capture',
    },
  ];
  if (createArtifactFiles) {
    for (final Map<String, Object?> artifact in captureArtifacts) {
      final String path = artifact['path']! as String;
      final File artifactFile = File('${runDirectory.path}/$path');
      artifactFile.parent.createSync(recursive: true);
      artifactFile.writeAsStringSync('{}');
    }
  }

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
        _stepJson(label: 'enter_email', action: 'type', status: stepStatuses),
        _stepJson(label: 'submit_form', action: 'tap', status: stepStatuses),
        _stepJson(
          label: 'wait_for_error',
          action: 'waitFor',
          status: stepStatuses,
        ),
        <String, Object?>{
          ..._stepJson(
            label: 'capture_runtime',
            action: 'capture',
            status: stepStatuses,
          ),
          'artifacts': captureArtifacts,
        },
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
