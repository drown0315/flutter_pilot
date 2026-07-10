import 'dart:io';

import 'package:test/test.dart';

/// Verifies that internal Scenario YAML command examples reference live files.
void main() {
  test('internal Scenario YAML docs use the current smoke Scenario path', () {
    final String markdown = File(
      'docs-internal/scenario-yaml.md',
    ).readAsStringSync();

    expect(markdown, contains('examples/smoke_app/smoke_scenario.yaml'));
    expect(markdown, isNot(contains('examples/smoke_scenario.yaml')));
  });
}
