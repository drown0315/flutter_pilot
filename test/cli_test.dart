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

  test(
    'validate accepts scenario files backed by Step Library includes',
    () async {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_cli_include_validate_test_',
      );
      final String packageRoot = Directory.current.absolute.path;
      try {
        File('${tempDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - label: enter_email
    type:
      byType: textField
      text: bad@example.com
  - label: submit_login
    tap:
      byText: Log in
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: include_cli
steps:
  - include: library.yaml
''');

        final ProcessResult result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            '$packageRoot/bin/flutter_pilot.dart',
            'validate',
            scenarioFile.path,
          ],
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('Scenario is valid.'));
        expect(result.stderr, isEmpty);
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    },
  );

  test('validate --json reports include validation paths', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_cli_include_json_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    try {
      final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
        ..writeAsStringSync('''
steps:
  - include: missing.yaml
''');

      final ProcessResult result =
          await Process.run(Platform.resolvedExecutable, [
            'run',
            '$packageRoot/bin/flutter_pilot.dart',
            'validate',
            scenarioFile.path,
            '--json',
          ]);

      expect(result.exitCode, isNonZero);
      expect(result.stdout, contains('"valid": false'));
      expect(result.stdout, contains('"path": "steps[0].include"'));
      expect(result.stdout, contains('missing.yaml'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('validate accepts and rejects Scenario Recording schema', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_pilot_recording_validate_test_',
    );
    final String packageRoot = Directory.current.absolute.path;
    final File validScenario = File('${tempDirectory.path}/valid.yaml')
      ..writeAsStringSync('''
scenario:
  name: recording_enabled
  recording: {}
steps:
  - tap:
      byText: Continue
''');
    final File invalidScenario = File('${tempDirectory.path}/invalid.yaml')
      ..writeAsStringSync('''
scenario:
  name: recording_shorthand
  recording: true
steps:
  - tap:
      byText: Continue
''');

    try {
      final ProcessResult validResult = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '$packageRoot/bin/flutter_pilot.dart',
          'validate',
          validScenario.path,
        ],
      );
      final ProcessResult invalidResult =
          await Process.run(Platform.resolvedExecutable, [
            'run',
            '$packageRoot/bin/flutter_pilot.dart',
            'validate',
            invalidScenario.path,
          ]);

      expect(validResult.exitCode, 0);
      expect(invalidResult.exitCode, isNonZero);
      expect(invalidResult.stderr, contains('scenario.recording'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('run is no longer registered as a command', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'run', '--help'],
    );

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('Could not find a command named "run"'));
  });

  test('test help exposes launch and diagnostic options', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'test', '--help'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('--device'));
    expect(result.stdout, contains('--flavor'));
    expect(result.stdout, contains('--target'));
    expect(result.stdout, contains('--until'));
    expect(result.stdout, contains('--print'));
    expect(result.stdout, contains('--json'));
    expect(result.stdout, isNot(contains('--html')));
  });

  test('test rejects unknown --until values before app launch', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'test',
          'examples/login_error.yaml',
          '--until',
          'missing_step',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('--until must be a 1-based step number'));
  });

  test('test requires exactly one scenario file', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'test'],
    );

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('Expected exactly one scenario file'));
  });

  test('test validates scenario before app launch', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'test',
          'test/fixtures/invalid_finder_type.yaml',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('steps[0].tap.byText'));
    expect(
      result.stderr,
      isNot(contains('test command app launch is not implemented yet')),
    );
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
            'test',
            '$packageRoot/examples/login_error.yaml',
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

  test('test --print without --until exits non-zero', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'test',
          'examples/login_error.yaml',
          '--print',
          'snapshot',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('--print must be used with --until'));
  });

  test('test rejects screenshot as printable output', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'test',
          'examples/login_error.yaml',
          '--until',
          '1',
          '--print',
          'screenshot',
        ]);

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('[snapshot, widget-tree, errors]'));
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
