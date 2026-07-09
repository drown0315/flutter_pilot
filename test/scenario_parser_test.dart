import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Exercise Scenario parsing through the public parser API.
///
/// These tests describe YAML behavior rather than parser internals: valid YAML
/// returns a typed Scenario, and invalid YAML throws a validation exception with
/// field paths.
void main() {
  group('ScenarioParser', () {
    test('parses a valid scenario with combined Finder and defaults', () {
      final Scenario scenario = parseScenario('''
scenario:
  name: login_error
  description: Reproduces the login validation error
steps:
  - label: submit_login
    tap:
      byText: Log in
      byType: button
  - label: wait_for_error
    waitFor:
      byText: Invalid password
  - label: capture_error
    capture: {}
''');

      expect(scenario.name, 'login_error');
      expect(scenario.description, 'Reproduces the login validation error');
      expect(scenario.steps, hasLength(3));

      final TapAction tap = scenario.steps[0].action as TapAction;
      expect(tap.finder.byText, 'Log in');
      expect(tap.finder.byType, 'button');

      final WaitForAction waitFor = scenario.steps[1].action as WaitForAction;
      expect(waitFor.timeoutMs, 3000);

      final CaptureAction capture = scenario.steps[2].action as CaptureAction;
      expect(capture.screenshot, isTrue);
      expect(capture.snapshot, isFalse);
      expect(capture.widgetTree, isTrue);
      expect(capture.logs, isTrue);
    });

    test('parses optional Scenario Recording metadata', () {
      final Scenario omitted = parseScenario('''
scenario:
  name: no_recording
steps:
  - tap:
      byText: Continue
''');
      final Scenario defaultEnabled = parseScenario('''
scenario:
  name: default_recording
  recording: {}
steps:
  - tap:
      byText: Continue
''');
      final Scenario explicitlyEnabled = parseScenario('''
scenario:
  name: explicit_recording
  recording:
    enabled: true
steps:
  - tap:
      byText: Continue
''');
      final Scenario explicitlyDisabled = parseScenario('''
scenario:
  name: disabled_recording
  recording:
    enabled: false
steps:
  - tap:
      byText: Continue
''');

      expect(omitted.recording, isNull);
      expect(defaultEnabled.recording!.enabled, isTrue);
      expect(explicitlyEnabled.recording!.enabled, isTrue);
      expect(explicitlyDisabled.recording!.enabled, isFalse);
    });

    test('rejects invalid Scenario Recording schema', () {
      final List<String> shorthandPaths = invalidPaths('''
scenario:
  recording: true
steps:
  - tap:
      byText: Continue
''');
      final List<String> unknownFieldPaths = invalidPaths('''
scenario:
  recording:
    mode: full
steps:
  - tap:
      byText: Continue
''');

      expect(shorthandPaths, contains('scenario.recording'));
      expect(unknownFieldPaths, contains('scenario.recording.mode'));
    });

    test('reports unknown fields with field paths', () {
      final List<String> paths = invalidPaths('''
scenario:
  name: login_error
extra: no
steps:
  - label: submit_login
    tap:
      byText: Log in
      unknown: no
''');

      expect(paths, containsAll([r'$.extra', 'steps[0].tap.unknown']));
    });

    test('rejects invalid Finder value types', () {
      final List<String> paths = invalidPaths('''
steps:
  - tap:
      byText:
        - Log in
''');

      expect(paths, contains('steps[0].tap.byText'));
    });

    test('rejects duplicate labels and invalid slugs', () {
      final List<String> paths = invalidPaths('''
scenario:
  name: -bad
steps:
  - label: repeat
    tap:
      byText: A
  - label: repeat
    tap:
      byText: B
  - label: -bad
    tap:
      byText: C
''');

      expect(
        paths,
        containsAll(['scenario.name', 'steps[1].label', 'steps[2].label']),
      );
    });

    test('rejects label-only and multi-action steps', () {
      final List<String> paths = invalidPaths('''
steps:
  - label: only_label
  - tap:
      byText: A
    waitFor:
      byText: B
''');

      expect(paths, containsAll(['steps[0]', 'steps[1]']));
    });

    test('parses type and scroll actions', () {
      final Scenario scenario = parseScenario('''
steps:
  - type:
      byText: Email
      text: bad@example.com
  - scroll:
      byType: scrollable
      deltaY: -500
''');

      final TypeAction type = scenario.steps[0].action as TypeAction;
      expect(type.finder.byText, 'Email');
      expect(type.text, 'bad@example.com');

      final ScrollAction scroll = scenario.steps[1].action as ScrollAction;
      expect(scroll.finder!.byType, 'scrollable');
      expect(scroll.deltaX, 0.0);
      expect(scroll.deltaY, -500.0);
    });

    test('rejects scroll with zero deltas', () {
      final List<String> paths = invalidPaths('''
steps:
  - scroll:
      deltaY: 0
''');

      expect(paths, contains('steps[0].scroll'));
    });

    test('rejects errors as a first-version capture field', () {
      final List<String> paths = invalidPaths('''
steps:
  - capture:
      errors: true
''');

      expect(paths, contains('steps[0].capture.errors'));
    });

    test('rejects snapshot as a capture field', () {
      final List<String> paths = invalidPaths('''
steps:
  - capture:
      snapshot: true
''');

      expect(paths, contains('steps[0].capture.snapshot'));
    });

    test('parseFile expands Step Library includes into a flat Step list', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_include_test_',
      );
      try {
        final File libraryFile = File('${tempDirectory.path}/login_steps.yaml')
          ..writeAsStringSync('''
steps:
  - label: enter_email
    type:
      byType: textField
      text: bad@example.com
  - label: submit_login
    tap:
      byText: Log in
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: include_smoke
steps:
  - label: open_login
    tap:
      byText: Sign in
  - include: ${libraryFile.uri.pathSegments.last}
  - label: capture_error
    capture: {}
''');

        final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);

        expect(scenario.name, 'include_smoke');
        expect(scenario.steps.map((ScenarioStep step) => step.index), <int>[
          1,
          2,
          3,
          4,
        ]);
        expect(scenario.steps.map((ScenarioStep step) => step.label), <String?>[
          'open_login',
          'enter_email',
          'submit_login',
          'capture_error',
        ]);
        expect(scenario.steps[1].action, isA<TypeAction>());
        expect(scenario.steps[2].action, isA<TapAction>());
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile expands nested relative includes', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_nested_include_test_',
      );
      try {
        Directory('${tempDirectory.path}/flows').createSync();
        Directory('${tempDirectory.path}/shared').createSync();
        File('${tempDirectory.path}/shared/capture.yaml').writeAsStringSync('''
steps:
  - label: capture_checkout
    capture: {}
''');
        File('${tempDirectory.path}/flows/login.yaml').writeAsStringSync('''
steps:
  - label: submit_login
    tap:
      byText: Log in
  - include: ../shared/capture.yaml
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: flows/login.yaml
''');

        final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);

        expect(scenario.steps.map((ScenarioStep step) => step.label), <String?>[
          'submit_login',
          'capture_checkout',
        ]);
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile accepts absolute include paths', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_absolute_include_test_',
      );
      try {
        final File libraryFile = File('${tempDirectory.path}/library.yaml')
          ..writeAsStringSync('''
steps:
  - label: absolute_capture
    capture: {}
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: ${libraryFile.absolute.path}
''');

        final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);

        expect(scenario.steps.single.label, 'absolute_capture');
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile rejects Step Libraries with scenario metadata', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_library_metadata_test_',
      );
      try {
        File('${tempDirectory.path}/library.yaml').writeAsStringSync('''
scenario:
  name: not_allowed
steps:
  - capture: {}
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: library.yaml
''');

        final List<String> paths = invalidFilePaths(scenarioFile.path);

        expect(paths, contains('steps[0].include.scenario'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile rejects include entries with extra fields', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_include_extra_test_',
      );
      try {
        File('${tempDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - label: invalid_include
    include: library.yaml
''');

        final List<String> paths = invalidFilePaths(scenarioFile.path);

        expect(paths, contains('steps[0].label'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile rejects duplicate labels after include expansion', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_duplicate_include_label_test_',
      );
      try {
        File('${tempDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - label: repeated
    capture: {}
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: library.yaml
  - label: repeated
    tap:
      byText: Again
''');

        final List<String> paths = invalidFilePaths(scenarioFile.path);

        expect(paths, contains('steps[1].label'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile rejects missing include files with include path', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_missing_include_test_',
      );
      try {
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: missing.yaml
''');

        final List<ScenarioValidationError> errors = invalidFileErrors(
          scenarioFile.path,
        );

        expect(errors.single.path, 'steps[0].include');
        expect(errors.single.message, contains('missing.yaml'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile rejects invalid included YAML with include path', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_invalid_include_yaml_test_',
      );
      try {
        File('${tempDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - tap:
      byText: [unterminated
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: library.yaml
''');

        final List<ScenarioValidationError> errors = invalidFileErrors(
          scenarioFile.path,
        );

        expect(errors.single.path, 'steps[0].include');
        expect(errors.single.message, contains('library.yaml'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile rejects include cycles', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_include_cycle_test_',
      );
      try {
        File('${tempDirectory.path}/a.yaml').writeAsStringSync('''
steps:
  - include: b.yaml
''');
        File('${tempDirectory.path}/b.yaml').writeAsStringSync('''
steps:
  - include: a.yaml
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: a.yaml
''');

        final List<ScenarioValidationError> errors = invalidFileErrors(
          scenarioFile.path,
        );

        expect(
          errors.single.path,
          'steps[0].include.steps[0].include.steps[0].include',
        );
        expect(errors.single.message, contains('cycle'));
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('in-memory parsing rejects include entries without file context', () {
      final List<String> paths = invalidPaths('''
steps:
  - include: login.yaml
''');

      expect(paths, contains('steps[0].include'));
    });

    test(
      'parseFile records Step Source metadata for root and included Steps',
      () {
        final Directory tempDirectory = Directory.systemTemp.createTempSync(
          'flutter_pilot_parser_source_test_',
        );
        try {
          Directory('${tempDirectory.path}/flows').createSync();
          File('${tempDirectory.path}/flows/login.yaml').writeAsStringSync('''
steps:
  - label: included_step
    capture: {}
''');
          final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
            ..writeAsStringSync('''
steps:
  - label: root_step
    tap:
      byText: Sign in
  - include: flows/login.yaml
''');

          final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);
          final StepSource rootSource = scenario.steps[0].source!;
          final StepSource includedSource = scenario.steps[1].source!;

          expect(
            rootSource.fileIdentity,
            scenarioFile.resolveSymbolicLinksSync(),
          );
          expect(rootSource.displayPath, scenarioFile.path);
          expect(rootSource.yamlPath, 'steps[0]');
          expect(rootSource.includeChain, isEmpty);
          expect(
            includedSource.fileIdentity,
            File(
              '${tempDirectory.path}/flows/login.yaml',
            ).resolveSymbolicLinksSync(),
          );
          expect(includedSource.displayPath, 'flows/login.yaml');
          expect(includedSource.yamlPath, 'steps[0]');
          expect(includedSource.includeChain, hasLength(1));
          expect(
            includedSource.includeChain.single.includePath,
            'steps[1].include',
          );
          expect(
            includedSource.includeChain.single.displayPath,
            'flows/login.yaml',
          );
        } finally {
          tempDirectory.deleteSync(recursive: true);
        }
      },
    );

    test('parseFile records nested and repeated Include Chains', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_nested_source_test_',
      );
      try {
        Directory('${tempDirectory.path}/flows').createSync();
        Directory('${tempDirectory.path}/shared').createSync();
        File('${tempDirectory.path}/shared/capture_a.yaml').writeAsStringSync(
          '''
steps:
  - label: shared_a_first
    capture: {}
  - label: shared_a_second
    capture: {}
''',
        );
        File('${tempDirectory.path}/shared/capture_b.yaml').writeAsStringSync(
          '''
steps:
  - label: shared_b_first
    capture: {}
  - label: shared_b_second
    capture: {}
''',
        );
        File('${tempDirectory.path}/flows/a.yaml').writeAsStringSync('''
steps:
  - include: ../shared/capture_a.yaml
''');
        File('${tempDirectory.path}/flows/b.yaml').writeAsStringSync('''
steps:
  - include: ../shared/capture_b.yaml
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: flows/a.yaml
  - include: flows/b.yaml
''');

        final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);

        expect(scenario.steps, hasLength(4));
        expect(
          scenario.steps[0].source!.includeChain.map(
            (IncludeSource include) => include.displayPath,
          ),
          <String>['flows/a.yaml', '../shared/capture_a.yaml'],
        );
        expect(
          scenario.steps[2].source!.includeChain.map(
            (IncludeSource include) => include.displayPath,
          ),
          <String>['flows/b.yaml', '../shared/capture_b.yaml'],
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('parseFile records absolute include display paths', () {
      final Directory tempDirectory = Directory.systemTemp.createTempSync(
        'flutter_pilot_parser_absolute_source_test_',
      );
      try {
        final File libraryFile = File('${tempDirectory.path}/library.yaml')
          ..writeAsStringSync('''
steps:
  - label: absolute_source
    capture: {}
''');
        final File scenarioFile = File('${tempDirectory.path}/scenario.yaml')
          ..writeAsStringSync('''
steps:
  - include: ${libraryFile.absolute.path}
''');

        final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);

        expect(
          scenario.steps.single.source!.displayPath,
          libraryFile.absolute.path,
        );
        expect(
          scenario.steps.single.source!.includeChain.single.displayPath,
          libraryFile.absolute.path,
        );
      } finally {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('in-memory parsing omits Step Source metadata', () {
      final Scenario scenario = parseScenario('''
steps:
  - capture: {}
''');

      expect(scenario.steps.single.source, isNull);
    });
  });
}

/// Parse a Scenario YAML string and return the typed Scenario.
Scenario parseScenario(String yaml) {
  return ScenarioParser.parse(loadYaml(yaml));
}

/// Parse an invalid Scenario YAML string and return its validation paths.
List<String> invalidPaths(String yaml) {
  try {
    parseScenario(yaml);
  } on ScenarioValidationException catch (error) {
    return [
      for (final ScenarioValidationError validationError in error.errors)
        validationError.path,
    ];
  }
  fail('Expected ScenarioValidationException.');
}

/// Parse an invalid Scenario file and return its validation paths.
List<String> invalidFilePaths(String filePath) {
  return <String>[
    for (final ScenarioValidationError error in invalidFileErrors(filePath))
      error.path,
  ];
}

/// Parse an invalid Scenario file and return its validation errors.
List<ScenarioValidationError> invalidFileErrors(String filePath) {
  try {
    ScenarioParser.parseFile(filePath);
  } on ScenarioValidationException catch (error) {
    return error.errors;
  }
  fail('Expected ScenarioValidationException.');
}
