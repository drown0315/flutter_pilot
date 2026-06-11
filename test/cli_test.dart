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
    expect(result.stdout, contains('"valid":false'));
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
