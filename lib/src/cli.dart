import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'runtime/runtime_contract.dart';
import 'scenario.dart';
import 'scenario_parser.dart';
import 'scenario_runner.dart';

/// Command-line entry point for Flutter Pilot.
///
/// It installs the first-version command surface:
/// - `validate <scenario.yaml>`
/// - `run <scenario.yaml> --target <vm-service-uri>`
///
/// Example:
/// `FlutterPilotCli().run(['validate', 'examples/login_error.yaml'])`
class FlutterPilotCli {
  /// Run the CLI with already-tokenized command-line arguments.
  ///
  /// Args:
  /// `arguments` is the argument list passed from `main`.
  ///
  /// Returns:
  /// A process exit code. Usage errors return `64`; validation errors return
  /// `1`; successful command shells return `0`.
  Future<int> run(List<String> arguments) async {
    final CommandRunner<int> runner =
        CommandRunner<int>(
            'flutter_pilot',
            'Replay Flutter UI scenarios and collect debugging artifacts.',
          )
          ..addCommand(_ValidateCommand())
          ..addCommand(_RunCommand());

    try {
      return await runner.run(arguments) ?? 0;
    } on UsageException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln();
      stderr.writeln(error.usage);
      return 64;
    }
  }
}

/// Build the first-version default runner used by the executable.
///
/// The real `mcp_flutter` adapter is not implemented yet, so the executable
/// reports a clear runtime failure after parsing succeeds. Runner success
/// behavior is covered separately through `ScenarioRunner` tests.
ScenarioRunner _createDefaultRunner(RuntimeTarget target) {
  return ScenarioRunner(
    adapter: _UnimplementedRuntimeAdapter(),
    outputDirectory: Directory.current,
  );
}

/// Placeholder adapter used until the real `mcp_flutter` adapter exists.
class _UnimplementedRuntimeAdapter implements RuntimeAdapter {
  const _UnimplementedRuntimeAdapter();

  @override
  Future<void> initialize() async {
    throw const RuntimeOperationException(
      operation: RuntimeOperation.initialize,
      message: 'mcp_flutter Runtime Adapter is not implemented yet.',
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<List<FinderMatch>> resolveFinder(Finder finder) async {
    throw _unimplemented(RuntimeOperation.resolveFinder);
  }

  @override
  Future<void> performTap(FinderMatch match) async {
    throw _unimplemented(RuntimeOperation.performTap);
  }

  @override
  Future<void> replaceText(FinderMatch match, String text) async {
    throw _unimplemented(RuntimeOperation.replaceText);
  }

  @override
  Future<void> performScroll({
    FinderMatch? match,
    required double deltaX,
    required double deltaY,
  }) async {
    throw _unimplemented(RuntimeOperation.performScroll);
  }

  @override
  Future<ScreenshotCapture> captureScreenshot() async {
    throw _unimplemented(RuntimeOperation.captureScreenshot);
  }

  @override
  Future<SnapshotCapture> captureSnapshot() async {
    throw _unimplemented(RuntimeOperation.captureSnapshot);
  }

  @override
  Future<WidgetTreeCapture> captureWidgetTree() async {
    throw _unimplemented(RuntimeOperation.captureWidgetTree);
  }

  @override
  Future<LogsCapture> collectLogs() async {
    throw _unimplemented(RuntimeOperation.collectLogs);
  }

  /// Return a normalized Runtime Adapter failure for an unsupported operation.
  RuntimeOperationException _unimplemented(RuntimeOperation operation) {
    return RuntimeOperationException(
      operation: operation,
      message: 'mcp_flutter Runtime Adapter is not implemented yet.',
    );
  }
}

/// `validate` command for checking Scenario YAML without connecting to Flutter.
///
/// It reads exactly one file path. By default it prints human-readable output;
/// with `--json` it prints a stable object containing `valid` and `errors`.
class _ValidateCommand extends Command<int> {
  _ValidateCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print machine-readable validation output.',
    );
  }

  @override
  String get description => 'Validate a scenario YAML file.';

  @override
  String get name => 'validate';

  @override
  Future<int> run() async {
    final bool jsonOutput = argResults!.flag('json');
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one scenario file.', usage);
    }

    try {
      ScenarioParser.parseFile(argResults!.rest.single);
      if (jsonOutput) {
        _writeValidationJson(valid: true, errors: const []);
      } else {
        stdout.writeln('Scenario is valid.');
      }
      return 0;
    } on ScenarioValidationException catch (error) {
      if (jsonOutput) {
        _writeValidationJson(valid: false, errors: error.errors);
      } else {
        _writeValidationErrors(error.errors);
      }
      return 1;
    }
  }

  /// Print validation status in the `validate --json` response shape.
  void _writeValidationJson({
    required bool valid,
    required List<ScenarioValidationError> errors,
  }) {
    stdout.writeln(
      jsonEncode({
        'valid': valid,
        'errors': [
          for (final ScenarioValidationError error in errors)
            {'path': error.path, 'message': error.message},
        ],
      }),
    );
  }

  /// Print validation errors as `path: message` lines for humans.
  void _writeValidationErrors(List<ScenarioValidationError> errors) {
    for (final ScenarioValidationError error in errors) {
      stderr.writeln('${error.path}: ${error.message}');
    }
  }
}

/// `run` command shell for validating CLI arguments before UI replay exists.
///
/// The first implementation checks Scenario YAML, requires `--target`, and
/// validates `--until` / `--print` relationships. It deliberately does not
/// connect to Flutter or execute MCP calls yet.
class _RunCommand extends Command<int> {
  _RunCommand() {
    argParser
      ..addOption(
        'target',
        help: 'Flutter runtime target. First version accepts VM service URI.',
      )
      ..addOption(
        'until',
        help: 'Run through a 1-based step number or step label.',
      )
      ..addOption(
        'print',
        allowed: ['snapshot', 'widget-tree', 'logs'],
        help: 'Print diagnostics after --until.',
      )
      ..addFlag(
        'html',
        negatable: false,
        help: 'Also generate an HTML timeline report.',
      );
  }

  @override
  String get description => 'Run a scenario against a Flutter runtime target.';

  @override
  String get name => 'run';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one scenario file.', usage);
    }
    final String? targetValue = argResults!.option('target');
    if (targetValue == null) {
      throw UsageException('Missing required option --target.', usage);
    }
    if (argResults!.option('print') != null &&
        argResults!.option('until') == null) {
      throw UsageException('--print must be used with --until.', usage);
    }

    final Scenario parsedScenario;
    try {
      parsedScenario = ScenarioParser.parseFile(argResults!.rest.single);
    } on ScenarioValidationException catch (error) {
      _writeValidationErrors(error.errors);
      return 1;
    }

    final String? until = argResults!.option('until');
    Scenario scenario = parsedScenario;
    if (until != null) {
      final String? error = _validateUntil(until, parsedScenario);
      if (error != null) {
        stderr.writeln(error);
        return 64;
      }
      scenario = _sliceScenarioUntil(parsedScenario, until);
    }

    final Uri? targetUri = _parseTargetUri(targetValue);
    if (targetUri == null) {
      stderr.writeln(
        '--target must be an absolute ws://, wss://, http://, or https:// VM service URI.',
      );
      return 64;
    }
    final ScenarioRunner runner = _createDefaultRunner(
      RuntimeTarget(vmServiceUri: targetUri),
    );
    try {
      final ScenarioRunReport report = await runner.run(scenario);
      return report.status == ScenarioRunStatus.passed ? 0 : 1;
    } on RuntimeOperationException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }

  /// Return the Scenario prefix selected by a validated `--until` value.
  Scenario _sliceScenarioUntil(Scenario scenario, String until) {
    final int? stepNumber = int.tryParse(until);
    if (stepNumber != null) {
      return scenario.sliceThroughStepNumber(stepNumber);
    }
    return scenario.sliceThroughStepLabel(until);
  }

  /// Parse and validate the first-version Runtime Target URI.
  ///
  /// Args:
  /// `targetValue` is the raw `--target` argument.
  ///
  /// Returns:
  /// An absolute VM service URI when valid, otherwise `null`.
  Uri? _parseTargetUri(String targetValue) {
    final Uri uri;
    try {
      uri = Uri.parse(targetValue);
    } on FormatException {
      return null;
    }
    final Set<String> allowedSchemes = <String>{'ws', 'wss', 'http', 'https'};
    if (!uri.hasScheme || !allowedSchemes.contains(uri.scheme)) {
      return null;
    }
    if (uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  /// Validate that `--until` names an existing stop point in the Scenario.
  ///
  /// Args:
  /// `until` is either a 1-based step number or a step label.
  /// `scenario` provides the step count and available labels.
  ///
  /// Returns:
  /// `null` when valid, otherwise a human-readable CLI usage error.
  String? _validateUntil(String until, Scenario scenario) {
    final int? stepNumber = int.tryParse(until);
    if (stepNumber != null) {
      if (stepNumber < 1 || stepNumber > scenario.steps.length) {
        return '--until step number must be between 1 and ${scenario.steps.length}.';
      }
      return null;
    }

    final Iterable<String> labels = scenario.steps
        .map((ScenarioStep step) => step.label)
        .whereType<String>();
    if (!labels.contains(until)) {
      return '--until must be a 1-based step number or an existing step label.';
    }
    return null;
  }

  /// Print validation errors as `path: message` lines for humans.
  void _writeValidationErrors(List<ScenarioValidationError> errors) {
    for (final ScenarioValidationError error in errors) {
      stderr.writeln('${error.path}: ${error.message}');
    }
  }
}
