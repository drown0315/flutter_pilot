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
      byText: 登录
      byType: TextButton
  - label: wait_for_error
    waitFor:
      byText: 密码错误
  - label: capture_error
    capture: {}
''');

      expect(scenario.name, 'login_error');
      expect(scenario.description, 'Reproduces the login validation error');
      expect(scenario.steps, hasLength(3));

      final TapAction tap = scenario.steps[0].action as TapAction;
      expect(tap.finder.byText, '登录');
      expect(tap.finder.byType, 'TextButton');

      final WaitForAction waitFor = scenario.steps[1].action as WaitForAction;
      expect(waitFor.timeoutMs, 3000);

      final CaptureAction capture = scenario.steps[2].action as CaptureAction;
      expect(capture.screenshot, isTrue);
      expect(capture.snapshot, isTrue);
      expect(capture.widgetTree, isFalse);
      expect(capture.logs, isTrue);
    });

    test('reports unknown fields with field paths', () {
      final List<String> paths = invalidPaths('''
scenario:
  name: login_error
extra: no
steps:
  - label: submit_login
    tap:
      byText: 登录
      unknown: no
''');

      expect(paths, containsAll([r'$.extra', 'steps[0].tap.unknown']));
    });

    test('rejects invalid Finder value types', () {
      final List<String> paths = invalidPaths('''
steps:
  - tap:
      byText:
        - 登录
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
      byKey: email_input
      text: bad@example.com
  - scroll:
      byType: ListView
      deltaY: -500
''');

      final TypeAction type = scenario.steps[0].action as TypeAction;
      expect(type.finder.byKey, 'email_input');
      expect(type.text, 'bad@example.com');

      final ScrollAction scroll = scenario.steps[1].action as ScrollAction;
      expect(scroll.finder!.byType, 'ListView');
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
