import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'scenario.dart';

/// One schema or YAML parsing problem found while reading a Scenario file.
///
/// It contains:
/// - `path`: the YAML field path, such as `steps[0].tap.byText`
/// - `message`: the reason that field cannot be accepted
///
/// Example:
/// `ScenarioValidationError('steps[0].tap.byText', 'Expected a string.')`
class ScenarioValidationError {
  const ScenarioValidationError(this.path, this.message);

  final String path;
  final String message;
}

/// Exception thrown when a YAML file cannot be converted into a Scenario.
///
/// It contains every schema-level error the parser can collect from the input.
/// YAML syntax errors and unreadable files usually produce a single error
/// because parsing cannot safely continue.
///
/// Example:
/// A step with both `tap` and `waitFor` throws this exception with an error at
/// `steps[0]` explaining that a step must contain exactly one action.
class ScenarioValidationException implements Exception {
  const ScenarioValidationException(this.errors);

  final List<ScenarioValidationError> errors;
}

/// Parser that converts strict Scenario YAML into typed Scenario objects.
///
/// It accepts the first-version Scenario schema:
/// - top-level `scenario` metadata and required `steps`
/// - one action per step
/// - Finder fields `byText`, `byKey`, and `byType`
///
/// Example:
/// `ScenarioParser.parseFile('examples/login_error.yaml')` returns a
/// `Scenario` or throws `ScenarioValidationException`.
class ScenarioParser {
  ScenarioParser._();

  static final RegExp _slugPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$');
  static const _actionKeys = {'tap', 'type', 'scroll', 'waitFor', 'capture'};
  static const _finderKeys = {'byText', 'byKey', 'byType'};

  /// Read a Scenario YAML file and return the parsed Scenario.
  ///
  /// Args:
  /// `filePath` is the path to a YAML file. When `scenario.name` is omitted,
  /// the file basename becomes the Scenario name.
  ///
  /// Returns:
  /// A typed `Scenario` whose steps contain concrete `StepAction` subclasses.
  ///
  /// Throws:
  /// `ScenarioValidationException` when the file is missing, the YAML cannot be
  /// parsed, or the schema contains invalid fields.
  static Scenario parseFile(String filePath) {
    final File file = File(filePath);
    if (!file.existsSync()) {
      throw ScenarioValidationException([
        ScenarioValidationError(filePath, 'Scenario file does not exist.'),
      ]);
    }

    try {
      final Object? yaml = loadYaml(file.readAsStringSync());
      return parse(yaml, fallbackName: p.basenameWithoutExtension(filePath));
    } on YamlException catch (error) {
      throw ScenarioValidationException([
        ScenarioValidationError(r'$', error.message),
      ]);
    } on FormatException catch (error) {
      throw ScenarioValidationException([
        ScenarioValidationError(r'$', error.message),
      ]);
    }
  }

  /// Convert a decoded YAML value into a typed Scenario.
  ///
  /// Args:
  /// `yaml` is the value returned by `loadYaml`. It must be a YAML map.
  /// `fallbackName` is used when `scenario.name` is absent or empty.
  ///
  /// Returns:
  /// A `Scenario` with validated metadata, labels, Finders, and actions.
  ///
  /// Throws:
  /// `ScenarioValidationException` containing all schema errors found while
  /// walking the YAML tree.
  static Scenario parse(Object? yaml, {String fallbackName = 'scenario'}) {
    final List<ScenarioValidationError> errors = <ScenarioValidationError>[];
    if (yaml is! YamlMap) {
      throw const ScenarioValidationException([
        ScenarioValidationError(r'$', 'Expected a YAML map.'),
      ]);
    }

    _rejectUnknownKeys(r'$', yaml, {'scenario', 'steps'}, errors);

    String scenarioName = fallbackName.isEmpty ? 'scenario' : fallbackName;
    String? description;
    final Object? scenarioYaml = yaml['scenario'];
    if (scenarioYaml != null) {
      if (scenarioYaml is! YamlMap) {
        errors.add(
          const ScenarioValidationError('scenario', 'Expected a map.'),
        );
      } else {
        _rejectUnknownKeys('scenario', scenarioYaml, {
          'name',
          'description',
        }, errors);
        final Object? name = scenarioYaml['name'];
        if (name != null) {
          if (name is String) {
            scenarioName = name;
            _validateSlug('scenario.name', name, errors);
          } else {
            errors.add(
              const ScenarioValidationError(
                'scenario.name',
                'Expected a string.',
              ),
            );
          }
        }
        final Object? rawDescription = scenarioYaml['description'];
        if (rawDescription != null) {
          if (rawDescription is String) {
            description = rawDescription;
          } else {
            errors.add(
              const ScenarioValidationError(
                'scenario.description',
                'Expected a string.',
              ),
            );
          }
        }
      }
    }

    final Object? rawSteps = yaml['steps'];
    final List<ScenarioStep> steps = <ScenarioStep>[];
    if (rawSteps is! YamlList) {
      errors.add(const ScenarioValidationError('steps', 'Expected a list.'));
    } else if (rawSteps.isEmpty) {
      errors.add(
        const ScenarioValidationError('steps', 'Expected at least one step.'),
      );
    } else {
      final Set<String> labels = <String>{};
      for (int i = 0; i < rawSteps.length; i++) {
        final ScenarioStep? step = _parseStep(rawSteps[i], i, labels, errors);
        if (step != null) {
          steps.add(step);
        }
      }
    }

    if (errors.isNotEmpty) {
      throw ScenarioValidationException(errors);
    }
    return Scenario(name: scenarioName, description: description, steps: steps);
  }

  /// Parse one step and enforce the "label plus exactly one action" rule.
  ///
  /// Args:
  /// `yaml` is the raw YAML item from the `steps` list.
  /// `index` is the zero-based YAML list index used in validation paths.
  /// `labels` contains labels already seen so duplicates can be rejected.
  /// `errors` receives schema errors found in this step.
  ///
  /// Returns:
  /// A `ScenarioStep` when the action can be parsed, or `null` when this step
  /// is structurally invalid.
  static ScenarioStep? _parseStep(
    Object? yaml,
    int index,
    Set<String> labels,
    List<ScenarioValidationError> errors,
  ) {
    final String path = 'steps[$index]';
    if (yaml is! YamlMap) {
      errors.add(ScenarioValidationError(path, 'Expected a map.'));
      return null;
    }

    _rejectUnknownKeys(path, yaml, {'label', ..._actionKeys}, errors);
    final List<String> actions = [
      for (final String key in _actionKeys)
        if (yaml.containsKey(key)) key,
    ];
    if (actions.length != 1) {
      errors.add(ScenarioValidationError(path, 'Expected exactly one action.'));
      return null;
    }

    String? label;
    if (yaml.containsKey('label')) {
      final Object? rawLabel = yaml['label'];
      if (rawLabel is String) {
        label = rawLabel;
        _validateSlug('$path.label', rawLabel, errors);
        if (!labels.add(rawLabel)) {
          errors.add(
            ScenarioValidationError(
              '$path.label',
              'Step label must be unique.',
            ),
          );
        }
      } else {
        errors.add(
          ScenarioValidationError('$path.label', 'Expected a string.'),
        );
      }
    }

    final String actionKey = actions.single;
    final StepAction? action = _parseAction(
      actionKey,
      yaml[actionKey],
      '$path.$actionKey',
      errors,
    );
    if (action == null) {
      return null;
    }
    return ScenarioStep(index: index + 1, label: label, action: action);
  }

  /// Dispatch one action map to the parser for its concrete action type.
  ///
  /// Args:
  /// `actionKey` is one of `tap`, `type`, `scroll`, `waitFor`, or `capture`.
  /// `yaml` is the map under that action key.
  /// `path` is the YAML field path used in validation errors.
  /// `errors` receives schema errors found inside the action.
  ///
  /// Returns:
  /// A concrete `StepAction`, or `null` when the action map is missing or
  /// malformed.
  static StepAction? _parseAction(
    String actionKey,
    Object? yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    if (yaml is! YamlMap) {
      errors.add(ScenarioValidationError(path, 'Expected a map.'));
      return null;
    }

    return switch (actionKey) {
      'tap' => _parseTap(yaml, path, errors),
      'type' => _parseType(yaml, path, errors),
      'scroll' => _parseScroll(yaml, path, errors),
      'waitFor' => _parseWaitFor(yaml, path, errors),
      'capture' => _parseCapture(yaml, path, errors),
      _ => null,
    };
  }

  /// Parse a tap action that must include at least one Finder field.
  static TapAction? _parseTap(
    YamlMap yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    _rejectUnknownKeys(path, yaml, _finderKeys, errors);
    final Finder? finder = _parseFinder(
      yaml,
      path,
      required: true,
      errors: errors,
    );
    return finder == null ? null : TapAction(finder: finder);
  }

  /// Parse a type action that clears and enters the provided `text`.
  static TypeAction? _parseType(
    YamlMap yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    _rejectUnknownKeys(path, yaml, {..._finderKeys, 'text'}, errors);
    final Finder? finder = _parseFinder(
      yaml,
      path,
      required: true,
      errors: errors,
    );
    final Object? text = yaml['text'];
    if (text is! String) {
      errors.add(ScenarioValidationError('$path.text', 'Expected a string.'));
      return null;
    }
    return finder == null ? null : TypeAction(finder: finder, text: text);
  }

  /// Parse a scroll action using gesture drag deltas.
  ///
  /// A Finder is optional. Without a Finder, the future runner should target
  /// the primary scrollable. At least one of `deltaX` or `deltaY` must be
  /// non-zero.
  static ScrollAction? _parseScroll(
    YamlMap yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    _rejectUnknownKeys(path, yaml, {
      ..._finderKeys,
      'deltaX',
      'deltaY',
    }, errors);
    final Finder? finder = _parseFinder(
      yaml,
      path,
      required: false,
      errors: errors,
    );
    final num deltaX =
        _optionalNumber(yaml, 'deltaX', '$path.deltaX', errors) ?? 0;
    final num deltaY =
        _optionalNumber(yaml, 'deltaY', '$path.deltaY', errors) ?? 0;
    if (deltaX == 0 && deltaY == 0) {
      errors.add(
        ScenarioValidationError(
          path,
          'Expected deltaX or deltaY to be non-zero.',
        ),
      );
      return null;
    }
    return ScrollAction(finder: finder, deltaX: deltaX, deltaY: deltaY);
  }

  /// Parse a waitFor action that waits for one unique Finder match.
  static WaitForAction? _parseWaitFor(
    YamlMap yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    _rejectUnknownKeys(path, yaml, {..._finderKeys, 'timeoutMs'}, errors);
    final Finder? finder = _parseFinder(
      yaml,
      path,
      required: true,
      errors: errors,
    );
    final int timeoutMs =
        _optionalInt(yaml, 'timeoutMs', '$path.timeoutMs', errors) ?? 3000;
    return finder == null
        ? null
        : WaitForAction(finder: finder, timeoutMs: timeoutMs);
  }

  /// Parse a capture action and apply the first-version diagnostic defaults.
  static CaptureAction _parseCapture(
    YamlMap yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    const keys = {'screenshot', 'snapshot', 'widgetTree', 'errors', 'logs'};
    _rejectUnknownKeys(path, yaml, keys, errors);
    return CaptureAction(
      screenshot:
          _optionalBool(yaml, 'screenshot', '$path.screenshot', errors) ?? true,
      snapshot:
          _optionalBool(yaml, 'snapshot', '$path.snapshot', errors) ?? true,
      widgetTree:
          _optionalBool(yaml, 'widgetTree', '$path.widgetTree', errors) ??
          false,
      errors: _optionalBool(yaml, 'errors', '$path.errors', errors) ?? true,
      logs: _optionalBool(yaml, 'logs', '$path.logs', errors) ?? true,
    );
  }

  /// Parse Finder fields from an action map.
  ///
  /// Args:
  /// `yaml` is the action map that may contain `byText`, `byKey`, and `byType`.
  /// `path` is the action path used when reporting invalid Finder fields.
  /// `required` controls whether an empty Finder is accepted. `scroll` passes
  /// `false`; `tap`, `type`, and `waitFor` pass `true`.
  /// `errors` receives invalid field type or missing-Finder errors.
  ///
  /// Returns:
  /// A Finder with all configured `by*` fields, or `null` when no Finder fields
  /// were present and the action allows an omitted Finder.
  static Finder? _parseFinder(
    YamlMap yaml,
    String path, {
    required bool required,
    required List<ScenarioValidationError> errors,
  }) {
    String? byText;
    String? byKey;
    String? byType;
    for (final String key in _finderKeys) {
      if (!yaml.containsKey(key)) {
        continue;
      }
      final Object? value = yaml[key];
      if (value is! String) {
        errors.add(ScenarioValidationError('$path.$key', 'Expected a string.'));
        continue;
      }
      switch (key) {
        case 'byText':
          byText = value;
        case 'byKey':
          byKey = value;
        case 'byType':
          byType = value;
      }
    }

    final Finder finder = Finder(byText: byText, byKey: byKey, byType: byType);
    if (required && finder.isEmpty) {
      errors.add(
        ScenarioValidationError(path, 'Expected at least one Finder.'),
      );
      return null;
    }
    return finder.isEmpty ? null : finder;
  }

  /// Add validation errors for every key that is not allowed at this path.
  static void _rejectUnknownKeys(
    String path,
    YamlMap yaml,
    Set<String> allowed,
    List<ScenarioValidationError> errors,
  ) {
    for (final Object? key in yaml.keys) {
      if (key is! String || !allowed.contains(key)) {
        errors.add(
          ScenarioValidationError(
            key is String ? '$path.$key' : path,
            'Unknown field.',
          ),
        );
      }
    }
  }

  /// Validate the slug rule used by Scenario names and step labels.
  static void _validateSlug(
    String path,
    String value,
    List<ScenarioValidationError> errors,
  ) {
    if (!_slugPattern.hasMatch(value)) {
      errors.add(
        ScenarioValidationError(
          path,
          'Expected /^[a-zA-Z0-9][a-zA-Z0-9_-]*\$/.',
        ),
      );
    }
  }

  /// Return an optional numeric YAML field or record a type error.
  static num? _optionalNumber(
    YamlMap yaml,
    String key,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    if (!yaml.containsKey(key)) {
      return null;
    }
    final Object? value = yaml[key];
    if (value is num) {
      return value;
    }
    errors.add(ScenarioValidationError(path, 'Expected a number.'));
    return null;
  }

  /// Return an optional integer YAML field or record a type error.
  static int? _optionalInt(
    YamlMap yaml,
    String key,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    if (!yaml.containsKey(key)) {
      return null;
    }
    final Object? value = yaml[key];
    if (value is int) {
      return value;
    }
    errors.add(ScenarioValidationError(path, 'Expected an integer.'));
    return null;
  }

  /// Return an optional boolean YAML field or record a type error.
  static bool? _optionalBool(
    YamlMap yaml,
    String key,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    if (!yaml.containsKey(key)) {
      return null;
    }
    final Object? value = yaml[key];
    if (value is bool) {
      return value;
    }
    errors.add(ScenarioValidationError(path, 'Expected a boolean.'));
    return null;
  }
}
