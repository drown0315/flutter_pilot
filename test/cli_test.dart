import 'dart:io';

import 'package:test/test.dart';

/// Exercise Flutter Pilot through a real Dart subprocess.
///
/// These tests verify the external CLI contract: exit codes, terminal output,
/// and accepted argument combinations.
void main() {
  test('validate exits zero for a valid scenario file', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/flutter_pilot.dart',
        'validate',
        'examples/login_error.yaml',
      ],
    );

    expect(result.exitCode, 0);
  });

  test('validate --json emits machine-readable errors', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'validate',
          'test/fixtures/invalid_finder_type.yaml',
          '--json',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stdout, contains('"valid": false'));
    expect(result.stdout, contains('steps[0].tap.byText'));
  });

  test('run rejects unknown --until values', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'run',
          'examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
          '--until',
          'missing_step',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('--until must be a 1-based step number'));
  });

  test('run requires --target', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'run', 'examples/login_error.yaml'],
    );

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('Missing required option --target'));
  });

  test('run rejects invalid target URI values', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'run',
          'examples/login_error.yaml',
          '--target',
          'not-a-uri',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('--target must be an absolute'));
  });

  test('run exits non-zero when the Scenario run fails', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_cli_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      final ProcessResult result =
          await Process.run(Platform.resolvedExecutable, [
            'run',
            '$packageRoot/bin/flutter_pilot.dart',
            'run',
            '$packageRoot/examples/login_error.yaml',
            '--target',
            'ws://127.0.0.1:1234/example=/ws',
          ], workingDirectory: tempDirectory.path);

      expect(result.exitCode, isNonZero);
      expect(result.stdout, contains('Run report:'));
      expect(result.stdout, contains('run_report.json'));
      expect(result.stdout, contains('HTML report:'));
      expect(result.stdout, contains('timeline.html'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('run help does not expose an html flag', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'run', '--help'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout, isNot(contains('--html')));
  });

  test('report generates HTML from an existing run directory', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_report_test_',
    );
    final Directory runDirectory = Directory('${tempDirectory.path}/run')
      ..createSync(recursive: true);
    try {
      File('${runDirectory.path}/run_report.json').writeAsStringSync('''
{
  "scenario": {
    "name": "existing_run"
  },
  "status": "failed",
  "startedAt": "2026-06-13T10:00:00.000Z",
  "durationMs": 42,
  "runDirectory": "${runDirectory.path}",
  "artifacts": [],
  "steps": [
    {
      "index": 1,
      "label": "submit",
      "action": "tap",
      "status": "failed",
      "durationMs": 12,
      "failureReason": "Finder matched no widgets."
    }
  ]
}
''');

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/flutter_pilot.dart', 'report', runDirectory.path],
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('HTML report:'));
      final File htmlFile = File('${runDirectory.path}/timeline.html');
      expect(htmlFile.existsSync(), isTrue);
      expect(htmlFile.readAsStringSync(), contains('existing_run'));
      expect(
        htmlFile.readAsStringSync(),
        contains('Finder matched no widgets.'),
      );
      expect(htmlFile.readAsStringSync(), contains('step-failed'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('run --print without --until exits non-zero', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'run',
          'examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
          '--print',
          'snapshot',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('--print must be used with --until'));
  });

  test('run rejects screenshot as printable output', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'run',
          'examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
          '--until',
          '1',
          '--print',
          'screenshot',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('[snapshot, widget-tree, errors]'));
  });

  test('run help exposes json output for raw diagnostics', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'run', '--help'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('--json'));
    expect(result.stdout, contains('Print raw diagnostics as indented JSON'));
  });
}
