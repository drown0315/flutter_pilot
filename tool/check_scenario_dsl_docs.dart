import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:yaml/yaml.dart';

/// Check that Scenario DSL reference examples match parser behavior.
///
/// This script is intended for CI and local pre-commit checks. It exits non-zero
/// when a documented Scenario YAML example no longer parses.
void main() {
  final File referenceFile = File('docs/reference/scenario-dsl.md');
  final List<String> failures = <String>[];

  _checkExamples(referenceFile, failures);

  if (failures.isNotEmpty) {
    stderr.writeln('Scenario DSL docs are out of sync.');
    for (final String failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Scenario DSL docs are current.');
}

/// Parse every documented Scenario YAML example with the public parser.
void _checkExamples(File file, List<String> failures) {
  if (!file.existsSync()) {
    failures.add('${file.path} is missing.');
    return;
  }

  final List<ScenarioDocExample> examples = ScenarioDocExamples.loadFromFile(
    file,
  );
  if (examples.isEmpty) {
    failures.add('${file.path} contains no scenario-yaml examples.');
    return;
  }

  for (final ScenarioDocExample example in examples) {
    try {
      ScenarioParser.parse(loadYaml(example.yaml), fallbackName: example.name);
    } on ScenarioValidationException catch (error) {
      final String details = error.errors
          .map(
            (ScenarioValidationError validationError) =>
                '${validationError.path}: ${validationError.message}',
          )
          .join('; ');
      failures.add('Example `${example.name}` is invalid: $details');
    } on YamlException catch (error) {
      failures.add(
        'Example `${example.name}` is invalid YAML: ${error.message}',
      );
    }
  }
}
