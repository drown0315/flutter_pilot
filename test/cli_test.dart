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

  test('run exits non-zero when the Scenario run fails', skip: true, () async {
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

  test(
    'run emits successful Step progress to stderr with fake runtime',
    () async {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_cli_progress_test_',
      );
      final String packageRoot = Directory.current.absolute.path;
      try {
        final ProcessResult result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            '$packageRoot/bin/flutter_pilot.dart',
            'run',
            '$packageRoot/examples/login_error.yaml',
            '--target',
            'ws://127.0.0.1:1234/example=/ws',
          ],
          workingDirectory: tempDirectory.path,
          environment: <String, String>{
            'FLUTTER_PILOT_TEST_RUNTIME': 'success',
          },
        );

        expect(result.exitCode, 0);
        expect(result.stderr, contains('Scenario: login_error (5 steps)'));
        expect(result.stderr, contains('1/5 type    enter_email    running'));
        expect(result.stderr, contains('1/5 type    enter_email    ok '));
        expect(result.stderr, contains('2/5 type    enter_password running'));
        expect(result.stderr, contains('3/5 tap     submit_login   ok '));
        expect(result.stderr, contains('4/5 waitFor wait_for_error ok '));
        expect(result.stderr, contains('5/5 capture capture_error  ok '));
        expect(result.stdout, contains('Run report:'));
        expect(result.stdout, contains('run_report.json'));
        expect(result.stdout, contains('HTML report:'));
        expect(result.stdout, contains('timeline.html'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    },
  );

  test('run --json suppresses Step progress with fake runtime', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_cli_json_progress_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '$packageRoot/bin/flutter_pilot.dart',
          'run',
          '$packageRoot/examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
          '--json',
        ],
        workingDirectory: tempDirectory.path,
        environment: <String, String>{'FLUTTER_PILOT_TEST_RUNTIME': 'success'},
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(result.stdout, contains('Run report:'));
      expect(result.stdout, contains('HTML report:'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'run --json still prints a report summary without progress text',
    () async {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_cli_json_summary_test_',
      );
      final String packageRoot = Directory.current.absolute.path;
      try {
        final ProcessResult result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            '$packageRoot/bin/flutter_pilot.dart',
            'run',
            '$packageRoot/examples/login_error.yaml',
            '--target',
            'ws://127.0.0.1:1234/example=/ws',
            '--json',
          ],
          workingDirectory: tempDirectory.path,
          environment: <String, String>{
            'FLUTTER_PILOT_TEST_RUNTIME': 'success',
          },
        );

        expect(result.exitCode, 0);
        expect(result.stderr, isEmpty);
        expect(result.stdout, contains('Run report:'));
        expect(result.stdout, contains('HTML report:'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    },
  );

  test('run emits failed Step progress with concise summary', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_cli_failed_progress_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '$packageRoot/bin/flutter_pilot.dart',
          'run',
          '$packageRoot/examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
        ],
        workingDirectory: tempDirectory.path,
        environment: <String, String>{'FLUTTER_PILOT_TEST_RUNTIME': 'failure'},
      );

      expect(result.exitCode, isNonZero);
      expect(result.stderr, contains('failed after'));
      expect(result.stderr, contains('Finder matched no widgets.'));
      expect(result.stdout, contains('run_report.json'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('run prints a passed summary for complete runs', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_cli_pass_summary_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '$packageRoot/bin/flutter_pilot.dart',
          'run',
          '$packageRoot/examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
        ],
        workingDirectory: tempDirectory.path,
        environment: <String, String>{'FLUTTER_PILOT_TEST_RUNTIME': 'success'},
      );

      expect(result.exitCode, 0);
      expect(result.stderr, contains('Run passed.'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('run prints a stopped summary for --until', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_cli_until_summary_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '$packageRoot/bin/flutter_pilot.dart',
          'run',
          '$packageRoot/examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
          '--until',
          '2',
        ],
        workingDirectory: tempDirectory.path,
        environment: <String, String>{'FLUTTER_PILOT_TEST_RUNTIME': 'success'},
      );

      expect(result.exitCode, 0);
      expect(result.stderr, contains('Stopped after 2/5.'));
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
    expect(result.stdout, isNot(contains('FLUTTER_PILOT_TEST_RUNTIME')));
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

  test('doctor reports complete Flutter Pilot app setup', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_doctor_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      File('${tempDirectory.path}/pubspec.yaml').writeAsStringSync('''
name: target_app
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  mcp_toolkit: ^3.0.0
''');
      final Directory libDirectory = Directory('${tempDirectory.path}/lib')
        ..createSync(recursive: true);
      File('${libDirectory.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () => runApp(const Placeholder()),
  );
}
''');

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['$packageRoot/bin/flutter_pilot.dart', 'doctor'],
        workingDirectory: tempDirectory.path,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Flutter Pilot doctor'));
      expect(result.stdout, contains('✅ Flutter Pilot app setup is complete.'));
      expect(result.stderr, isEmpty);
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('doctor reports missing app setup without failing the check', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_doctor_missing_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      File('${tempDirectory.path}/pubspec.yaml').writeAsStringSync('''
name: target_app
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
''');
      final Directory libDirectory = Directory('${tempDirectory.path}/lib')
        ..createSync(recursive: true);
      File('${libDirectory.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  runApp(const Placeholder());
}
''');

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['$packageRoot/bin/flutter_pilot.dart', 'doctor'],
        workingDirectory: tempDirectory.path,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Flutter Pilot doctor'));
      expect(
        result.stdout,
        contains(
          '❌ MCP Toolkit dependency missing: run `flutter pub add mcp_toolkit`',
        ),
      );
      expect(
        result.stdout,
        contains(
          '❌ bootstrapFlutter missing: add MCPToolkitBinding.instance.bootstrapFlutter in lib/main.dart',
        ),
      );
      expect(result.stderr, isEmpty);
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('doctor rejects non-Flutter packages', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_doctor_non_flutter_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      File('${tempDirectory.path}/pubspec.yaml').writeAsStringSync('''
name: dart_package
environment:
  sdk: ^3.9.0
dependencies:
  path: ^1.9.1
''');

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['$packageRoot/bin/flutter_pilot.dart', 'doctor'],
        workingDirectory: tempDirectory.path,
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        contains(
          'Flutter Pilot only supports Flutter packages. Run this command from a directory with a pubspec.yaml that declares dependencies.flutter.sdk: flutter.',
        ),
      );
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'doctor rejects directories without pubspec as non-Flutter packages',
    () async {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_doctor_no_pubspec_test_',
      );
      final String packageRoot = Directory.current.absolute.path;
      try {
        final ProcessResult result = await Process.run(
          Platform.resolvedExecutable,
          ['$packageRoot/bin/flutter_pilot.dart', 'doctor'],
          workingDirectory: tempDirectory.path,
        );

        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          contains(
            'Flutter Pilot only supports Flutter packages. Run this command from a directory with a pubspec.yaml that declares dependencies.flutter.sdk: flutter.',
          ),
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    },
  );

  test('init reports existing complete Flutter Pilot app setup', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_init_existing_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      File('${tempDirectory.path}/pubspec.yaml').writeAsStringSync('''
name: target_app
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  mcp_toolkit: ^3.0.0
''');
      final Directory libDirectory = Directory('${tempDirectory.path}/lib')
        ..createSync(recursive: true);
      File('${libDirectory.path}/main.dart').writeAsStringSync('''
Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () {},
  );
}
''');

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['$packageRoot/bin/flutter_pilot.dart', 'init'],
        workingDirectory: tempDirectory.path,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Flutter Pilot init'));
      expect(
        result.stdout,
        contains('✅ MCP Toolkit dependency already exists.'),
      );
      expect(result.stdout, contains('✅ bootstrapFlutter already exists.'));
      expect(result.stderr, isEmpty);
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'init prints bootstrap guidance when entrypoint is not bootstrapped',
    () async {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_init_bootstrap_test_',
      );
      final String packageRoot = Directory.current.absolute.path;
      try {
        File('${tempDirectory.path}/pubspec.yaml').writeAsStringSync('''
name: target_app
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  mcp_toolkit: ^3.0.0
''');
        final Directory libDirectory = Directory('${tempDirectory.path}/lib')
          ..createSync(recursive: true);
        File('${libDirectory.path}/main.dart').writeAsStringSync('''
void main() {
  runApp(const Placeholder());
}
''');

        final ProcessResult result = await Process.run(
          Platform.resolvedExecutable,
          ['$packageRoot/bin/flutter_pilot.dart', 'init'],
          workingDirectory: tempDirectory.path,
        );

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            '❌ bootstrapFlutter missing: add MCPToolkitBinding.instance.bootstrapFlutter in lib/main.dart',
          ),
        );
        expect(
          result.stdout,
          contains("import 'package:mcp_toolkit/mcp_toolkit.dart';"),
        );
        expect(
          result.stdout,
          contains('await MCPToolkitBinding.instance.bootstrapFlutter('),
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    },
  );
}
