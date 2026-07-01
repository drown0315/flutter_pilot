import 'dart:io';

/// One Scenario YAML example extracted from a documentation file.
///
/// It contains:
/// - `name`: the Markdown heading that introduced the example
/// - `yaml`: the fenced YAML body to validate with `ScenarioParser`
class ScenarioDocExample {
  const ScenarioDocExample({required this.name, required this.yaml});

  final String name;
  final String yaml;
}

/// Loader for Scenario examples embedded in documentation Markdown.
///
/// It extracts fenced code blocks declared as `scenario-yaml`. The most recent
/// Markdown heading before the fence becomes the example name.
class ScenarioDocExamples {
  ScenarioDocExamples._();

  /// Read a Markdown file and return all Scenario YAML examples in it.
  ///
  /// Args:
  /// `file` is a Markdown document containing fenced `scenario-yaml` blocks.
  ///
  /// Returns:
  /// Examples in document order. Missing files surface as `FileSystemException`
  /// so CI clearly reports the broken docs path.
  static List<ScenarioDocExample> loadFromFile(File file) {
    return load(file.readAsStringSync());
  }

  /// Extract Scenario YAML examples from Markdown text.
  ///
  /// Args:
  /// `markdown` is the full Markdown document text.
  ///
  /// Returns:
  /// Every fenced `scenario-yaml` block with the nearest preceding heading as
  /// its name, or `example_N` when no heading exists.
  static List<ScenarioDocExample> load(String markdown) {
    final List<String> lines = markdown.split('\n');
    final List<ScenarioDocExample> examples = <ScenarioDocExample>[];
    String? currentHeading;
    bool inScenarioFence = false;
    final List<String> yamlLines = <String>[];

    for (final String line in lines) {
      if (!inScenarioFence && line.startsWith('#')) {
        currentHeading = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      }

      if (line.trim() == '```scenario-yaml') {
        inScenarioFence = true;
        yamlLines.clear();
        continue;
      }

      if (inScenarioFence && line.trim() == '```') {
        final String name = currentHeading == null || currentHeading.isEmpty
            ? 'example_${examples.length + 1}'
            : currentHeading;
        examples.add(
          ScenarioDocExample(name: name, yaml: yamlLines.join('\n')),
        );
        inScenarioFence = false;
        yamlLines.clear();
        continue;
      }

      if (inScenarioFence) {
        yamlLines.add(line);
      }
    }

    return examples;
  }
}
