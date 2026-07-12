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
/// It accepts the Scenario schema:
/// - top-level `scenario` metadata and required `steps`
/// - Step Includes that reference Step Library files
/// - optional `scenario.recording` metadata
/// - one action per step
/// - Finder fields `byText`, `byType`, `byKey`, and `byWidget`
///
/// Example:
/// `ScenarioParser.parseFile('examples/login_error.yaml')` returns a
/// `Scenario` or throws `ScenarioValidationException`.
class ScenarioParser {
  ScenarioParser._();

  static final RegExp _slugPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$');
  static const _actionKeys = {'tap', 'type', 'scroll', 'waitFor', 'capture'};
  static const _finderKeys = {'byText', 'byType', 'byKey', 'byWidget'};

  /// Read a Scenario YAML file and return the parsed Scenario.
  ///
  /// Args:
  /// `filePath` is the path to a YAML file. When `scenario.name` is omitted,
  /// the file basename becomes the Scenario name.
  ///
  /// Step Includes in the Steps list are expanded: each `include:` entry loads
  /// the referenced Step Library file and inlines its Steps. Include paths are
  /// resolved relative to the file that contains the include. Include cycles
  /// are detected and produce a validation error.
  ///
  /// Returns:
  /// A typed `Scenario` whose steps contain concrete `StepAction` subclasses.
  ///
  /// Throws:
  /// `ScenarioValidationException` when the file is missing, the YAML cannot be
  /// parsed, include expansion fails, or the schema contains invalid fields.
  static Scenario parseFile(String filePath) {
    final File file = File(filePath);
    if (!file.existsSync()) {
      throw ScenarioValidationException([
        ScenarioValidationError(filePath, 'Scenario file does not exist.'),
      ]);
    }

    final List<ScenarioValidationError> errors = <ScenarioValidationError>[];
    final _ParsedYamlFile? parsedFile = _readYamlFile(
      file,
      r'$',
      p.normalize(filePath),
      errors,
    );
    if (parsedFile == null) {
      throw ScenarioValidationException(errors);
    }

    final String identity = _fileIdentity(file);
    final String entryDisplayPath = p.normalize(filePath);
    final Scenario scenario = _parseDocument(
      parsedFile.yaml,
      fallbackName: p.basenameWithoutExtension(filePath),
      sourceFile: file,
      fileIdentity: identity,
      displayPath: entryDisplayPath,
      documentPath: r'$',
      library: false,
      includeStack: <String>[identity],
      includeChain: const <IncludeSource>[],
      labels: null,
      errors: errors,
    );
    if (errors.isNotEmpty) {
      throw ScenarioValidationException(errors);
    }
    return scenario;
  }

  /// Convert a decoded YAML value into a typed Scenario.
  ///
  /// Args:
  /// `yaml` is the value returned by `loadYaml`. It must be a YAML map.
  /// `fallbackName` is used when `scenario.name` is absent or empty.
  ///
  /// Step Includes are rejected in in-memory mode (see `parseFile` for
  /// file-level parsing with include expansion).
  ///
  /// Returns:
  /// A `Scenario` with validated metadata, labels, Finders, and actions.
  ///
  /// Throws:
  /// `ScenarioValidationException` containing all schema errors found while
  /// walking the YAML tree.
  static Scenario parse(Object? yaml, {String fallbackName = 'scenario'}) {
    final List<ScenarioValidationError> errors = <ScenarioValidationError>[];
    final Scenario scenario = _parseDocument(
      yaml,
      fallbackName: fallbackName,
      sourceFile: null,
      fileIdentity: null,
      displayPath: null,
      documentPath: r'$',
      library: false,
      includeStack: const <String>[],
      includeChain: const <IncludeSource>[],
      labels: null,
      errors: errors,
    );
    if (errors.isNotEmpty) {
      throw ScenarioValidationException(errors);
    }
    return scenario;
  }

  /// Convert one YAML document into a Scenario and expand file includes.
  ///
  /// Args:
  /// `yaml` is the decoded YAML document.
  /// `fallbackName` is used for Entry Scenario files without `scenario.name`.
  /// `sourceFile` is the file that owns relative include resolution. When
  /// absent, Step Includes are rejected instead of using the process directory.
  /// `library` controls whether top-level Scenario metadata is allowed.
  /// `includeStack` contains canonical file identities already being expanded.
  /// `errors` receives schema, file, include, and YAML parse failures.
  ///
  /// Returns:
  /// A Scenario with expanded and re-indexed Steps. The returned object is only
  /// safe to use when `errors` is empty.
  static Scenario _parseDocument(
    Object? yaml, {
    required String fallbackName,
    required File? sourceFile,
    required String? fileIdentity,
    required String? displayPath,
    required String documentPath,
    required bool library,
    required List<String> includeStack,
    required List<IncludeSource> includeChain,
    required Set<String>? labels,
    required List<ScenarioValidationError> errors,
  }) {
    if (yaml is! YamlMap) {
      errors.add(ScenarioValidationError(documentPath, 'Expected a YAML map.'));
      return Scenario(name: fallbackName, steps: const <ScenarioStep>[]);
    }

    _rejectUnknownKeys(
      documentPath,
      yaml,
      library ? {'steps'} : {'scenario', 'steps'},
      errors,
    );
    if (library && yaml.containsKey('scenario')) {
      errors.add(
        ScenarioValidationError(
          _joinPath(documentPath, 'scenario'),
          'Step Libraries cannot define scenario metadata.',
        ),
      );
    }

    String scenarioName = fallbackName.isEmpty ? 'scenario' : fallbackName;
    String? description;
    ScenarioRecording? recording;
    final Object? scenarioYaml = yaml['scenario'];
    final String scenarioPath = _joinPath(documentPath, 'scenario');
    if (!library && scenarioYaml != null) {
      if (scenarioYaml is! YamlMap) {
        errors.add(ScenarioValidationError(scenarioPath, 'Expected a map.'));
      } else {
        _rejectUnknownKeys(scenarioPath, scenarioYaml, {
          'name',
          'description',
          'recording',
        }, errors);
        final Object? name = scenarioYaml['name'];
        if (name != null) {
          if (name is String) {
            scenarioName = name;
            _validateSlug(_joinPath(scenarioPath, 'name'), name, errors);
          } else {
            errors.add(
              ScenarioValidationError(
                _joinPath(scenarioPath, 'name'),
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
              ScenarioValidationError(
                _joinPath(scenarioPath, 'description'),
                'Expected a string.',
              ),
            );
          }
        }
        if (scenarioYaml.containsKey('recording')) {
          recording = _parseRecording(
            scenarioYaml['recording'],
            'scenario.recording',
            errors,
          );
        }
      }
    }

    final Object? rawSteps = yaml['steps'];
    final List<ScenarioStep> steps = <ScenarioStep>[];
    final String stepsPath = _joinPath(documentPath, 'steps');
    if (rawSteps is! YamlList) {
      errors.add(ScenarioValidationError(stepsPath, 'Expected a list.'));
    } else if (rawSteps.isEmpty) {
      errors.add(
        ScenarioValidationError(stepsPath, 'Expected at least one step.'),
      );
    } else {
      final Set<String> documentLabels = labels ?? <String>{};
      _parseSteps(
        rawSteps,
        path: stepsPath,
        sourcePath: 'steps',
        sourceFile: sourceFile,
        fileIdentity: fileIdentity,
        displayPath: displayPath,
        includeStack: includeStack,
        includeChain: includeChain,
        labels: documentLabels,
        steps: steps,
        errors: errors,
      );
    }

    return Scenario(
      name: scenarioName,
      description: description,
      recording: recording,
      steps: _reindexSteps(steps),
    );
  }

  /// Parse a Step list and expand any Step Includes found in list order.
  static void _parseSteps(
    YamlList rawSteps, {
    required String path,
    required String sourcePath,
    required File? sourceFile,
    required String? fileIdentity,
    required String? displayPath,
    required List<String> includeStack,
    required List<IncludeSource> includeChain,
    required Set<String> labels,
    required List<ScenarioStep> steps,
    required List<ScenarioValidationError> errors,
  }) {
    for (int i = 0; i < rawSteps.length; i++) {
      final String stepPath = '$path[$i]';
      final String sourceStepPath = '$sourcePath[$i]';
      final Object? rawStep = rawSteps[i];
      if (_isIncludeEntry(rawStep)) {
        _parseInclude(
          rawStep as YamlMap,
          stepPath,
          sourceFile: sourceFile,
          fileIdentity: fileIdentity,
          displayPath: displayPath,
          includeStack: includeStack,
          includeChain: includeChain,
          labels: labels,
          steps: steps,
          errors: errors,
        );
        continue;
      }
      final ScenarioStep? step = _parseStep(
        rawStep,
        stepPath,
        steps.length,
        source: _stepSource(
          fileIdentity: fileIdentity,
          displayPath: displayPath,
          yamlPath: sourceStepPath,
          includeChain: includeChain,
        ),
        labels: labels,
        errors: errors,
      );
      if (step != null) {
        steps.add(step);
      }
    }
  }

  /// Return whether a raw Step list item uses the Step Include shape.
  static bool _isIncludeEntry(Object? yaml) {
    return yaml is YamlMap && yaml.containsKey('include');
  }

  /// Parse one Step Include and append the referenced library Steps.
  static void _parseInclude(
    YamlMap yaml,
    String path, {
    required File? sourceFile,
    required String? fileIdentity,
    required String? displayPath,
    required List<String> includeStack,
    required List<IncludeSource> includeChain,
    required Set<String> labels,
    required List<ScenarioStep> steps,
    required List<ScenarioValidationError> errors,
  }) {
    _rejectUnknownKeys(path, yaml, {'include'}, errors);
    final Object? rawIncludePath = yaml['include'];
    if (rawIncludePath is! String) {
      errors.add(
        ScenarioValidationError('$path.include', 'Expected a string.'),
      );
      return;
    }
    if (yaml.length != 1) {
      return;
    }
    if (sourceFile == null) {
      errors.add(
        ScenarioValidationError(
          '$path.include',
          'Step Includes require file context from parseFile(...).',
        ),
      );
      return;
    }

    final File includeFile = _resolveIncludeFile(sourceFile, rawIncludePath);
    final String includeDisplayPath = rawIncludePath;
    final String includeErrorPath = '$path.include';
    if (!includeFile.existsSync()) {
      errors.add(
        ScenarioValidationError(
          includeErrorPath,
          'Included Step Library does not exist: $includeDisplayPath',
        ),
      );
      return;
    }

    final String includeIdentity = _fileIdentity(includeFile);
    if (includeStack.contains(includeIdentity)) {
      errors.add(
        ScenarioValidationError(
          includeErrorPath,
          'Step Include cycle detected: $includeDisplayPath',
        ),
      );
      return;
    }

    final _ParsedYamlFile? parsedFile = _readYamlFile(
      includeFile,
      includeErrorPath,
      includeDisplayPath,
      errors,
    );
    if (parsedFile == null) {
      return;
    }
    final Scenario libraryScenario = _parseDocument(
      parsedFile.yaml,
      fallbackName: p.basenameWithoutExtension(includeFile.path),
      sourceFile: includeFile,
      fileIdentity: includeIdentity,
      displayPath: includeDisplayPath,
      documentPath: includeErrorPath,
      library: true,
      includeStack: <String>[...includeStack, includeIdentity],
      includeChain: <IncludeSource>[
        ...includeChain,
        IncludeSource(
          fileIdentity: includeIdentity,
          displayPath: includeDisplayPath,
          includePath: includeErrorPath,
        ),
      ],
      labels: labels,
      errors: errors,
    );
    steps.addAll(libraryScenario.steps);
  }

  /// Append a YAML field name to an existing validation path.
  static String _joinPath(String path, String field) {
    return path == r'$' ? field : '$path.$field';
  }

  /// Parse Scenario Recording metadata and apply default enablement.
  ///
  /// Args:
  /// `yaml` is the raw value under `scenario.recording`.
  /// `path` is the validation path used for recording schema errors.
  /// `errors` receives invalid recording field errors.
  ///
  /// Returns:
  /// `ScenarioRecording(enabled: true)` for `{}` or explicit `enabled: true`,
  /// `ScenarioRecording(enabled: false)` for explicit disablement, and `null`
  /// when the recording value is structurally invalid.
  static ScenarioRecording? _parseRecording(
    Object? yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    if (yaml is! YamlMap) {
      errors.add(ScenarioValidationError(path, 'Expected a map.'));
      return null;
    }

    _rejectUnknownKeys(path, yaml, {'enabled'}, errors);
    final bool enabled =
        _optionalBool(yaml, 'enabled', '$path.enabled', errors) ?? true;
    return ScenarioRecording(enabled: enabled);
  }

  /// Parse one step and enforce the "label plus exactly one action" rule.
  ///
  /// Args:
  /// `yaml` is the raw YAML item from the `steps` list.
  /// `path` is the YAML list path used in validation messages.
  /// `index` is the zero-based expanded Step index used until final reindexing.
  /// `labels` contains labels already seen so duplicates can be rejected.
  /// `errors` receives schema errors found in this step.
  ///
  /// Returns:
  /// A `ScenarioStep` when the action can be parsed, or `null` when this step
  /// is structurally invalid.
  static ScenarioStep? _parseStep(
    Object? yaml,
    String path,
    int index, {
    required StepSource? source,
    required Set<String> labels,
    required List<ScenarioValidationError> errors,
  }) {
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
    return ScenarioStep(
      index: index + 1,
      label: label,
      source: source,
      action: action,
    );
  }

  /// Return Step Source metadata when parsing has file context.
  static StepSource? _stepSource({
    required String? fileIdentity,
    required String? displayPath,
    required String yamlPath,
    required List<IncludeSource> includeChain,
  }) {
    if (fileIdentity == null || displayPath == null) {
      return null;
    }
    return StepSource(
      fileIdentity: fileIdentity,
      displayPath: displayPath,
      yamlPath: yamlPath,
      includeChain: List<IncludeSource>.unmodifiable(includeChain),
    );
  }

  /// Return Steps with contiguous 1-based indexes after include expansion.
  static List<ScenarioStep> _reindexSteps(List<ScenarioStep> steps) {
    return <ScenarioStep>[
      for (int i = 0; i < steps.length; i++)
        ScenarioStep(
          index: i + 1,
          label: steps[i].label,
          source: steps[i].source,
          action: steps[i].action,
        ),
    ];
  }

  /// Read one YAML file and convert syntax errors into validation errors.
  static _ParsedYamlFile? _readYamlFile(
    File file,
    String path,
    String displayPath,
    List<ScenarioValidationError> errors,
  ) {
    try {
      return _ParsedYamlFile(loadYaml(file.readAsStringSync()));
    } on YamlException catch (error) {
      errors.add(
        ScenarioValidationError(
          path,
          'Invalid YAML in $displayPath: ${error.message}',
        ),
      );
    } on FormatException catch (error) {
      errors.add(
        ScenarioValidationError(
          path,
          'Invalid YAML in $displayPath: ${error.message}',
        ),
      );
    } on FileSystemException catch (error) {
      errors.add(
        ScenarioValidationError(
          path,
          'Cannot read $displayPath: ${error.message}',
        ),
      );
    }
    return null;
  }

  /// Resolve an include path against the file that contains it.
  static File _resolveIncludeFile(File sourceFile, String includePath) {
    if (p.isAbsolute(includePath)) {
      return File(includePath);
    }
    return File(p.normalize(p.join(sourceFile.parent.path, includePath)));
  }

  /// Return a canonical file identity for cycle detection when available.
  static String _fileIdentity(File file) {
    try {
      return file.resolveSymbolicLinksSync();
    } on FileSystemException {
      return p.normalize(file.absolute.path);
    }
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
  /// A Finder is optional. Without a Finder, the runner selects the unique
  /// outermost visible scrollable on the dominant drag axis. At least one of
  /// `deltaX` or `deltaY` must be non-zero.
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
    final double deltaX =
        _optionalDouble(yaml, 'deltaX', '$path.deltaX', errors) ?? 0;
    final double deltaY =
        _optionalDouble(yaml, 'deltaY', '$path.deltaY', errors) ?? 0;
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

  /// Parse a capture action and apply the Widget Tree diagnostic defaults.
  static CaptureAction _parseCapture(
    YamlMap yaml,
    String path,
    List<ScenarioValidationError> errors,
  ) {
    const keys = {'screenshot', 'widgetTree', 'logs'};
    _rejectUnknownKeys(path, yaml, keys, errors);
    return CaptureAction(
      screenshot:
          _optionalBool(yaml, 'screenshot', '$path.screenshot', errors) ?? true,
      snapshot: false,
      widgetTree:
          _optionalBool(yaml, 'widgetTree', '$path.widgetTree', errors) ?? true,
      logs: _optionalBool(yaml, 'logs', '$path.logs', errors) ?? true,
    );
  }

  /// Parse Finder fields from an action map.
  ///
  /// Args:
  /// `yaml` is the action map that may contain Finder fields.
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
    String? byType;
    String? byKey;
    String? byWidget;
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
        case 'byType':
          byType = value;
        case 'byKey':
          byKey = value;
        case 'byWidget':
          byWidget = value;
      }
    }

    final Finder finder = Finder(
      byText: byText,
      byType: byType,
      byKey: byKey,
      byWidget: byWidget,
    );
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
  static double? _optionalDouble(
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
      return value.toDouble();
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

/// Decoded YAML document read from one Scenario or Step Library file.
class _ParsedYamlFile {
  const _ParsedYamlFile(this.yaml);

  final Object? yaml;
}
