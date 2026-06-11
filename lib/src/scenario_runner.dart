import 'dart:io';

import 'artifacts/artifact_store.dart';
import 'runtime/runtime_contract.dart';
import 'scenario.dart';

/// Runner for replaying one Scenario through a Runtime Adapter.
///
/// It contains:
/// - the Runtime Adapter used for UI operations and captures
/// - the output directory where run artifacts are written
///
/// During `run`, it:
/// - initialize the Runtime Adapter
/// - execute ordered Steps
/// - dispose the Runtime Adapter
/// - write Scenario, Step metadata, and run report artifacts
///
/// Example:
/// `ScenarioRunner(adapter: adapter, outputDirectory: Directory('build'))`
/// writes under `build/.runs/<timestamp>_<scenario>/`.
class ScenarioRunner {
  const ScenarioRunner({required this.adapter, required this.outputDirectory});

  static const Duration _waitForPollInterval = Duration(milliseconds: 50);

  final RuntimeAdapter adapter;
  final Directory outputDirectory;

  /// Execute every Step in a Scenario and write a run report.
  ///
  /// Args:
  /// `scenario` is the parsed Scenario to replay through the Runtime Adapter.
  /// Its name is used in the run directory name, and its Steps determine which
  /// Runtime Adapter operations are called.
  ///
  /// Returns:
  /// A `ScenarioRunReport` containing Scenario metadata, run status, elapsed
  /// time, the run directory path, artifact paths, and ordered Step results.
  Future<ScenarioRunReport> run(Scenario scenario) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final RunArtifactWriter runArtifactWriter = RunArtifactStore(
      outputDirectory,
    ).createRun(scenario: scenario, startedAt: startedAt);
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<StepRunReport> steps = <StepRunReport>[];

    final String? initializeFailure = await _tryInitializeAdapter();
    if (initializeFailure != null) {
      stopwatch.stop();
      return _finishRun(
        scenario: scenario,
        runArtifactWriter: runArtifactWriter,
        startedAt: startedAt,
        durationMs: stopwatch.elapsedMilliseconds,
        steps: steps,
        failed: true,
        failureReason: initializeFailure,
      );
    }

    bool failed = false;
    String? failureReason = await _executeSteps(scenario.steps, steps);
    if (failureReason != null) {
      failed = true;
    }

    final String? disposeFailure = await _tryDisposeAdapter();
    if (!failed && disposeFailure != null) {
      failed = true;
      failureReason = disposeFailure;
    }

    stopwatch.stop();
    return _finishRun(
      scenario: scenario,
      runArtifactWriter: runArtifactWriter,
      startedAt: startedAt,
      durationMs: stopwatch.elapsedMilliseconds,
      steps: steps,
      failed: failed,
      failureReason: failureReason,
    );
  }

  /// Initialize the Runtime Adapter and return an initialization failure.
  ///
  /// Returns:
  /// `null` when initialization succeeds. Otherwise, the runtime failure message
  /// that should become the run-level failure reason.
  Future<String?> _tryInitializeAdapter() async {
    try {
      await adapter.initialize();
      return null;
    } on RuntimeOperationException catch (error) {
      return error.message;
    }
  }

  /// Execute ordered Scenario Steps and append their reports.
  ///
  /// Args:
  /// `scenarioSteps` are the parsed Steps to execute in order.
  /// `reports` receives one `StepRunReport` for each executed Step.
  ///
  /// Returns:
  /// `null` when all Steps pass. Otherwise, the first Step failure reason. When
  /// a Runtime Adapter operation throws, this method records that active Step as
  /// failed and stops the Step loop.
  Future<String?> _executeSteps(
    List<ScenarioStep> scenarioSteps,
    List<StepRunReport> reports,
  ) async {
    ScenarioStep? activeStep;
    Stopwatch? activeStepStopwatch;
    try {
      for (final ScenarioStep step in scenarioSteps) {
        activeStep = step;
        activeStepStopwatch = Stopwatch()..start();
        final StepRunReport stepReport = await _executeStep(
          step,
          activeStepStopwatch,
        );
        reports.add(stepReport);
        if (stepReport.status == StepStatus.failed) {
          return stepReport.failureReason;
        }
      }
    } on RuntimeOperationException catch (error) {
      activeStepStopwatch?.stop();
      final ScenarioStep? step = activeStep;
      if (step != null) {
        reports.add(
          StepRunReport(
            index: step.index,
            label: step.label,
            action: _actionName(step.action),
            status: StepStatus.failed,
            durationMs: activeStepStopwatch?.elapsedMilliseconds ?? 0,
            failureReason: error.message,
          ),
        );
      }
      return error.message;
    }
    return null;
  }

  /// Dispose the Runtime Adapter and return a cleanup failure.
  ///
  /// Returns:
  /// `null` when cleanup succeeds. Otherwise, the runtime failure message that
  /// should become the run-level failure reason only when no Step failed first.
  Future<String?> _tryDisposeAdapter() async {
    try {
      await adapter.dispose();
      return null;
    } on RuntimeOperationException catch (error) {
      return error.message;
    }
  }

  /// Write Step metadata and the final run report.
  ///
  /// Args:
  /// `scenario` provides Scenario metadata for the report.
  /// `runArtifactWriter` writes files into the run directory.
  /// `startedAt` is the UTC run start time.
  /// `durationMs` is the total run duration in milliseconds.
  /// `steps` are the executed Step reports.
  /// `failed` controls the final run status.
  /// `failureReason` is the optional run-level failure message.
  ///
  /// Returns:
  /// The report that was also written to `run_report.json`.
  ScenarioRunReport _finishRun({
    required Scenario scenario,
    required RunArtifactWriter runArtifactWriter,
    required DateTime startedAt,
    required int durationMs,
    required List<StepRunReport> steps,
    required bool failed,
    required String? failureReason,
  }) {
    final List<ArtifactReport> artifacts = <ArtifactReport>[
      const ArtifactReport(type: ArtifactType.scenario, path: 'scenario.json'),
    ];
    _writeStepMetadataArtifacts(runArtifactWriter, steps, artifacts);
    final ScenarioRunReport report = ScenarioRunReport(
      scenarioName: scenario.name,
      scenarioDescription: scenario.description,
      status: failed ? ScenarioRunStatus.failed : ScenarioRunStatus.passed,
      startedAt: startedAt,
      durationMs: durationMs,
      steps: steps,
      runDirectoryPath: runArtifactWriter.runDirectory.path,
      artifacts: artifacts,
      failureReason: failureReason,
    );
    _writeReport(runArtifactWriter, report);
    return report;
  }

  /// Execute one Step and return its report entry.
  Future<StepRunReport> _executeStep(
    ScenarioStep step,
    Stopwatch stopwatch,
  ) async {
    final String actionName = _actionName(step.action);
    try {
      await _executeAction(step.action);
      stopwatch.stop();
      return StepRunReport(
        index: step.index,
        label: step.label,
        action: actionName,
        status: StepStatus.passed,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on _StepFailureException catch (error) {
      stopwatch.stop();
      return StepRunReport(
        index: step.index,
        label: step.label,
        action: error.actionName,
        status: StepStatus.failed,
        durationMs: stopwatch.elapsedMilliseconds,
        failureReason: error.message,
      );
    }
  }

  /// Return the stable report action name for a Step action.
  String _actionName(StepAction action) {
    return switch (action) {
      TapAction() => 'tap',
      TypeAction() => 'type',
      ScrollAction() => 'scroll',
      WaitForAction() => 'waitFor',
      CaptureAction() => 'capture',
    };
  }

  /// Dispatch one action to the Runtime Adapter.
  Future<String> _executeAction(StepAction action) async {
    return switch (action) {
      TapAction(:final Finder finder) => _withUniqueMatch(
        finder,
        (FinderMatch match) => adapter.performTap(match),
        actionName: 'tap',
      ),
      TypeAction(:final Finder finder, :final String text) => _withUniqueMatch(
        finder,
        (FinderMatch match) => adapter.replaceText(match, text),
        actionName: 'type',
      ),
      ScrollAction(
        :final Finder? finder,
        :final double deltaX,
        :final double deltaY,
      ) =>
        _executeScroll(finder: finder, deltaX: deltaX, deltaY: deltaY),
      WaitForAction(:final Finder finder, :final int timeoutMs) => _waitFor(
        finder,
        timeout: Duration(milliseconds: timeoutMs),
      ),
      CaptureAction(
        :final bool screenshot,
        :final bool snapshot,
        :final bool widgetTree,
        :final bool logs,
      ) =>
        _executeCapture(
          screenshot: screenshot,
          snapshot: snapshot,
          widgetTree: widgetTree,
          logs: logs,
        ),
    };
  }

  /// Resolve `finder`, execute `operation`, and return the action name.
  Future<String> _withUniqueMatch(
    Finder finder,
    Future<void> Function(FinderMatch match) operation, {
    required String actionName,
  }) async {
    final FinderMatch match = await _resolveUniqueMatch(
      finder,
      actionName: actionName,
    );
    await operation(match);
    return actionName;
  }

  /// Resolve a Finder and enforce first-version cardinality rules.
  Future<FinderMatch> _resolveUniqueMatch(
    Finder finder, {
    required String actionName,
  }) async {
    final List<FinderMatch> matches = await adapter.resolveFinder(finder);
    if (matches.isEmpty) {
      throw _StepFailureException(
        actionName: actionName,
        message: 'Finder matched no widgets.',
      );
    }
    if (matches.length > 1) {
      throw _StepFailureException(
        actionName: actionName,
        message: 'Finder matched multiple widgets.',
      );
    }
    return matches.single;
  }

  /// Poll a Finder until it has one unique match or the timeout expires.
  Future<String> _waitFor(Finder finder, {required Duration timeout}) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    while (true) {
      final List<FinderMatch> matches = await adapter.resolveFinder(finder);
      if (matches.length == 1) {
        return 'waitFor';
      }
      if (matches.length > 1) {
        throw _StepFailureException(
          actionName: 'waitFor',
          message: 'Finder matched multiple widgets.',
        );
      }
      if (stopwatch.elapsed >= timeout) {
        throw _StepFailureException(
          actionName: 'waitFor',
          message: 'Finder matched no widgets before timeout.',
        );
      }
      await Future<void>.delayed(_waitForPollInterval);
    }
  }

  /// Execute a scroll action, resolving its optional Finder when provided.
  Future<String> _executeScroll({
    required Finder? finder,
    required double deltaX,
    required double deltaY,
  }) async {
    FinderMatch? match;
    if (finder != null) {
      match = await _resolveUniqueMatch(finder, actionName: 'scroll');
    }
    await adapter.performScroll(match: match, deltaX: deltaX, deltaY: deltaY);
    return 'scroll';
  }

  /// Execute a capture action without persisting artifacts yet.
  ///
  /// Issue #6 and Issue #7 will write captured payloads through the Artifact
  /// Store. In this runner slice, capture only proves that the configured
  /// Runtime Adapter operations are invoked successfully.
  Future<String> _executeCapture({
    required bool screenshot,
    required bool snapshot,
    required bool widgetTree,
    required bool logs,
  }) async {
    if (screenshot) {
      await adapter.captureScreenshot();
    }
    if (snapshot) {
      await adapter.captureSnapshot();
    }
    if (widgetTree) {
      await adapter.captureWidgetTree();
    }
    if (logs) {
      await adapter.collectLogs();
    }
    return 'capture';
  }

  /// Write the JSON report artifact for this run.
  ///
  /// Args:
  /// `runArtifactWriter` is the writer scoped to the run directory.
  /// `report` is the final run report to serialize.
  void _writeReport(
    RunArtifactWriter runArtifactWriter,
    ScenarioRunReport report,
  ) {
    runArtifactWriter.writeRunReport(report.toJson());
  }

  /// Write metadata artifacts for all executed Steps.
  ///
  /// Args:
  /// `runArtifactWriter` is the writer scoped to the run directory.
  /// `steps` are the Step reports that were executed before the run ended.
  /// `artifacts` is the report artifact list that receives each Step metadata
  /// path.
  ///
  /// Example:
  /// A Step report with `index: 1` and `label: 'checkpoint'` writes
  /// `steps/0001_checkpoint.json` and appends that path to `artifacts`.
  void _writeStepMetadataArtifacts(
    RunArtifactWriter runArtifactWriter,
    List<StepRunReport> steps,
    List<ArtifactReport> artifacts,
  ) {
    for (final StepRunReport step in steps) {
      final ArtifactReport artifact = runArtifactWriter.writeStepMetadata(
        index: step.index,
        label: step.label,
        metadata: step.toJson(),
      );
      artifacts.add(artifact);
    }
  }
}

/// Overall status for one Scenario run.
enum ScenarioRunStatus { passed, failed }

/// Status for one executed Step.
enum StepStatus { passed, failed, skipped }

/// Report returned after one Scenario run.
///
/// It contains:
/// - Scenario metadata
/// - total status, start time, and duration
/// - the run directory path
/// - artifact path records
/// - one ordered entry for every executed Step
///
/// Example:
/// A failed run can have `status: failed`, a `failureReason`, and artifact
/// paths for `scenario.json`, Step metadata, and `run_report.json`.
class ScenarioRunReport {
  const ScenarioRunReport({
    required this.scenarioName,
    required this.scenarioDescription,
    required this.status,
    required this.startedAt,
    required this.durationMs,
    required this.steps,
    required this.runDirectoryPath,
    required this.artifacts,
    this.failureReason,
  });

  final String scenarioName;
  final String? scenarioDescription;
  final ScenarioRunStatus status;
  final DateTime startedAt;
  final int durationMs;
  final List<StepRunReport> steps;

  /// Path to the directory containing this run's artifacts.
  final String runDirectoryPath;

  /// File artifacts written relative to `runDirectoryPath`.
  final List<ArtifactReport> artifacts;

  /// Human-readable run-level failure reason.
  final String? failureReason;

  /// Convert this report to the JSON stored in `run_report.json`.
  ///
  /// Returns:
  /// A JSON-compatible map containing Scenario metadata, run status, timing,
  /// artifact paths, and Step results.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scenario': <String, Object?>{
        'name': scenarioName,
        if (scenarioDescription != null) 'description': scenarioDescription,
      },
      'status': status.name,
      'startedAt': startedAt.toIso8601String(),
      'durationMs': durationMs,
      'runDirectory': runDirectoryPath,
      if (failureReason != null) 'failureReason': failureReason,
      'artifacts': <Object?>[
        for (final ArtifactReport artifact in artifacts) artifact.toJson(),
      ],
      'steps': <Object?>[for (final StepRunReport step in steps) step.toJson()],
    };
  }
}

/// JSON-serializable report entry for one executed Step.
class StepRunReport {
  const StepRunReport({
    required this.index,
    required this.label,
    required this.action,
    required this.status,
    required this.durationMs,
    this.failureReason,
  });

  final int index;
  final String? label;
  final String action;
  final StepStatus status;
  final int durationMs;

  /// Human-readable failure reason when `status` is `failed`.
  final String? failureReason;

  /// Convert this Step entry to the first-version `run_report.json` shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      if (label != null) 'label': label,
      'action': action,
      'status': status.name,
      'durationMs': durationMs,
      if (failureReason != null) 'failureReason': failureReason,
    };
  }
}

/// Controlled Step failure that should be recorded in the run report.
class _StepFailureException implements Exception {
  const _StepFailureException({
    required this.actionName,
    required this.message,
  });

  final String actionName;
  final String message;
}
