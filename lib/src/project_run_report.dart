/// Machine-readable report model for one Project Run.
///
/// The report summarizes the discovery root, selected Project Scenarios,
/// per-Scenario report paths, command inputs, timing, and environment-level
/// failures that stop a batch before all Scenarios run.
class ProjectRunReport {
  const ProjectRunReport({
    required this.discoveryRootPath,
    required this.scenarioResults,
    required this.status,
    required this.startedAt,
    required this.durationMs,
    required this.commandInputs,
    this.environmentFailure,
  });

  /// Create a Project Run report stopped by an environment-level failure.
  const ProjectRunReport.environmentFailure({
    required this.discoveryRootPath,
    required this.startedAt,
    required this.durationMs,
    required this.commandInputs,
    required ProjectRunEnvironmentFailure failure,
    this.scenarioResults = const <ProjectScenarioRunReport>[],
  }) : status = ProjectRunStatus.environmentFailed,
       environmentFailure = failure;

  /// Directory path that was used for Project Scenario discovery.
  final String discoveryRootPath;

  /// Per-Scenario results recorded in execution order.
  final List<ProjectScenarioRunReport> scenarioResults;

  /// Final batch status for the Project Run.
  final ProjectRunStatus status;

  /// UTC time when the Project Run started.
  final DateTime startedAt;

  /// Total Project Run duration in milliseconds.
  final int durationMs;

  /// CLI options that affected launch and report output.
  final ProjectRunCommandInputs commandInputs;

  /// Environment-level failure that stopped the batch, when present.
  final ProjectRunEnvironmentFailure? environmentFailure;

  /// Convert this report to the JSON stored in `project_run_report.json`.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'discoveryRoot': discoveryRootPath,
      'status': status.name,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'durationMs': durationMs,
      'commandInputs': commandInputs.toJson(),
      if (environmentFailure != null)
        'environmentFailure': environmentFailure!.toJson(),
      'scenarios': <Object?>[
        for (final ProjectScenarioRunReport scenario in scenarioResults)
          scenario.toJson(),
      ],
    };
  }
}

/// Overall Project Run status.
enum ProjectRunStatus { passed, failed, environmentFailed }

/// Status for one Scenario Run inside a Project Run.
enum ProjectScenarioRunStatus { passed, failed }

/// Report entry for one Scenario Run inside a Project Run.
class ProjectScenarioRunReport {
  const ProjectScenarioRunReport({
    required this.scenarioPath,
    required this.status,
    required this.runReportPath,
    required this.htmlReportPath,
  });

  /// Project Scenario path relative to the discovery root.
  final String scenarioPath;

  /// Final status for this Scenario inside the Project Run.
  final ProjectScenarioRunStatus status;

  /// Project Run root-relative path to this Scenario's `run_report.json`.
  final String runReportPath;

  /// Project Run root-relative path to this Scenario's `timeline.html`.
  final String htmlReportPath;

  /// Convert this Scenario result to the Project Run report JSON shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': scenarioPath,
      'status': status.name,
      'runReportPath': runReportPath,
      'htmlReportPath': htmlReportPath,
    };
  }
}

/// CLI inputs that affect Project Run execution and reports.
class ProjectRunCommandInputs {
  const ProjectRunCommandInputs({this.device, this.flavor, this.target});

  /// Target Device selector passed through `--device`, when provided.
  final String? device;

  /// Flutter flavor passed through `--flavor`, when provided.
  final String? flavor;

  /// Flutter app entrypoint passed through `--target`, when provided.
  final String? target;

  /// Convert provided command inputs to the Project Run report JSON shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (device != null) 'device': device,
      if (flavor != null) 'flavor': flavor,
      if (target != null) 'target': target,
    };
  }
}

/// Environment-level failure that stops a Project Run.
class ProjectRunEnvironmentFailure {
  const ProjectRunEnvironmentFailure({
    required this.phase,
    required this.message,
  });

  /// Project Run phase where the environment-level failure happened.
  final ProjectRunEnvironmentFailurePhase phase;

  /// User-facing failure message for the stopped Project Run.
  final String message;

  /// Convert this failure to the Project Run report JSON shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{'phase': phase.name, 'message': message};
  }
}

/// Project Run phase that produced an environment-level failure.
enum ProjectRunEnvironmentFailurePhase {
  discovery,
  validation,
  targetDeviceResolution,
  launch,
  hotRestart,
}
