import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Verifies that Scenario DSL documentation is synchronized with parser rules.
///
/// These tests exercise the public drift-checking surface that CI can run
/// whenever Scenario model or parser behavior changes.
void main() {
  group('Scenario DSL docs', () {
    test('reference documentation examples parse as valid Scenarios', () {
      final List<ScenarioDocExample> examples =
          ScenarioDocExamples.loadFromFile(
            File('docs/reference/scenario-dsl.md'),
          );

      expect(examples, isNotEmpty);
      for (final ScenarioDocExample example in examples) {
        expect(
          () => ScenarioParser.parse(
            loadYaml(example.yaml),
            fallbackName: example.name,
          ),
          returnsNormally,
          reason: 'Example `${example.name}` should parse as a Scenario.',
        );
      }
    });
  });
}
