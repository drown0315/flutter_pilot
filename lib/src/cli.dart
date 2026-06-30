import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'app_setup.dart';
import 'html_timeline_report.dart';
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
          ..addCommand(_TestCommand())
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

/// `test` command shell for validating CLI arguments before app launch.
///
/// It checks Scenario YAML and validates `--until` / `--print` relationships
/// before the Target App Package is launched.
class _TestCommand extends Command<int> {
  _TestCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Target Device id, exact name, or unique id/name prefix.',
      )
      ..addOption('flavor', help: 'Flutter flavor passed to flutter run.')
      ..addOption(
        'target',
        abbr: 't',
        help: 'Flutter app entrypoint file passed to flutter run.',
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
  String get description => 'Launch the Target App Package and run a Scenario.';

  @override
  String get name => 'test';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one scenario file.', usage);
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

    final String? device = argResults!.option('device');
    if (device != null && device.trim().isEmpty) {
      stderr.writeln('Target Device selector must not be empty.');
      return 64;
    }
    final String? flavor = argResults!.option('flavor');
    if (flavor != null && flavor.trim().isEmpty) {
      stderr.writeln('--flavor must not be empty.');
      return 64;
    }
    final String? target = argResults!.option('target');
    if (target != null && target.trim().isEmpty) {
      stderr.writeln('--target must not be empty.');
      return 64;
    }
    final _TestCommandOptions options = _TestCommandOptions(
      scenario: parsedScenario,
      device: device?.trim(),
      flavor: flavor?.trim(),
      target: target?.trim(),
      stopPoint: stopPoint,
      printDiagnostics: _printDiagnosticsFromOptions(
        argResults!.multiOption('print'),
      ),
      jsonOutput: argResults!.flag('json'),
    );
    _ignorePendingTestCommandWiring(options);

    stderr.writeln('test command app launch is not implemented yet.');
    return 1;
  }

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

/// Parsed `test` command inputs that are validated before app launch.
class _TestCommandOptions {
  const _TestCommandOptions({
    required this.scenario,
    required this.device,
    required this.flavor,
    required this.target,
    required this.stopPoint,
    required this.printDiagnostics,
    required this.jsonOutput,
  });

  final Scenario scenario;
  final String? device;
  final String? flavor;
  final String? target;
  final RunStopPoint? stopPoint;
  final Set<PrintDiagnostic> printDiagnostics;
  final bool jsonOutput;
}

/// Keep pre-launch option parsing explicit until app launch wiring lands.
void _ignorePendingTestCommandWiring(_TestCommandOptions options) {
  Object.hash(
    options.scenario,
    options.device,
    options.flavor,
    options.target,
    options.stopPoint,
    options.printDiagnostics,
    options.jsonOutput,
  );
}
