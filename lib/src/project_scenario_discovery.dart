import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'scenario.dart';
import 'scenario_parser.dart';

/// One Entry Scenario file selected for a Project Run.
///
/// It contains the absolute or caller-provided file path used for parsing, the
/// POSIX-style path relative to the discovery root, and the validated Scenario
/// parsed from that file.
class ProjectScenarioFile {
  const ProjectScenarioFile({
    required this.path,
    required this.relativePath,
    required this.scenario,
  });

  /// Path passed to `ScenarioParser.parseFile`.
  final String path;

  /// Lexicographic Project Run ordering key relative to the discovery root.
  final String relativePath;

  /// Validated Entry Scenario parsed from [path].
  final Scenario scenario;
}

/// Exception thrown when Project Scenario discovery cannot produce a run list.
///
/// `usageError` marks discovery failures that should be presented as command
/// misuse before launching the Target App Package.
class ProjectScenarioDiscoveryException implements Exception {
  const ProjectScenarioDiscoveryException(
    this.message, {
    this.usageError = false,
  });

  final String message;
  final bool usageError;

  @override
  String toString() => message;
}

/// Discovers Project Scenarios from a Pilot Directory or explicit directory.
///
/// Directory discovery recursively scans `.yaml` and `.yml` files. Files with
/// top-level `scenario:` metadata are parsed as Entry Scenarios; metadata-free
/// YAML files are treated as Step Library candidates and are not returned.
class ProjectScenarioDiscovery {
  ProjectScenarioDiscovery._();

  /// Conventional directory used by `flutter_pilot test` with no path input.
  static const String defaultPilotDirectory = 'pilot';

  /// Return Project Scenarios from `pilot/` below [packageDirectoryPath].
  static List<ProjectScenarioFile> discoverDefault({
    String packageDirectoryPath = '.',
  }) {
    return discoverInDirectory(
      p.join(packageDirectoryPath, defaultPilotDirectory),
    );
  }

  /// Return validated Project Scenarios from [directoryPath].
  ///
  /// Results are sorted by POSIX-style path relative to [directoryPath]. YAML
  /// files that cannot be decoded or files with invalid Scenario metadata throw
  /// `ScenarioValidationException`.
  static List<ProjectScenarioFile> discoverInDirectory(String directoryPath) {
    final Directory directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw ProjectScenarioDiscoveryException(
        'Project Scenario discovery root does not exist: ${directory.path}.',
        usageError: true,
      );
    }
    final List<ProjectScenarioFile> discovered = <ProjectScenarioFile>[];
    for (final File file in _yamlFiles(directory)) {
      if (!_hasScenarioMetadata(file)) {
        continue;
      }
      final Scenario scenario = ScenarioParser.parseFile(file.path);
      discovered.add(
        ProjectScenarioFile(
          path: file.path,
          relativePath: _relativePosixPath(directory.path, file.path),
          scenario: scenario,
        ),
      );
    }
    discovered.sort(
      (ProjectScenarioFile a, ProjectScenarioFile b) =>
          a.relativePath.compareTo(b.relativePath),
    );
    if (discovered.isEmpty) {
      throw ProjectScenarioDiscoveryException(
        'No Project Scenarios found in ${directory.path}.',
        usageError: true,
      );
    }
    return discovered;
  }

  /// Return YAML files below [directory] without following symlink loops.
  static Iterable<File> _yamlFiles(Directory directory) sync* {
    final List<File> entities = directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList();
    for (final File file in entities) {
      final String extension = p.extension(file.path).toLowerCase();
      if (extension == '.yaml' || extension == '.yml') {
        yield file;
      }
    }
  }

  /// Return whether [file] declares top-level Scenario metadata.
  static bool _hasScenarioMetadata(File file) {
    Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync());
    } on YamlException catch (error) {
      throw ScenarioValidationException([
        ScenarioValidationError(file.path, 'Invalid YAML: ${error.message}'),
      ]);
    } on FileSystemException catch (error) {
      throw ScenarioValidationException([
        ScenarioValidationError(
          file.path,
          'Cannot read file: ${error.message}',
        ),
      ]);
    }
    return yaml is YamlMap && yaml.containsKey('scenario');
  }

  /// Convert the file path below [rootPath] into a POSIX-style relative path.
  static String _relativePosixPath(String rootPath, String filePath) {
    final String relativePath = p.relative(filePath, from: rootPath);
    return p.split(relativePath).join('/');
  }
}
