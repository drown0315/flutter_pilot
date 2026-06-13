import 'dart:io';

import 'artifacts/artifact_store.dart';
import 'diagnostic_reducer.dart';
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

  /// Execute Scenario Steps and write a run report.
  ///
  /// Args:
  /// `scenario` is the parsed Scenario to replay through the Runtime Adapter.
  /// Its name is used in the run directory name, and its Steps determine which
  /// Runtime Adapter operations are called.
  /// `stopPoint` optionally stops after a selected 1-based Step number or Step
  /// label. Later Steps stay in the report with `skipped` status.
  ///
  /// Returns:
  /// A `ScenarioRunReport` containing Scenario metadata, run status, elapsed
  /// time, the run directory path, artifact paths, and ordered Step results.
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
  }) async {
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
        printedDiagnostics: const <PrintedDiagnostic>[],
        diagnosticSummary: null,
      );
    }

    bool failed = false;
    String? failureReason = await _executeSteps(
      _stepsToExecute(scenario, stopPoint),
      steps,
      runArtifactWriter,
    );
    if (failureReason != null) {
      failed = true;
    }

    if (!failed) {
      _addSkippedSteps(allSteps: scenario.steps, reports: steps);
    }

    List<PrintedDiagnostic> printedDiagnostics = const <PrintedDiagnostic>[];
    DiagnosticSummary? diagnosticSummary;
    if (!failed) {
      try {
        printedDiagnostics = await _capturePrintedDiagnostics(printDiagnostics);
        diagnosticSummary = _reducePrintedDiagnostics(printedDiagnostics);
      } on RuntimeOperationException catch (error) {
        failed = true;
        failureReason = error.message;
        printedDiagnostics = const <PrintedDiagnostic>[];
        diagnosticSummary = null;
      }
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
      printedDiagnostics: printedDiagnostics,
      diagnosticSummary: diagnosticSummary,
    );
  }

  /// Return the Step prefix selected by an optional run stop point.
  ///
  /// Args:
  /// `scenario` provides the full ordered Step list.
  /// `stopPoint` selects the final Step to execute. When omitted, every Step is
  /// executed.
  ///
  /// Returns:
  /// The ordered Steps that should execute before later Steps are marked
  /// skipped in the report.
  List<ScenarioStep> _stepsToExecute(
    Scenario scenario,
    RunStopPoint? stopPoint,
  ) {
    if (stopPoint == null) {
      return scenario.steps;
    }
    return switch (stopPoint) {
      StepNumberStopPoint(:final int stepNumber) =>
        scenario.sliceThroughStepNumber(stepNumber).steps,
      StepLabelStopPoint(:final String label) =>
        scenario.sliceThroughStepLabel(label).steps,
    };
  }

  /// Append skipped reports for Steps after the last executed Step.
  ///
  /// Args:
  /// `allSteps` is the full Scenario Step list.
  /// `reports` already contains the executed Step reports and receives skipped
  /// entries for any later Steps.
  void _addSkippedSteps({
    required List<ScenarioStep> allSteps,
    required List<StepRunReport> reports,
  }) {
    final Set<int> reportedIndexes = <int>{
      for (final StepRunReport report in reports) report.index,
    };
    for (final ScenarioStep step in allSteps) {
      if (reportedIndexes.contains(step.index)) {
        continue;
      }
      reports.add(
        StepRunReport(
          index: step.index,
          label: step.label,
          action: _actionName(step.action),
          status: StepStatus.skipped,
          durationMs: 0,
        ),
      );
    }
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
    RunArtifactWriter runArtifactWriter,
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
          runArtifactWriter,
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
        final _FailureDiagnosticResult diagnostics =
            await _collectFailureArtifacts(
              step: step,
              runArtifactWriter: runArtifactWriter,
            );
        reports.add(
          StepRunReport(
            index: step.index,
            label: step.label,
            action: _actionName(step.action),
            status: StepStatus.failed,
            durationMs: activeStepStopwatch?.elapsedMilliseconds ?? 0,
            artifacts: diagnostics.artifacts,
            failureReason: error.message,
            diagnosticFailureReason: diagnostics.failureReason,
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
    required List<PrintedDiagnostic> printedDiagnostics,
    DiagnosticSummary? diagnosticSummary,
  }) {
    final List<ArtifactReport> artifacts = <ArtifactReport>[
      const ArtifactReport(type: ArtifactType.scenario, path: 'scenario.json'),
    ];
    _addStepCaptureArtifacts(steps, artifacts);
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
      printedDiagnostics: printedDiagnostics,
      diagnosticSummary: diagnosticSummary,
    );
    _writeReport(runArtifactWriter, report);
    return report;
  }

  /// Execute one Step and return its report entry.
  Future<StepRunReport> _executeStep(
    ScenarioStep step,
    Stopwatch stopwatch,
    RunArtifactWriter runArtifactWriter,
  ) async {
    final String actionName = _actionName(step.action);
    try {
      final _ActionExecutionResult result = await _executeAction(
        step,
        runArtifactWriter,
      );
      stopwatch.stop();
      return StepRunReport(
        index: step.index,
        label: step.label,
        action: actionName,
        status: result.failureReason == null
            ? StepStatus.passed
            : StepStatus.failed,
        durationMs: stopwatch.elapsedMilliseconds,
        artifacts: result.artifacts,
        failureReason: result.failureReason,
      );
    } on _StepFailureException catch (error) {
      stopwatch.stop();
      final _FailureDiagnosticResult diagnostics =
          await _collectFailureArtifacts(
            step: step,
            runArtifactWriter: runArtifactWriter,
          );
      return StepRunReport(
        index: step.index,
        label: step.label,
        action: error.actionName,
        status: StepStatus.failed,
        durationMs: stopwatch.elapsedMilliseconds,
        artifacts: diagnostics.artifacts,
        failureReason: error.message,
        diagnosticFailureReason: diagnostics.failureReason,
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
  Future<_ActionExecutionResult> _executeAction(
    ScenarioStep step,
    RunArtifactWriter runArtifactWriter,
  ) async {
    final StepAction action = step.action;
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
          step: step,
          runArtifactWriter: runArtifactWriter,
          screenshot: screenshot,
          snapshot: snapshot,
          widgetTree: widgetTree,
          logs: logs,
          purpose: ArtifactPurpose.capture,
        ),
    };
  }

  /// Resolve `finder`, execute `operation`, and return no Step artifacts.
  Future<_ActionExecutionResult> _withUniqueMatch(
    Finder finder,
    Future<void> Function(FinderMatch match) operation, {
    required String actionName,
  }) async {
    final FinderMatch match = await _resolveUniqueMatch(
      finder,
      actionName: actionName,
    );
    await operation(match);
    return const _ActionExecutionResult();
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
  Future<_ActionExecutionResult> _waitFor(
    Finder finder, {
    required Duration timeout,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    while (true) {
      final List<FinderMatch> matches = await adapter.resolveFinder(finder);
      if (matches.length == 1) {
        return const _ActionExecutionResult();
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
  Future<_ActionExecutionResult> _executeScroll({
    required Finder? finder,
    required double deltaX,
    required double deltaY,
  }) async {
    FinderMatch? match;
    if (finder != null) {
      match = await _resolveUniqueMatch(finder, actionName: 'scroll');
    }
    await adapter.performScroll(match: match, deltaX: deltaX, deltaY: deltaY);
    return const _ActionExecutionResult();
  }

  /// Execute a capture action and write Step-owned capture artifacts.
  ///
  /// Each requested capture is attempted independently. A failed capture marks
  /// the Step failed, but does not discard artifacts already written by earlier
  /// captures or prevent later requested captures from being attempted.
  Future<_ActionExecutionResult> _executeCapture({
    required ScenarioStep step,
    required RunArtifactWriter runArtifactWriter,
    required bool screenshot,
    required bool snapshot,
    required bool widgetTree,
    required bool logs,
    required ArtifactPurpose purpose,
  }) async {
    final List<ArtifactReport> artifacts = <ArtifactReport>[];
    final List<String> failures = <String>[];
    if (screenshot) {
      try {
        final ScreenshotCapture capture = await adapter.captureScreenshot();
        artifacts.add(
          runArtifactWriter.writeScreenshot(
            index: step.index,
            label: step.label,
            bytes: capture.bytes,
            mimeType: capture.mimeType,
            purpose: purpose,
          ),
        );
      } on RuntimeOperationException catch (error) {
        failures.add(error.message);
      }
    }
    if (snapshot) {
      try {
        final SnapshotCapture capture = await adapter.captureSnapshot();
        artifacts.add(
          runArtifactWriter.writeSnapshot(
            index: step.index,
            label: step.label,
            data: capture.data,
            purpose: purpose,
          ),
        );
      } on RuntimeOperationException catch (error) {
        failures.add(error.message);
      }
    }
    if (widgetTree) {
      try {
        await adapter.captureWidgetTree();
      } on RuntimeOperationException catch (error) {
        failures.add(error.message);
      }
    }
    if (logs) {
      try {
        final LogsCapture capture = await adapter.collectLogs();
        artifacts.add(
          runArtifactWriter.writeLogs(
            index: step.index,
            label: step.label,
            data: capture.data,
            purpose: purpose,
          ),
        );
      } on RuntimeOperationException catch (error) {
        failures.add(error.message);
      }
    }
    return _ActionExecutionResult(
      artifacts: artifacts,
      failureReason: failures.isEmpty ? null : failures.join('; '),
    );
  }

  /// Collect the default diagnostic bundle for a failed Step.
  ///
  /// Args:
  /// `step` is the Step that already failed.
  /// `runArtifactWriter` writes successful diagnostic captures into the current
  /// run directory.
  ///
  /// Returns:
  /// Artifact records for successful screenshot, Snapshot, and Logs captures.
  /// Widget Tree is not requested by default.
  Future<_FailureDiagnosticResult> _collectFailureArtifacts({
    required ScenarioStep step,
    required RunArtifactWriter runArtifactWriter,
  }) async {
    final _ActionExecutionResult result = await _executeCapture(
      step: step,
      runArtifactWriter: runArtifactWriter,
      screenshot: true,
      snapshot: true,
      widgetTree: false,
      logs: true,
      purpose: ArtifactPurpose.failure,
    );
    return _FailureDiagnosticResult(
      artifacts: result.artifacts,
      failureReason: result.failureReason,
    );
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

  /// Add Step capture artifact records to the run-level artifact list.
  ///
  /// Args:
  /// `steps` are the executed Step reports.
  /// `artifacts` is the report artifact list that receives each Step-owned
  /// screenshot and Snapshot path.
  void _addStepCaptureArtifacts(
    List<StepRunReport> steps,
    List<ArtifactReport> artifacts,
  ) {
    for (final StepRunReport step in steps) {
      artifacts.addAll(step.artifacts);
    }
  }

  /// Capture diagnostic payloads requested for terminal printing.
  ///
  /// Args:
  /// `printDiagnostics` selects the Runtime Adapter captures to perform after
  /// the stopped Step has completed.
  ///
  /// Returns:
  /// The captured payloads in stable order: Snapshot, Widget Tree, then errors.
  Future<List<PrintedDiagnostic>> _capturePrintedDiagnostics(
    Set<PrintDiagnostic> printDiagnostics,
  ) async {
    final List<PrintedDiagnostic> printedDiagnostics = <PrintedDiagnostic>[];
    for (final PrintDiagnostic printDiagnostic in PrintDiagnostic.fixedOrder) {
      if (!printDiagnostics.contains(printDiagnostic)) {
        continue;
      }
      printedDiagnostics.add(await _capturePrintedDiagnostic(printDiagnostic));
    }
    return printedDiagnostics;
  }

  /// Capture one diagnostic payload for terminal printing.
  Future<PrintedDiagnostic> _capturePrintedDiagnostic(
    PrintDiagnostic printDiagnostic,
  ) async {
    return switch (printDiagnostic) {
      PrintDiagnostic.snapshot => PrintedDiagnostic(
        type: PrintDiagnostic.snapshot,
        data: (await adapter.captureSnapshot()).data,
      ),
      PrintDiagnostic.widgetTree => PrintedDiagnostic(
        type: PrintDiagnostic.widgetTree,
        data: (await adapter.captureWidgetTree()).data,
      ),
      PrintDiagnostic.errors => PrintedDiagnostic(
        type: PrintDiagnostic.errors,
        data: (await adapter.collectLogs()).data,
      ),
    };
  }

  /// Reduce printable diagnostics into the compact agent-facing summary.
  DiagnosticSummary? _reducePrintedDiagnostics(
    List<PrintedDiagnostic> printedDiagnostics,
  ) {
    if (printedDiagnostics.isEmpty) {
      return null;
    }

    Object? snapshot;
    Object? widgetTree;
    Object? logs;
    for (final PrintedDiagnostic diagnostic in printedDiagnostics) {
      switch (diagnostic.type) {
        case PrintDiagnostic.snapshot:
          snapshot = diagnostic.data;
        case PrintDiagnostic.widgetTree:
          widgetTree = diagnostic.data;
        case PrintDiagnostic.errors:
          logs = diagnostic.data;
      }
    }
    return DiagnosticReducer.reduce(
      snapshot: snapshot,
      widgetTree: widgetTree,
      logs: logs,
    );
  }
}

/// Overall status for one Scenario run.
enum ScenarioRunStatus { passed, failed }

/// Status for one executed Step.
enum StepStatus { passed, failed, skipped }

/// Diagnostic payload that can be printed after `--until` completes.
enum PrintDiagnostic {
  snapshot,
  widgetTree,
  errors;

  /// Stable terminal and report output order for requested diagnostics.
  static const List<PrintDiagnostic> fixedOrder = <PrintDiagnostic>[
    snapshot,
    widgetTree,
    errors,
  ];
}

/// Stop point for a partial Scenario run.
///
/// It contains either:
/// - a 1-based Step number
/// - a Step label
///
/// Example:
/// `RunStopPoint.stepNumber(3)` runs through Step 3 and reports later Steps as
/// skipped.
sealed class RunStopPoint {
  const RunStopPoint();

  const factory RunStopPoint.stepNumber(int stepNumber) = StepNumberStopPoint;

  const factory RunStopPoint.stepLabel(String label) = StepLabelStopPoint;
}

/// Stop point that selects the final executed Step by its 1-based index.
class StepNumberStopPoint extends RunStopPoint {
  const StepNumberStopPoint(this.stepNumber);

  final int stepNumber;
}

/// Stop point that selects the final executed Step by its label.
class StepLabelStopPoint extends RunStopPoint {
  const StepLabelStopPoint(this.label);

  final String label;
}

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
    this.printedDiagnostics = const <PrintedDiagnostic>[],
    this.diagnosticSummary,
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

  /// Diagnostic data requested for terminal output after a stopped Step.
  final List<PrintedDiagnostic> printedDiagnostics;

  /// Compact agent-facing summary reduced from printed diagnostics.
  final DiagnosticSummary? diagnosticSummary;

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
      if (printedDiagnostics.isNotEmpty)
        'printedDiagnostics': <Object?>[
          for (final PrintedDiagnostic diagnostic in printedDiagnostics)
            diagnostic.toJson(),
        ],
      if (diagnosticSummary != null)
        'diagnosticSummary': diagnosticSummary!.toJson(),
      'artifacts': <Object?>[
        for (final ArtifactReport artifact in artifacts) artifact.toJson(),
      ],
      'steps': <Object?>[for (final StepRunReport step in steps) step.toJson()],
    };
  }
}

/// Runtime diagnostic selected for stdout printing by the CLI.
class PrintedDiagnostic {
  const PrintedDiagnostic({required this.type, required this.data});

  final PrintDiagnostic type;
  final Object data;

  /// Convert the printed diagnostic to a JSON-compatible report object.
  Map<String, Object?> toJson() {
    return <String, Object?>{'type': type.name, 'data': data};
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
    this.artifacts = const <ArtifactReport>[],
    this.failureReason,
    this.diagnosticFailureReason,
  });

  final int index;
  final String? label;
  final String action;
  final StepStatus status;
  final int durationMs;

  /// Human-readable failure reason when `status` is `failed`.
  final String? failureReason;

  /// Human-readable failure from automatic failure diagnostic capture.
  ///
  /// This field is separate from `failureReason` so the report preserves the
  /// Step's primary failure while still recording screenshot, Snapshot, or Logs
  /// capture failures that happened while building the failure bundle.
  final String? diagnosticFailureReason;

  /// Files produced by this Step, relative to the run directory.
  final List<ArtifactReport> artifacts;

  /// Convert this Step entry to the first-version `run_report.json` shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      if (label != null) 'label': label,
      'action': action,
      'status': status.name,
      'durationMs': durationMs,
      if (artifacts.isNotEmpty)
        'artifacts': <Object?>[
          for (final ArtifactReport artifact in artifacts) artifact.toJson(),
        ],
      if (failureReason != null) 'failureReason': failureReason,
      if (diagnosticFailureReason != null)
        'diagnosticFailureReason': diagnosticFailureReason,
    };
  }
}

/// Result from collecting automatic diagnostics after a Step fails.
///
/// It contains:
/// - artifacts that were successfully written
/// - an optional failure reason for diagnostic captures that failed
///
/// Example:
/// If screenshot capture fails but Snapshot and Logs succeed, `artifacts`
/// contains the Snapshot and Logs paths, and `failureReason` contains the
/// screenshot failure message.
class _FailureDiagnosticResult {
  const _FailureDiagnosticResult({
    required this.artifacts,
    required this.failureReason,
  });

  final List<ArtifactReport> artifacts;
  final String? failureReason;
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

/// Result from executing one action inside a Step.
///
/// It carries any Step-owned artifact records and an optional failure reason.
/// Capture uses this to report partial success without throwing away files that
/// were already written.
class _ActionExecutionResult {
  const _ActionExecutionResult({
    this.artifacts = const <ArtifactReport>[],
    this.failureReason,
  });

  final List<ArtifactReport> artifacts;
  final String? failureReason;
}
