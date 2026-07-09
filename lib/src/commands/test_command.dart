import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../diagnostic_text_renderer.dart';
import '../project_scenario_discovery.dart';
import '../scenario.dart';
import '../scenario_parser.dart';
import '../scenario_runner.dart';
import '../step_progress_renderer.dart';
import '../target_app_launch_progress_renderer.dart';
import '../test_command_support.dart';

/// `test` command shell for validating CLI arguments before app launch.
///
/// It checks Scenario YAML and validates `--until` / `--print` relationships
class TestCommand extends Command<int> {
  TestCommand({
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
        allowed: ['widget-tree', 'errors'],
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
    final String? device = argResults!.option('device')?.trim();
    if (device != null && device.isEmpty) {
      stderr.writeln('--device must not be empty.');
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
      device: device,
      flavor: flavor,
      target: target,
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
      final ProjectRunCommandReport report = await _projectRunExecutor.run(
        options,
        onLaunchProgress: launchProgressRenderer?.render,
        launchHeartbeatEnabled: launchProgressRenderer != null,
        onProgress: progressRenderer?.render,
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
