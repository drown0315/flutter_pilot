import 'dart:io';

import 'package:test/test.dart';

/// Exercises the one-command Scenario DSL documentation drift check.
void main() {
  test(
    'check_scenario_dsl_docs exits zero when reference docs are current',
    () async {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'tool/check_scenario_dsl_docs.dart'],
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Scenario DSL docs are current.'));
      expect(result.stderr, isEmpty);
    },
  );
}
