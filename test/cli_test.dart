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
    final File file = File('${Directory.systemTemp.path}/invalid_scenario.yaml')
      ..writeAsStringSync('''
steps:
  - tap:
      byText:
        - Log in
''');

    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/flutter_pilot.dart', 'validate', file.path, '--json'],
    );

    expect(result.exitCode, isNonZero);
    expect(result.stdout, contains('"valid":false'));
    expect(result.stdout, contains('steps[0].tap.byText'));
  });

  test(
    'run validates args and reports not implemented for a valid shell run',
    () async {
      final ProcessResult result =
          await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/flutter_pilot.dart',
            'run',
            'examples/login_error.yaml',
            '--target',
            'ws://127.0.0.1:1234/example=/ws',
          ]);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Runner is not implemented yet.'));
    },
  );

  test('run accepts --until with a 1-based step number', () async {
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
          'logs',
        ]);

    expect(result.exitCode, 0);
  });

  test('run accepts --until with an existing step label', () async {
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/flutter_pilot.dart',
          'run',
          'examples/login_error.yaml',
          '--target',
          'ws://127.0.0.1:1234/example=/ws',
          '--until',
          'submit_login',
        ]);

    expect(result.exitCode, 0);
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
}
