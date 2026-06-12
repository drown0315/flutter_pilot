import 'dart:io';

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
}
