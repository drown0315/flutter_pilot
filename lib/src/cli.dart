import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'app_setup.dart';
import 'diagnostic_text_renderer.dart';
import 'html_timeline_report.dart';
import 'runtime/fake_runtime_adapter.dart';
import 'runtime/mcp_flutter_runtime_adapter.dart';
import 'runtime/runtime_contract.dart';
import 'run_diff.dart';
import 'scenario.dart';
import 'scenario_parser.dart';
import 'scenario_runner.dart';
import 'step_progress_renderer.dart';

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
          ..addCommand(_RunCommand())
          ..addCommand(_ReportCommand())
          ..addCommand(_DiffCommand())
          ..addCommand(_DoctorCommand())
          ..addCommand(_InitCommand());

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

/// `doctor` command for checking Flutter Pilot setup in a Target App Package.
///
/// It inspects the current working directory without modifying files. Missing
/// setup is reported as diagnostic output, while unreadable or unsupported
/// package shapes return an execution failure.
class _DoctorCommand extends Command<int> {
  @override
  String get description => 'Check Flutter Pilot setup in a Flutter package.';

  @override
  String get name => 'doctor';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException('Expected no arguments.', usage);
    }
    try {
      final AppSetupStatus status = AppSetupChecker.check(Directory.current);
      if (!status.isFlutterPackage) {
        stderr.writeln(_flutterPackageOnlyMessage);
        return 1;
      }
      stdout.writeln('Flutter Pilot doctor');
      stdout.writeln('');
      if (status.isComplete) {
        stdout.writeln('✅ Flutter Pilot app setup is complete.');
      } else {
        if (!status.hasMcpToolkitDependency) {
          stdout.writeln(
            '❌ MCP Toolkit dependency missing: run `flutter pub add mcp_toolkit`',
          );
        }
        if (!status.hasBootstrapFlutter) {
          _writeBootstrapGuidance();
        }
      }
      return 0;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } on YamlException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}

/// `init` command for adding safe Flutter Pilot setup to a Target App Package.
///
/// It can add the `mcp_toolkit` dependency through Flutter tooling, then
/// reports whether the app entrypoint still needs manual bootstrap code.
class _InitCommand extends Command<int> {
  @override
  String get description =>
      'Initialize Flutter Pilot setup in a Flutter package.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException('Expected no arguments.', usage);
    }
    try {
      final AppSetupStatus status = AppSetupChecker.check(Directory.current);
      if (!status.isFlutterPackage) {
        stderr.writeln(_flutterPackageOnlyMessage);
        return 1;
      }
      final AppSetupInitResult result = await AppSetupInitializer.initialize(
        Directory.current,
        addMcpToolkitDependency: _addMcpToolkitDependency,
      );
      stdout.writeln('Flutter Pilot init');
      stdout.writeln('');
      if (result.addedMcpToolkitDependency) {
        stdout.writeln('✅ Added MCP Toolkit dependency.');
      } else {
        stdout.writeln('✅ MCP Toolkit dependency already exists.');
      }
      if (result.status.hasBootstrapFlutter) {
        stdout.writeln('✅ bootstrapFlutter already exists.');
      } else {
        _writeBootstrapGuidance();
      }
      return 0;
    } on AppSetupInstallException catch (error) {
      stderr.writeln('Failed to add MCP Toolkit dependency.');
      if (error.result.stderr.isNotEmpty) {
        stderr.writeln('');
        stderr.writeln('flutter pub add output:');
        stderr.write(error.result.stderr);
      }
      stderr.writeln('');
      stderr.writeln('Run this command manually from the Flutter package:');
      stderr.writeln('flutter pub add mcp_toolkit');
      return 1;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } on YamlException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}

/// Run Flutter tooling to add the runtime dependency.
Future<AppSetupInstallResult> _addMcpToolkitDependency(
  Directory packageDirectory,
) async {
  try {
    final ProcessResult result = await Process.run('flutter', <String>[
      'pub',
      'add',
      'mcp_toolkit',
    ], workingDirectory: packageDirectory.path);
    if (result.exitCode == 0) {
      return const AppSetupInstallResult.success();
    }
    return AppSetupInstallResult.failure(
      exitCode: result.exitCode,
      stderr: result.stderr.toString(),
    );
  } on ProcessException catch (error) {
    return AppSetupInstallResult.failure(exitCode: 1, stderr: error.message);
  }
}

/// Print the manual app entrypoint change required for MCP Toolkit.
void _writeBootstrapGuidance() {
  stdout.writeln(
    '❌ bootstrapFlutter missing: add '
    'MCPToolkitBinding.instance.bootstrapFlutter in lib/main.dart',
  );
  stdout.writeln('');
  stdout.writeln('Add the MCP Toolkit import:');
  stdout.writeln("import 'package:mcp_toolkit/mcp_toolkit.dart';");
  stdout.writeln('');
  stdout.writeln('Wrap runApp with MCPToolkitBinding:');
  stdout.writeln('Future<void> main() async {');
  stdout.writeln('  await MCPToolkitBinding.instance.bootstrapFlutter(');
  stdout.writeln('    runApp: () => runApp(const MyApp()),');
  stdout.writeln('  );');
  stdout.writeln('}');
}

const String _flutterPackageOnlyMessage =
    'Flutter Pilot only supports Flutter packages. Run this command from a '
    'directory with a pubspec.yaml that declares dependencies.flutter.sdk: '
    'flutter.';

/// `diff` command for comparing two existing Scenario Run directories.
///
/// It reads each directory's `run_report.json`, generates a Step-focused Run
/// Diff, and prints either human-readable output or `--json` output.
/// Regressions are report content, not process failures, so successful diff
/// generation exits `0`.
class _DiffCommand extends Command<int> {
  _DiffCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print machine-readable Run Diff output.',
    );
  }

  @override
  String get description => 'Compare two Scenario Run directories.';

  @override
  String get name => 'diff';

  @override
  Future<int> run() async {
    final bool jsonOutput = argResults!.flag('json');
    if (argResults!.rest.length != 2) {
      throw UsageException('Expected before and after run directories.', usage);
    }
    final Directory beforeRunDirectory = Directory(argResults!.rest[0]);
    final Directory afterRunDirectory = Directory(argResults!.rest[1]);
    try {
      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: beforeRunDirectory,
        afterRunDirectory: afterRunDirectory,
      );
      if (jsonOutput) {
        stdout.writeln(RunDiffJsonRenderer.render(diff));
      } else {
        stdout.writeln(RunDiffTextRenderer.render(diff));
      }
      return 0;
    } on RunDiffException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}

/// `report` command for regenerating HTML from an existing run directory.
///
/// It reads `<run-directory>/run_report.json` and writes
/// `<run-directory>/timeline.html` without connecting to a Flutter runtime.
class _ReportCommand extends Command<int> {
  @override
  String get description =>
      'Generate an HTML timeline report from an existing run directory.';

  @override
  String get name => 'report';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one run directory.', usage);
    }
    final Directory runDirectory = Directory(argResults!.rest.single);
    if (!runDirectory.existsSync()) {
      stderr.writeln('Run directory does not exist: ${runDirectory.path}');
      return 1;
    }
    try {
      HtmlTimelineReport.generateFromRunDirectory(runDirectory);
      stdout.writeln('HTML report: ${runDirectory.path}/timeline.html');
      return 0;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}

/// Build the first-version default runner used by the executable.
ScenarioRunner _createDefaultRunner(RuntimeTarget target, Scenario scenario) {
  final String? testRuntime =
      Platform.environment['FLUTTER_PILOT_TEST_RUNTIME'];
  if (testRuntime != null) {
    return ScenarioRunner(
      adapter: switch (testRuntime) {
        'success' => _createSuccessfulFakeRuntimeAdapter(scenario),
        'failure' => _createFailureFakeRuntimeAdapter(scenario),
        _ => _createSuccessfulFakeRuntimeAdapter(scenario),
      },
      outputDirectory: Directory.current,
    );
  }
  return ScenarioRunner(
    adapter: McpFlutterRuntimeAdapter(target: target),
    outputDirectory: Directory.current,
  );
}

/// Build the test-only fake Runtime Adapter used by CLI subprocess tests.
///
/// This hook is intentionally selected through an environment variable rather
/// than a public CLI option so it does not become part of the user-facing
/// command contract or appear in `--help`.
FakeRuntimeAdapter _createSuccessfulFakeRuntimeAdapter(Scenario scenario) {
  final Map<String, List<FinderMatch>> finderResults =
      <String, List<FinderMatch>>{};
  for (final ScenarioStep step in scenario.steps) {
    final Finder? finder = _finderForAction(step.action);
    if (finder == null) {
      continue;
    }
    finderResults[_fakeRuntimeFinderKey(finder)] = <FinderMatch>[
      FinderMatch(id: 'step-${step.index}', debugLabel: step.label),
    ];
  }
  return FakeRuntimeAdapter(finderResults: finderResults);
}

/// Build the test-only fake Runtime Adapter that fails the first Finder match.
FakeRuntimeAdapter _createFailureFakeRuntimeAdapter(Scenario scenario) {
  final Map<String, List<FinderMatch>> finderResults =
      <String, List<FinderMatch>>{};
  for (final ScenarioStep step in scenario.steps) {
    final Finder? finder = _finderForAction(step.action);
    if (finder == null) {
      continue;
    }
    finderResults[_fakeRuntimeFinderKey(finder)] = const <FinderMatch>[];
    break;
  }
  return FakeRuntimeAdapter(finderResults: finderResults);
}

/// Return the Finder used by an action, if the action resolves one.
Finder? _finderForAction(StepAction action) {
  return switch (action) {
    TapAction(:final Finder finder) => finder,
    TypeAction(:final Finder finder) => finder,
    ScrollAction(:final Finder? finder) => finder,
    WaitForAction(:final Finder finder) => finder,
    CaptureAction() => null,
  };
}

/// Convert a Finder into the key expected by `FakeRuntimeAdapter`.
String _fakeRuntimeFinderKey(Finder finder) {
  final List<String> parts = <String>[
    if (finder.byText != null) 'byText=${finder.byText}',
    if (finder.byType != null) 'byType=${finder.byType}',
  ];
  if (parts.length == 1) {
    return parts.single.split('=').last;
  }
  return parts.join('&');
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
      const JsonEncoder.withIndent('  ').convert({
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
      ..addMultiOption(
        'print',
        allowed: ['snapshot', 'widget-tree', 'errors'],
        help: 'Print diagnostics after --until.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print raw diagnostics as indented JSON.',
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
    if (argResults!.multiOption('print').isNotEmpty &&
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
    RunStopPoint? stopPoint;
    if (until != null) {
      final String? error = _validateUntil(until, parsedScenario);
      if (error != null) {
        stderr.writeln(error);
        return 64;
      }
      stopPoint = _stopPointFromUntil(until);
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
      parsedScenario,
    );
    try {
      final bool jsonOutput = argResults!.flag('json');
      final StepProgressRenderer? progressRenderer = jsonOutput
          ? null
          : StepProgressRenderer(sink: stderr, interactive: stderr.hasTerminal);
      final ScenarioRunReport report = await runner.run(
        parsedScenario,
        stopPoint: stopPoint,
        printDiagnostics: _printDiagnosticsFromOptions(
          argResults!.multiOption('print'),
        ),
        onProgress: progressRenderer?.render,
      );
      if (report.printedDiagnostics.isNotEmpty) {
        if (jsonOutput) {
          stdout.writeln(
            const JsonEncoder.withIndent(
              '  ',
            ).convert(_printDiagnosticsJson(report)),
          );
        } else {
          stdout.writeln(DiagnosticTextRenderer.render(report));
        }
      }
      if (!jsonOutput) {
        _writeRunSummary(report);
      }
      stdout.writeln(
        '$_runReportLabel ${report.runDirectoryPath}/run_report.json',
      );
      stdout.writeln(
        '$_htmlReportLabel ${report.runDirectoryPath}/timeline.html',
      );
      return report.status == ScenarioRunStatus.passed ? 0 : 1;
    } on RuntimeOperationException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }

  static const String _runReportLabel = 'Run report:';
  static const String _htmlReportLabel = 'HTML report:';

  /// Print the final human-readable run summary to stderr.
  void _writeRunSummary(ScenarioRunReport report) {
    if (report.status == ScenarioRunStatus.passed &&
        report.stopPointDescription == null) {
      stderr.writeln('Run passed.');
      return;
    }
    if (report.stopPointDescription != null &&
        report.status == ScenarioRunStatus.passed) {
      stderr.writeln('Stopped after ${report.stopPointDescription}.');
      return;
    }
    if (report.failureReason != null) {
      stderr.writeln('Run failed at ${_failedStepText(report)}.');
      return;
    }
    stderr.writeln('Run completed.');
  }

  /// Describe the Step that ended a failed run.
  String _failedStepText(ScenarioRunReport report) {
    final StepRunReport failedStep = report.steps.firstWhere(
      (StepRunReport step) => step.status == StepStatus.failed,
      orElse: () => report.steps.last,
    );
    return '${failedStep.index}/${report.totalSteps}';
  }

  /// Return the runner stop point selected by a validated `--until` value.
  RunStopPoint _stopPointFromUntil(String until) {
    final int? stepNumber = int.tryParse(until);
    if (stepNumber != null) {
      return RunStopPoint.stepNumber(stepNumber);
    }
    return RunStopPoint.stepLabel(until);
  }

  /// Return the runner diagnostics selected by repeated CLI `--print` options.
  ///
  /// Args:
  /// `printValues` are the already-validated option values from `args`.
  ///
  /// Returns:
  /// The diagnostic requests to pass to the runner. Duplicate options collapse
  /// to one request.
  Set<PrintDiagnostic> _printDiagnosticsFromOptions(List<String> printValues) {
    final Set<PrintDiagnostic> printDiagnostics = <PrintDiagnostic>{};
    for (final String printValue in printValues) {
      final PrintDiagnostic? printDiagnostic = switch (printValue) {
        'snapshot' => PrintDiagnostic.snapshot,
        'widget-tree' => PrintDiagnostic.widgetTree,
        'errors' => PrintDiagnostic.errors,
        _ => null,
      };
      if (printDiagnostic != null) {
        printDiagnostics.add(printDiagnostic);
      }
    }
    return printDiagnostics;
  }

  /// Return the stdout JSON object for printable diagnostics.
  ///
  /// Args:
  /// `report` contains diagnostics already captured by the runner in fixed
  /// output order.
  ///
  /// Returns:
  /// A JSON-compatible object keyed by the CLI diagnostic names.
  Map<String, Object?> _printDiagnosticsJson(ScenarioRunReport report) {
    return <String, Object?>{
      for (final PrintedDiagnostic diagnostic in report.printedDiagnostics)
        _printDiagnosticJsonKey(diagnostic.type): diagnostic.data,
    };
  }

  /// Return the public JSON key for a printable diagnostic type.
  String _printDiagnosticJsonKey(PrintDiagnostic printDiagnostic) {
    return switch (printDiagnostic) {
      PrintDiagnostic.snapshot => 'snapshot',
      PrintDiagnostic.widgetTree => 'widgetTree',
      PrintDiagnostic.errors => 'errors',
    };
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
