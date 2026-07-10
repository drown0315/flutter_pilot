import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;

import '../artifacts/artifact_store.dart';
import '../reports/project_run_report.dart';
import '../recording/screen_recorder_recording_controller.dart';
import '../runtime/runtime_adapter_selector.dart';
import '../scenario/project_scenario_discovery.dart';
import 'scenario_runner.dart';
import '../target/target_app_launch_progress_renderer.dart';
import '../target/target_app_launcher.dart';
import 'test_command_models.dart';
import '../target/test_device_discovery.dart';
import 'test_execution_session.dart';
import 'test_scenario_runner_factory.dart';

/// Executes a validated Project Run selected by `test`.
abstract interface class ProjectRunExecutor {
  /// Run the Project Scenarios described by [options].
  ///
  /// `onLaunchProgress`, when provided, receives the batch-level Target App
  /// Launch Progress events before any Project Scenario executes.
  Future<ProjectRunResult> run(
    ProjectRunOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  });
}

/// Default Project Run executor for launch reuse and batch Scenario execution.
class DefaultProjectRunExecutor implements ProjectRunExecutor {
  const DefaultProjectRunExecutor({
    this.deviceDiscovery = const DefaultTestDeviceDiscovery(),
    this.launcher = const TargetAppLauncher(),
    TestExecutionSessionFactory? sessionFactory,
    this.runnerFactory = const DefaultTestScenarioRunnerFactory(),
    this.interruptSignals,
    this.outputDirectory,
    this.clock = DateTime.now,
    this.launchHeartbeatTicks,
  }) : _sessionFactory = sessionFactory;

  /// Discovers Flutter and Recording Devices before app launch when needed.
  final TestDeviceDiscovery deviceDiscovery;

  /// Starts the Target App Package and exposes hot restart.
  final TargetAppLauncher launcher;

  /// Starts the shared Test Execution Session for this Project Run.
  final TestExecutionSessionFactory? _sessionFactory;

  /// Creates Scenario runners for each selected Project Scenario.
  final TestScenarioRunnerFactory runnerFactory;

  /// Optional interrupt stream used by tests and Ctrl-C handling.
  final Stream<void>? interruptSignals;

  /// Directory where Project Run artifacts are written.
  final Directory? outputDirectory;

  /// Clock used for report timestamps, durations, and tests.
  final TargetAppLaunchClock clock;

  /// Optional heartbeat stream used by launch progress tests.
  final Stream<void>? launchHeartbeatTicks;

  @override
  Future<ProjectRunResult> run(
    ProjectRunOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    final DateTime startedAt = clock().toUtc();
    final ProjectRunArtifactWriter projectRunWriter = RunArtifactStore(
      outputDirectory ?? Directory.current,
    ).createProjectRun(startedAt: startedAt);
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<ProjectScenarioRunReport> scenarioResults =
        <ProjectScenarioRunReport>[];
    ProjectRunEnvironmentFailure? environmentFailure;
    final bool recordingRequired = options.scenarios.any(
      (ProjectScenarioFile file) => file.scenario.recording?.enabled == true,
    );
    TestExecutionSession? session;
    try {
      session = await _effectiveSessionFactory.start(
        deviceSelector: options.device,
        flavor: options.flavor,
        target: options.target,
        recordingRequired: recordingRequired,
        launchHeartbeatEnabled: launchHeartbeatEnabled,
        onLaunchProgress: onLaunchProgress,
      );
      for (int index = 0; index < options.scenarios.length; index++) {
        final ProjectScenarioFile scenarioFile = options.scenarios[index];
        if (index > 0) {
          try {
            await session.hotRestart();
          } on TestExecutionLaunchException catch (error) {
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
        final TestScenarioRunner runner;
        try {
          runner = runnerFactory.create(
            runtimeTarget: session.runtimeTarget,
            targetDevice: session.targetDevice,
            recordingController:
                scenarioFile.scenario.recording?.enabled == true
                ? ScreenRecorderRecordingController(
                    recorder: screen_recorder.ScreenRecorder.defaultRecorder(),
                    deviceSelector: session.targetDevice!.id,
                    outputDirectory: Directory.current,
                  )
                : null,
          );
        } on RuntimeAdapterSelectionException catch (error) {
          environmentFailure = ProjectRunEnvironmentFailure(
            phase: ProjectRunEnvironmentFailurePhase.runtimeSelection,
            message: error.message,
          );
          break;
        }
        final Future<ScenarioRunReport> runFuture = runner.run(
          scenarioFile.scenario,
          runArtifactWriter: childRun,
          onProgress: onProgress,
        );
        final ScenarioRunReport scenarioReport = await session.runWithInterrupt(
          runFuture,
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
    } on TestExecutionTargetDeviceException catch (error) {
      environmentFailure = ProjectRunEnvironmentFailure(
        phase: ProjectRunEnvironmentFailurePhase.targetDeviceResolution,
        message: error.message,
      );
    } on TestExecutionLaunchException catch (error) {
      environmentFailure = ProjectRunEnvironmentFailure(
        phase: ProjectRunEnvironmentFailurePhase.launch,
        message: error.message,
      );
    } on TestCommandException catch (error) {
      if (error.exitCode == 130) {
        rethrow;
      }
      environmentFailure = ProjectRunEnvironmentFailure(
        phase: ProjectRunEnvironmentFailurePhase.validation,
        message: error.message,
      );
    } finally {
      stopwatch.stop();
      await session?.close();
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
    return ProjectRunResult(
      passed: projectStatus == ProjectRunStatus.passed,
      status: projectStatus,
      projectRunReportPath: p.join(
        projectRunWriter.runDirectory.path,
        'project_run_report.json',
      ),
      scenarioReports: <ProjectRunScenarioOutputReport>[
        for (final ProjectScenarioRunReport scenarioReport in scenarioResults)
          ProjectRunScenarioOutputReport(
            scenarioPath: scenarioReport.scenarioPath,
            status: scenarioReport.status,
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

  TestExecutionSessionFactory get _effectiveSessionFactory {
    return _sessionFactory ??
        DefaultTestExecutionSessionFactory(
          deviceDiscovery: deviceDiscovery,
          launcher: launcher,
          interruptSignals: interruptSignals,
          launchHeartbeatTicks: launchHeartbeatTicks,
          launchClock: clock,
        );
  }
}
