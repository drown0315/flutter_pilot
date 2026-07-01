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

  final String discoveryRootPath;
  final List<ProjectScenarioRunReport> scenarioResults;
  final ProjectRunStatus status;
  final DateTime startedAt;
  final int durationMs;
  final ProjectRunCommandInputs commandInputs;
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

  final String scenarioPath;
  final ProjectScenarioRunStatus status;
  final String runReportPath;
  final String htmlReportPath;

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

  final String? device;
  final String? flavor;
  final String? target;

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

  final ProjectRunEnvironmentFailurePhase phase;
  final String message;

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
