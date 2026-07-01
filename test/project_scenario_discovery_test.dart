import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies Project Scenario discovery through its public API.
///
/// These tests describe which Entry Scenario files are selected for a Project
/// Run. They avoid app launch and Scenario execution so discovery rules remain
/// testable as a small public contract.
void main() {
  group('ProjectScenarioDiscovery', () {
    test('uses pilot as the default Pilot Directory below a package root', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_default_pilot_discovery_test_',
      );
      try {
        Directory('${tempDirectory.path}/pilot').createSync();
        File('${tempDirectory.path}/pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');

        final List<ProjectScenarioFile> files =
            ProjectScenarioDiscovery.discoverDefault(
              packageDirectoryPath: tempDirectory.path,
            );

        expect(files.single.relativePath, 'login.yaml');
        expect(files.single.scenario.name, 'login');
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test(
      'discovers Scenario metadata files recursively in relative path order',
      () {
        final Directory tempDirectory = Directory.systemTemp.createTempSync(
          'flutter_pilot_project_discovery_test_',
        );
        try {
          File('${tempDirectory.path}/z_last.yaml').writeAsStringSync('''
scenario:
  name: z_last
steps:
  - capture: {}
''');
          Directory('${tempDirectory.path}/checkout').createSync();
          File('${tempDirectory.path}/checkout/a_first.yml').writeAsStringSync(
            '''
scenario:
  name: a_first
steps:
  - capture: {}
''',
          );
          File('${tempDirectory.path}/checkout/library.yaml').writeAsStringSync(
            '''
steps:
  - capture: {}
''',
          );
          File('${tempDirectory.path}/notes.txt').writeAsStringSync('not yaml');

          final List<ProjectScenarioFile> files =
              ProjectScenarioDiscovery.discoverInDirectory(tempDirectory.path);

          expect(
            files.map((ProjectScenarioFile file) => file.relativePath),
            <String>['checkout/a_first.yml', 'z_last.yaml'],
          );
          expect(
            files.map((ProjectScenarioFile file) => file.scenario.name),
            <String>['a_first', 'z_last'],
          );
        } finally {
          tempDirectory.deleteSync(recursive: true);
        }
      },
    );

    test(
      'throws a usage-level discovery error when no Project Scenarios exist',
      () {
        final Directory tempDirectory = Directory.systemTemp.createTempSync(
          'flutter_pilot_empty_project_discovery_test_',
        );
        try {
          File('${tempDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');

          expect(
            () => ProjectScenarioDiscovery.discoverInDirectory(
              tempDirectory.path,
            ),
            throwsA(
              isA<ProjectScenarioDiscoveryException>()
                  .having(
                    (ProjectScenarioDiscoveryException error) => error.message,
                    'message',
                    contains('No Project Scenarios found'),
                  )
                  .having(
                    (ProjectScenarioDiscoveryException error) =>
                        error.usageError,
                    'usageError',
                    isTrue,
                  ),
            ),
          );
        } finally {
          tempDirectory.deleteSync(recursive: true);
        }
      },
    );

    test('throws a usage-level discovery error when the root is missing', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_missing_project_discovery_test_',
      );
      try {
        final String missingDirectoryPath = '${tempDirectory.path}/missing';

        expect(
          () => ProjectScenarioDiscovery.discoverInDirectory(
            missingDirectoryPath,
          ),
          throwsA(
            isA<ProjectScenarioDiscoveryException>()
                .having(
                  (ProjectScenarioDiscoveryException error) => error.message,
                  'message',
                  contains('Project Scenario discovery root does not exist'),
                )
                .having(
                  (ProjectScenarioDiscoveryException error) => error.usageError,
                  'usageError',
                  isTrue,
                ),
          ),
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('throws Scenario validation errors for invalid discovered YAML', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_invalid_yaml_discovery_test_',
      );
      try {
        File('${tempDirectory.path}/broken.yaml').writeAsStringSync('''
scenario:
  name: broken
steps:
  - capture: [
''');

        expect(
          () =>
              ProjectScenarioDiscovery.discoverInDirectory(tempDirectory.path),
          throwsA(isA<ScenarioValidationException>()),
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('throws Scenario validation errors for invalid Project Scenarios', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_invalid_scenario_discovery_test_',
      );
      try {
        File('${tempDirectory.path}/invalid.yaml').writeAsStringSync('''
scenario:
  name: invalid
steps:
  - tap:
      byText:
        - Continue
''');

        expect(
          () =>
              ProjectScenarioDiscovery.discoverInDirectory(tempDirectory.path),
          throwsA(
            isA<ScenarioValidationException>().having(
              (ScenarioValidationException error) => error.errors.map(
                (ScenarioValidationError validationError) =>
                    validationError.path,
              ),
              'paths',
              contains('steps[0].tap.byText'),
            ),
          ),
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });
  });
}
