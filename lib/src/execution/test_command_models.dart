import '../reports/project_run_report.dart';
import '../scenario/project_scenario_discovery.dart';
import '../scenario/scenario.dart';
import 'scenario_runner.dart';

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
class ProjectRunOptions {
  /// Creates validated Project Run inputs.
  const ProjectRunOptions({
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

/// Project Run result used by mode selection and stdout rendering.
class ProjectRunResult {
  const ProjectRunResult({
    required this.passed,
    required this.status,
    required this.projectRunReportPath,
    required this.scenarioReports,
  });

  /// Whether the selected Project Scenarios all passed.
  final bool passed;

  /// Overall Project Run status.
  final ProjectRunStatus status;

  /// Path to the batch-level `project_run_report.json`.
  final String projectRunReportPath;

  /// Per-Scenario report paths to print after the Project Run finishes.
  final List<ProjectRunScenarioOutputReport> scenarioReports;
}

/// Report paths for one Scenario inside Project Run stdout.
class ProjectRunScenarioOutputReport {
  const ProjectRunScenarioOutputReport({
    required this.scenarioPath,
    required this.status,
    required this.runReportPath,
    required this.htmlReportPath,
  });

  /// Project Scenario path relative to the discovery root.
  final String scenarioPath;

  /// Scenario status in the Project Run summary.
  final ProjectScenarioRunStatus status;

  /// Path to the child Scenario Run report.
  final String runReportPath;

  /// Path to the child Scenario HTML timeline report.
  final String htmlReportPath;
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
