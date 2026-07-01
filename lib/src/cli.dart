import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;
import 'package:yaml/yaml.dart';

import 'app_setup.dart';
import 'artifacts/artifact_store.dart';
import 'diagnostic_text_renderer.dart';
import 'html_timeline_report.dart';
import 'recording/recording_contract.dart';
import 'recording/screen_recorder_recording_controller.dart';
import 'project_scenario_discovery.dart';
import 'project_run_report.dart';
import 'runtime/mcp_flutter_runtime_adapter.dart';
import 'runtime/runtime_contract.dart';
import 'run_diff.dart';
import 'scenario.dart';
import 'scenario_parser.dart';
import 'scenario_runner.dart';
import 'step_progress_renderer.dart';
import 'target_app_launch_progress_renderer.dart';
import 'target_app_launcher.dart';
import 'target_device.dart';

/// Command-line entry point for Flutter Pilot.
///
/// It installs the first-version command surface:
/// - `validate <scenario.yaml>`
/// - `test <scenario.yaml>`
///
/// Example:
/// `FlutterPilotCli().run(['validate', 'examples/login_error.yaml'])`
class FlutterPilotCli {
  /// Creates a Flutter Pilot CLI instance.
  ///
  /// `testCommandExecutor` is injectable so tests can exercise the `test`
  /// command without launching a real Flutter app.
  const FlutterPilotCli({
    TestCommandExecutor testCommandExecutor =
        const DefaultTestCommandExecutor(),
    ProjectRunCommandExecutor projectRunCommandExecutor =
        const DefaultProjectRunCommandExecutor(),
  }) : _testCommandExecutor = testCommandExecutor,
       _projectRunCommandExecutor = projectRunCommandExecutor;

  final TestCommandExecutor _testCommandExecutor;
  final ProjectRunCommandExecutor _projectRunCommandExecutor;

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
          ..addCommand(
            _TestCommand(
              executor: _testCommandExecutor,
              projectRunExecutor: _projectRunCommandExecutor,
            ),
          )
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
  _TestCommand({
    required TestCommandExecutor executor,
    required ProjectRunCommandExecutor projectRunExecutor,
  }) : _executor = executor,
       _projectRunExecutor = projectRunExecutor {
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

  final TestCommandExecutor _executor;
  final ProjectRunCommandExecutor _projectRunExecutor;

  @override
  String get description => 'Launch the Target App Package and run a Scenario.';

  @override
  String get name => 'test';

  @override
  Future<int> run() async {
    if (argResults!.rest.length > 1) {
      throw UsageException('Expected zero or one scenario path.', usage);
    }
    final String? scenarioPath = argResults!.rest.isEmpty
        ? null
        : argResults!.rest.single;
    if (scenarioPath == null) {
      return _runProjectRun(
        ProjectScenarioDiscovery.defaultPilotDirectory,
        defaultDiscovery: true,
      );
    }
    if (FileSystemEntity.isDirectorySync(scenarioPath)) {
      return _runProjectRun(scenarioPath);
    }
    if (!FileSystemEntity.isFileSync(scenarioPath)) {
      throw UsageException(
        'Scenario path does not exist: $scenarioPath',
        usage,
      );
    }
    if (argResults!.multiOption('print').isNotEmpty &&
        argResults!.option('until') == null) {
      throw UsageException('--print must be used with --until.', usage);
    }

    final Scenario parsedScenario;
    try {
      parsedScenario = ScenarioParser.parseFile(scenarioPath);
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

    final String? device = argResults!.option('device')?.trim();
    if (device != null && device.isEmpty) {
      stderr.writeln('Target Device selector must not be empty.');
      return 64;
    }
    final String? flavor = argResults!.option('flavor')?.trim();
    if (flavor != null && flavor.isEmpty) {
      stderr.writeln('--flavor must not be empty.');
      return 64;
    }
    final String? target = argResults!.option('target')?.trim();
    if (target != null && target.isEmpty) {
      stderr.writeln('--target must not be empty.');
      return 64;
    }
    final TestCommandOptions options = TestCommandOptions(
      scenario: parsedScenario,
      device: device,
      flavor: flavor,
      target: target,
      stopPoint: stopPoint,
      printDiagnostics: _printDiagnosticsFromOptions(
        argResults!.multiOption('print'),
      ),
      jsonOutput: argResults!.flag('json'),
    );
    try {
      final StepProgressRenderer? progressRenderer =
          TestCommandOutput.stepProgressRenderer(
            sink: stderr,
            jsonOutput: options.jsonOutput,
            stderrHasTerminal: stderr.hasTerminal,
          );
      final TargetAppLaunchProgressRenderer? launchProgressRenderer =
          TestCommandOutput.targetAppLaunchProgressRenderer(
            sink: stderr,
            jsonOutput: options.jsonOutput,
            stderrHasTerminal: stderr.hasTerminal,
          );
      final ScenarioRunReport report = await _executor.run(
        options,
        onLaunchProgress: launchProgressRenderer?.render,
        launchHeartbeatEnabled: launchProgressRenderer != null,
        onProgress: progressRenderer?.render,
      );
      if (report.printedDiagnostics.isNotEmpty) {
        if (options.jsonOutput) {
          stdout.writeln(
            const JsonEncoder.withIndent(
              '  ',
            ).convert(_printDiagnosticsJson(report)),
          );
        } else {
          stdout.writeln(DiagnosticTextRenderer.render(report));
        }
      }
      stdout.writeln('Run report: ${report.runDirectoryPath}/run_report.json');
      stdout.writeln('HTML report: ${report.runDirectoryPath}/timeline.html');
      return report.status == ScenarioRunStatus.passed ? 0 : 1;
    } on TestCommandException catch (error) {
      if (!error.alreadyRendered) {
        stderr.writeln(error.message);
      }
      return error.exitCode;
    }
  }

  /// Discover Project Scenarios and delegate Project Run execution.
  Future<int> _runProjectRun(
    String discoveryRootPath, {
    bool defaultDiscovery = false,
  }) async {
    if (argResults!.option('until') != null) {
      throw UsageException(
        '--until is only supported for one Scenario file.',
        usage,
      );
    }
    if (argResults!.multiOption('print').isNotEmpty) {
      throw UsageException(
        '--print is only supported for one Scenario file.',
        usage,
      );
    }
    final List<ProjectScenarioFile> scenarios;
    try {
      scenarios = defaultDiscovery
          ? ProjectScenarioDiscovery.discoverDefault()
          : ProjectScenarioDiscovery.discoverInDirectory(discoveryRootPath);
    } on ProjectScenarioDiscoveryException catch (error) {
      stderr.writeln(error.message);
      return error.usageError ? 64 : 1;
    } on ScenarioValidationException catch (error) {
      _writeValidationErrors(error.errors);
      return 1;
    }
    final ProjectRunCommandOptions options = ProjectRunCommandOptions(
      discoveryRootPath: discoveryRootPath,
      scenarios: scenarios,
      device: argResults!.option('device')?.trim(),
      flavor: argResults!.option('flavor')?.trim(),
      target: argResults!.option('target')?.trim(),
      jsonOutput: argResults!.flag('json'),
    );
    try {
      final TargetAppLaunchProgressRenderer? launchProgressRenderer =
          TestCommandOutput.targetAppLaunchProgressRenderer(
            sink: stderr,
            jsonOutput: options.jsonOutput,
            stderrHasTerminal: stderr.hasTerminal,
          );
      final ProjectRunCommandReport report = await _projectRunExecutor.run(
        options,
        onLaunchProgress: launchProgressRenderer?.render,
        launchHeartbeatEnabled: launchProgressRenderer != null,
      );
      stdout.write(TestCommandOutput.renderProjectRunSummary(report));
      return report.passed ? 0 : 1;
    } on TestCommandException catch (error) {
      if (!error.alreadyRendered) {
        stderr.writeln(error.message);
      }
      return error.exitCode;
    }
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
class TestCommandOptions {
  /// Creates validated inputs for executing one Scenario through `test`.
  const TestCommandOptions({
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

/// Parsed Project Run inputs selected by the `test` command.
class ProjectRunCommandOptions {
  /// Creates validated Project Run command inputs.
  const ProjectRunCommandOptions({
    required this.discoveryRootPath,
    required this.scenarios,
    required this.device,
    required this.flavor,
    required this.target,
    required this.jsonOutput,
  });

  /// Directory used to discover Project Scenarios.
  final String discoveryRootPath;

  /// Validated Entry Scenario files selected for the Project Run.
  final List<ProjectScenarioFile> scenarios;

  final String? device;
  final String? flavor;
  final String? target;
  final bool jsonOutput;
}

/// Project Run command result used by mode selection and stdout rendering.
class ProjectRunCommandReport {
  const ProjectRunCommandReport({
    required this.passed,
    required this.projectRunReportPath,
    required this.scenarioReports,
  });

  /// Whether the selected Project Scenarios all passed.
  final bool passed;

  /// Path to the batch-level `project_run_report.json`.
  final String projectRunReportPath;

  /// Per-Scenario report paths to print after the Project Run finishes.
  final List<ProjectRunScenarioOutputReport> scenarioReports;
}

/// Report paths for one Scenario inside Project Run stdout.
class ProjectRunScenarioOutputReport {
  const ProjectRunScenarioOutputReport({
    required this.scenarioPath,
    required this.runReportPath,
    required this.htmlReportPath,
  });

  /// Project Scenario path relative to the discovery root.
  final String scenarioPath;

  /// Path to the child Scenario Run report.
  final String runReportPath;

  /// Path to the child Scenario HTML timeline report.
  final String htmlReportPath;
}

/// Executes a validated Project Run selected by `test`.
abstract interface class ProjectRunCommandExecutor {
  /// Run the Project Scenarios described by [options].
  ///
  /// `onLaunchProgress`, when provided, receives the batch-level Target App
  /// Launch Progress events before any Project Scenario executes.
  Future<ProjectRunCommandReport> run(
    ProjectRunCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
  });
}

/// Placeholder Project Run executor until orchestration lands in later slices.
class DefaultProjectRunCommandExecutor implements ProjectRunCommandExecutor {
  const DefaultProjectRunCommandExecutor({
    this.launcher = const TargetAppLauncher(),
    this.runnerFactory = const DefaultTestScenarioRunnerFactory(),
    this.outputDirectory,
    this.clock = DateTime.now,
  });

  final TargetAppLauncher launcher;
  final TestScenarioRunnerFactory runnerFactory;
  final Directory? outputDirectory;
  final TargetAppLaunchClock clock;

  @override
  Future<ProjectRunCommandReport> run(
    ProjectRunCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
  }) async {
    final DateTime startedAt = clock().toUtc();
    final ProjectRunArtifactWriter projectRunWriter = RunArtifactStore(
      outputDirectory ?? Directory.current,
    ).createProjectRun(startedAt: startedAt);
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<ProjectScenarioRunReport> scenarioResults =
        <ProjectScenarioRunReport>[];
    ProjectRunEnvironmentFailure? environmentFailure;
    TargetAppLaunch? launch;
    final TargetAppLaunchChoices launchChoices = TargetAppLaunchChoices(
      flavor: options.flavor,
      target: options.target,
    );
    onLaunchProgress?.call(
      TargetAppLaunchStartedEvent(startedAt: startedAt, choices: launchChoices),
    );
    try {
      launch = await launcher.launch(
        TargetAppLaunchCommand(
          flavor: options.flavor,
          target: options.target,
          deviceId: options.device,
        ),
      );
      onLaunchProgress?.call(
        TargetAppLaunchSucceededEvent(
          startedAt: startedAt,
          finishedAt: clock().toUtc(),
          choices: launchChoices,
        ),
      );
      for (int index = 0; index < options.scenarios.length; index++) {
        final ProjectScenarioFile scenarioFile = options.scenarios[index];
        if (index > 0) {
          try {
            await launch.hotRestart();
          } on TargetAppLaunchException catch (error) {
            environmentFailure = ProjectRunEnvironmentFailure(
              phase: ProjectRunEnvironmentFailurePhase.hotRestart,
              message: error.message,
            );
            break;
          }
        }
        final RunArtifactWriter childRun = projectRunWriter.createScenarioRun(
          scenario: scenarioFile.scenario,
          startedAt: clock().toUtc(),
        );
        final TestScenarioRunner runner = runnerFactory.create(
          runtimeTarget: RuntimeTarget(vmServiceUri: launch.runtimeTargetUri),
          targetDevice: null,
          recordingController: null,
        );
        final ScenarioRunReport scenarioReport = await runner.run(
          scenarioFile.scenario,
          runArtifactWriter: childRun,
        );
        final ProjectScenarioRunStatus scenarioStatus =
            scenarioReport.status == ScenarioRunStatus.passed
            ? ProjectScenarioRunStatus.passed
            : ProjectScenarioRunStatus.failed;
        scenarioResults.add(
          ProjectScenarioRunReport(
            scenarioPath: scenarioFile.relativePath,
            status: scenarioStatus,
            runReportPath: projectRunWriter.relativePathFor(
              childRun,
              'run_report.json',
            ),
            htmlReportPath: projectRunWriter.relativePathFor(
              childRun,
              'timeline.html',
            ),
          ),
        );
      }
    } on TargetAppLaunchException catch (error) {
      environmentFailure = ProjectRunEnvironmentFailure(
        phase: ProjectRunEnvironmentFailurePhase.launch,
        message: error.message,
      );
      onLaunchProgress?.call(
        TargetAppLaunchFailedEvent(
          startedAt: startedAt,
          failedAt: clock().toUtc(),
          message: error.message,
          stderrLines: error.stderrLines,
          choices: launchChoices,
        ),
      );
    } on TestCommandException catch (error) {
      environmentFailure = ProjectRunEnvironmentFailure(
        phase: ProjectRunEnvironmentFailurePhase.validation,
        message: error.message,
      );
    } finally {
      stopwatch.stop();
      await launch?.cleanup();
    }
    final bool allPassed =
        environmentFailure == null &&
        scenarioResults.every(
          (ProjectScenarioRunReport report) =>
              report.status == ProjectScenarioRunStatus.passed,
        );
    final ProjectRunStatus projectStatus = environmentFailure != null
        ? ProjectRunStatus.environmentFailed
        : allPassed
        ? ProjectRunStatus.passed
        : ProjectRunStatus.failed;
    final ProjectRunReport projectReport = environmentFailure == null
        ? ProjectRunReport(
            discoveryRootPath: options.discoveryRootPath,
            scenarioResults: scenarioResults,
            status: projectStatus,
            startedAt: startedAt,
            durationMs: stopwatch.elapsedMilliseconds,
            commandInputs: ProjectRunCommandInputs(
              device: options.device,
              flavor: options.flavor,
              target: options.target,
            ),
          )
        : ProjectRunReport.environmentFailure(
            discoveryRootPath: options.discoveryRootPath,
            startedAt: startedAt,
            durationMs: stopwatch.elapsedMilliseconds,
            commandInputs: ProjectRunCommandInputs(
              device: options.device,
              flavor: options.flavor,
              target: options.target,
            ),
            failure: environmentFailure,
            scenarioResults: scenarioResults,
          );
    projectRunWriter.writeProjectRunReport(projectReport.toJson());
    return ProjectRunCommandReport(
      passed: projectStatus == ProjectRunStatus.passed,
      projectRunReportPath: p.join(
        projectRunWriter.runDirectory.path,
        'project_run_report.json',
      ),
      scenarioReports: <ProjectRunScenarioOutputReport>[
        for (final ProjectScenarioRunReport scenarioReport in scenarioResults)
          ProjectRunScenarioOutputReport(
            scenarioPath: scenarioReport.scenarioPath,
            runReportPath: p.join(
              projectRunWriter.runDirectory.path,
              scenarioReport.runReportPath,
            ),
            htmlReportPath: p.join(
              projectRunWriter.runDirectory.path,
              scenarioReport.htmlReportPath,
            ),
          ),
      ],
    );
  }
}

/// Terminal output helpers for the `test` command.
class TestCommandOutput {
  TestCommandOutput._();

  /// Return the Step progress renderer for human-readable `test` output.
  ///
  /// JSON output is machine-oriented and suppresses Step progress. Interactive
  /// rendering is used only when stderr is a terminal; redirected stderr gets
  /// deterministic plain-text progress lines for CI logs.
  static StepProgressRenderer? stepProgressRenderer({
    required IOSink sink,
    required bool jsonOutput,
    required bool stderrHasTerminal,
  }) {
    if (jsonOutput) {
      return null;
    }
    return StepProgressRenderer(sink: sink, interactive: stderrHasTerminal);
  }

  /// Return the Target App Launch Progress renderer for human-readable output.
  ///
  /// Launch progress is stderr-only status. JSON output suppresses it so stdout
  /// remains machine-oriented.
  static TargetAppLaunchProgressRenderer? targetAppLaunchProgressRenderer({
    required IOSink sink,
    required bool jsonOutput,
    required bool stderrHasTerminal,
  }) {
    if (jsonOutput) {
      return null;
    }
    return TargetAppLaunchProgressRenderer(
      sink: sink,
      interactive: stderrHasTerminal,
    );
  }

  /// Return deterministic stdout summary lines for a completed Project Run.
  ///
  /// The summary keeps the batch-level report path first, then prints each
  /// Scenario's existing report paths in execution order.
  static String renderProjectRunSummary(ProjectRunCommandReport report) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Project Run report: ${report.projectRunReportPath}');
    for (final ProjectRunScenarioOutputReport scenarioReport
        in report.scenarioReports) {
      buffer
        ..writeln('Scenario: ${scenarioReport.scenarioPath}')
        ..writeln('Run report: ${scenarioReport.runReportPath}')
        ..writeln('HTML report: ${scenarioReport.htmlReportPath}');
    }
    return buffer.toString();
  }
}

/// Executes a validated `test` command.
abstract interface class TestCommandExecutor {
  /// Run the Scenario described by `options` and return its run report.
  ///
  /// `onLaunchProgress`, when provided, receives Target App Launch Progress
  /// events before Scenario execution starts. `launchHeartbeatEnabled` controls
  /// whether long pending launches emit heartbeat events. `onProgress`, when
  /// provided, receives Scenario Step progress events during execution.
  Future<ScenarioRunReport> run(
    TestCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  });
}

/// Default `test` command executor for launching and running one Scenario.
class DefaultTestCommandExecutor implements TestCommandExecutor {
  /// Creates an executor with injectable launch and discovery boundaries.
  ///
  /// `launchHeartbeatTicks` and `launchClock` make Target App Launch Progress
  /// deterministic in tests without waiting on real time.
  const DefaultTestCommandExecutor({
    this.deviceDiscovery = const DefaultTestDeviceDiscovery(),
    this.launcher = const TargetAppLauncher(),
    this.runnerFactory = const DefaultTestScenarioRunnerFactory(),
    this.interruptSignals,
    this.launchHeartbeatTicks,
    this.launchClock = DateTime.now,
  });

  final TestDeviceDiscovery deviceDiscovery;
  final TargetAppLauncher launcher;
  final TestScenarioRunnerFactory runnerFactory;
  final Stream<void>? interruptSignals;
  final Stream<void>? launchHeartbeatTicks;
  final TargetAppLaunchClock launchClock;

  @override
  Future<ScenarioRunReport> run(
    TestCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    final bool recordingRequired = options.scenario.recording?.enabled == true;
    TargetDevice? targetDevice;
    if (options.device != null || recordingRequired) {
      try {
        final List<FlutterDevice> flutterDevices = await deviceDiscovery
            .listFlutterDevices();
        final List<RecordingDeviceIdentity> recordingDevices = recordingRequired
            ? await deviceDiscovery.listRecordingDevices()
            : const <RecordingDeviceIdentity>[];
        targetDevice = TargetDeviceResolver.resolve(
          selector: options.device,
          recordingRequired: recordingRequired,
          flutterDevices: flutterDevices,
          recordingDevices: recordingDevices,
        );
      } on TargetDeviceResolutionException catch (error) {
        throw TestCommandException(message: error.message, exitCode: 64);
      } on DeviceDiscoveryException catch (error) {
        throw TestCommandException(message: error.message, exitCode: 1);
      }
    }

    TargetAppLaunch launch;
    final DateTime launchStartedAt = launchClock();
    final TargetAppLaunchChoices launchChoices = TargetAppLaunchChoices(
      targetDevice: targetDevice,
      selectionReason: _targetDeviceSelectionReason(
        deviceSelector: options.device,
        recordingRequired: recordingRequired,
      ),
      flavor: options.flavor,
      target: options.target,
    );
    onLaunchProgress?.call(
      TargetAppLaunchStartedEvent(
        startedAt: launchStartedAt,
        choices: launchChoices,
      ),
    );
    TargetAppLaunchHeartbeat? launchHeartbeat;
    if (onLaunchProgress != null && launchHeartbeatEnabled) {
      launchHeartbeat = TargetAppLaunchHeartbeat(
        ticks:
            launchHeartbeatTicks ??
            Stream<void>.periodic(const Duration(seconds: 10)),
        onProgress: onLaunchProgress,
        clock: launchClock,
      );
      launchHeartbeat.start(
        TargetAppLaunchStartedEvent(
          startedAt: launchStartedAt,
          choices: launchChoices,
        ),
      );
    }
    try {
      launch = await launcher.launch(
        TargetAppLaunchCommand(
          deviceId: targetDevice?.id,
          flavor: options.flavor,
          target: options.target,
        ),
      );
      onLaunchProgress?.call(
        TargetAppLaunchSucceededEvent(
          startedAt: launchStartedAt,
          finishedAt: launchClock(),
          choices: launchChoices,
        ),
      );
      await launchHeartbeat?.stop();
    } on TargetAppLaunchException catch (error) {
      onLaunchProgress?.call(
        TargetAppLaunchFailedEvent(
          startedAt: launchStartedAt,
          failedAt: launchClock(),
          message: error.message,
          stderrLines: error.stderrLines,
          choices: launchChoices,
        ),
      );
      await launchHeartbeat?.stop();
      final String stderrContext =
          onLaunchProgress == null && error.stderrLines.isNotEmpty
          ? '\n${error.stderrLines.join('\n')}'
          : '';
      throw TestCommandException(
        message: '${error.message}$stderrContext',
        exitCode: 1,
        alreadyRendered: onLaunchProgress != null,
      );
    }

    try {
      final TestScenarioRunner runner = runnerFactory.create(
        runtimeTarget: RuntimeTarget(vmServiceUri: launch.runtimeTargetUri),
        targetDevice: targetDevice,
        recordingController: recordingRequired
            ? ScreenRecorderRecordingController(
                recorder: screen_recorder.ScreenRecorder.defaultRecorder(),
                deviceSelector: targetDevice!.id,
                outputDirectory: Directory.current,
              )
            : null,
      );
      final Future<ScenarioRunReport> runFuture = runner.run(
        options.scenario,
        stopPoint: options.stopPoint,
        printDiagnostics: options.printDiagnostics,
        onProgress: onProgress,
      );
      StreamSubscription<void>? interruptSub;
      try {
        final Completer<ScenarioRunReport> interruptCompleter =
            Completer<ScenarioRunReport>();
        interruptSub =
            (interruptSignals ??
                    ProcessSignal.sigint.watch().map<void>(
                      (ProcessSignal _) {},
                    ))
                .listen((_) {
                  if (!interruptCompleter.isCompleted) {
                    interruptCompleter.completeError(
                      const TestCommandException(
                        message: 'test command interrupted.',
                        exitCode: 130,
                      ),
                    );
                  }
                });
        return await Future.any(<Future<ScenarioRunReport>>[
          runFuture,
          interruptCompleter.future,
        ]);
      } finally {
        runFuture.ignore();
        await interruptSub?.cancel();
      }
    } on RuntimeOperationException catch (error) {
      throw TestCommandException(message: error.message, exitCode: 1);
    } finally {
      await launch.cleanup();
    }
  }

  /// Return the user-facing reason for the selected Target Device.
  TargetDeviceSelectionReason? _targetDeviceSelectionReason({
    required String? deviceSelector,
    required bool recordingRequired,
  }) {
    if (deviceSelector != null) {
      return TargetDeviceSelectionReason.explicit(selector: deviceSelector);
    }
    if (recordingRequired) {
      return const TargetDeviceSelectionReason.autoSelectedForRecording();
    }
    return null;
  }
}

/// Discovers Flutter Devices and Recording Devices for `test`.
abstract interface class TestDeviceDiscovery {
  /// Return Flutter Devices from `flutter devices --machine`.
  Future<List<FlutterDevice>> listFlutterDevices();

  /// Return Recording Device identities available for Scenario Recording.
  Future<List<RecordingDeviceIdentity>> listRecordingDevices();
}

/// Default device discovery backed by Flutter CLI and `screen_recorder`.
class DefaultTestDeviceDiscovery implements TestDeviceDiscovery {
  /// Creates default Target Device discovery.
  const DefaultTestDeviceDiscovery();

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    final ProcessResult result;
    try {
      result = await Process.run('flutter', <String>['devices', '--machine']);
    } on ProcessException catch (error) {
      throw DeviceDiscoveryException(error.message);
    }
    if (result.exitCode != 0) {
      throw DeviceDiscoveryException(result.stderr.toString());
    }
    try {
      return TargetDeviceParser.parseMachineJson(result.stdout.toString());
    } on FormatException catch (e) {
      throw DeviceDiscoveryException(e.message);
    }
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    final screen_recorder.ScreenRecorder recorder =
        screen_recorder.ScreenRecorder.defaultRecorder();
    final List<screen_recorder.RecordingDevice> devices = await recorder
        .listDevices();
    return <RecordingDeviceIdentity>[
      for (final screen_recorder.RecordingDevice device in devices)
        RecordingDeviceIdentity(id: device.id),
    ];
  }
}

/// Creates a Scenario runner for one launched Runtime Target.
abstract interface class TestScenarioRunnerFactory {
  /// Create a runner bound to the launched Runtime Target.
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  });
}

/// Narrow Scenario runner interface used by the `test` command executor.
abstract interface class TestScenarioRunner {
  /// Run `scenario` with optional stop, diagnostic, and Step progress controls.
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics,
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  });
}

/// Default Scenario runner factory backed by `McpFlutterRuntimeAdapter`.
class DefaultTestScenarioRunnerFactory implements TestScenarioRunnerFactory {
  /// Creates the default runner factory.
  const DefaultTestScenarioRunnerFactory();

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    return _ScenarioRunnerAdapter(
      ScenarioRunner(
        adapter: McpFlutterRuntimeAdapter(target: runtimeTarget),
        recordingController: recordingController,
        targetDevice: targetDevice,
        outputDirectory: Directory.current,
      ),
    );
  }
}

class _ScenarioRunnerAdapter implements TestScenarioRunner {
  const _ScenarioRunnerAdapter(this._runner);

  final ScenarioRunner _runner;

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) {
    return _runner.run(
      scenario,
      stopPoint: stopPoint,
      printDiagnostics: printDiagnostics,
      onProgress: onProgress,
      runArtifactWriter: runArtifactWriter,
    );
  }
}

/// Failure raised when device discovery fails.
class DeviceDiscoveryException implements Exception {
  /// Creates a device discovery failure.
  const DeviceDiscoveryException(this.message);

  /// Human-readable failure reason.
  final String message;

  @override
  String toString() => message;
}

/// Failure from the `test` command executor.
class TestCommandException implements Exception {
  /// Creates a command execution failure.
  const TestCommandException({
    required this.message,
    required this.exitCode,
    this.alreadyRendered = false,
  });

  /// Human-readable error message.
  final String message;

  /// CLI exit code.
  final int exitCode;

  /// Whether `message` was already written by command-specific output.
  ///
  /// The `test` command uses this for launch failures rendered by Target App
  /// Launch Progress so the same message is not printed twice.
  final bool alreadyRendered;
}
