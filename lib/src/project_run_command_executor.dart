import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;

import 'artifacts/artifact_store.dart';
import 'project_scenario_discovery.dart';
import 'project_run_report.dart';
import 'recording/screen_recorder_recording_controller.dart';
import 'runtime/runtime_adapter_selector.dart';
import 'runtime/runtime_contract.dart';
import 'scenario_runner.dart';
import 'target_app_launch_progress_renderer.dart';
import 'target_app_launcher.dart';
import 'target_device.dart';
import 'test_command_models.dart';
import 'test_device_discovery.dart';
import 'test_scenario_runner_factory.dart';
import 'test_target_device_selection.dart';

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
    void Function(StepProgressEvent event)? onProgress,
  });
}

/// Default Project Run executor for launch reuse and batch Scenario execution.
class DefaultProjectRunCommandExecutor implements ProjectRunCommandExecutor {
  const DefaultProjectRunCommandExecutor({
    this.deviceDiscovery = const DefaultTestDeviceDiscovery(),
    this.launcher = const TargetAppLauncher(),
    this.runnerFactory = const DefaultTestScenarioRunnerFactory(),
    this.interruptSignals,
    this.outputDirectory,
    this.clock = DateTime.now,
    this.launchHeartbeatTicks,
  });

  /// Discovers Flutter and Recording Devices before app launch when needed.
  final TestDeviceDiscovery deviceDiscovery;

  /// Starts the Target App Package and exposes hot restart.
  final TargetAppLauncher launcher;

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
  Future<ProjectRunCommandReport> run(
    ProjectRunCommandOptions options, {
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
    TargetAppLaunch? launch;
    TargetDevice? targetDevice;
    final bool recordingRequired = options.scenarios.any(
      (ProjectScenarioFile file) => file.scenario.recording?.enabled == true,
    );
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
        environmentFailure = ProjectRunEnvironmentFailure(
          phase: ProjectRunEnvironmentFailurePhase.targetDeviceResolution,
          message: error.message,
        );
      } on DeviceDiscoveryException catch (error) {
        environmentFailure = ProjectRunEnvironmentFailure(
          phase: ProjectRunEnvironmentFailurePhase.targetDeviceResolution,
          message: error.message,
        );
      }
    }
    if (environmentFailure != null) {
      stopwatch.stop();
      final ProjectRunReport projectReport =
          ProjectRunReport.environmentFailure(
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
        passed: false,
        status: ProjectRunStatus.environmentFailed,
        projectRunReportPath: p.join(
          projectRunWriter.runDirectory.path,
          'project_run_report.json',
        ),
        scenarioReports: const <ProjectRunScenarioOutputReport>[],
      );
    }
    final TargetAppLaunchChoices launchChoices = TargetAppLaunchChoices(
      targetDevice: targetDevice,
      selectionReason: targetDeviceSelectionReason(
        deviceSelector: options.device,
        recordingRequired: recordingRequired,
      ),
      flavor: options.flavor,
      target: options.target,
    );
    final TargetAppLaunchStartedEvent launchStartedEvent =
        TargetAppLaunchStartedEvent(
          startedAt: startedAt,
          choices: launchChoices,
        );
    onLaunchProgress?.call(launchStartedEvent);
    TargetAppLaunchHeartbeat? launchHeartbeat;
    if (onLaunchProgress != null && launchHeartbeatEnabled) {
      launchHeartbeat = TargetAppLaunchHeartbeat(
        ticks:
            launchHeartbeatTicks ??
            Stream<void>.periodic(const Duration(seconds: 10)),
        onProgress: onLaunchProgress,
        clock: clock,
      );
      launchHeartbeat.start(launchStartedEvent);
    }
    try {
      launch = await launcher.launch(
        TargetAppLaunchCommand(
          flavor: options.flavor,
          target: options.target,
          deviceId: targetDevice?.id,
        ),
      );
      onLaunchProgress?.call(
        TargetAppLaunchSucceededEvent(
          startedAt: startedAt,
          finishedAt: clock().toUtc(),
          choices: launchChoices,
        ),
      );
      await launchHeartbeat?.stop();
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
        final TestScenarioRunner runner;
        try {
          runner = runnerFactory.create(
            runtimeTarget: RuntimeTarget(
              vmServiceUri: launch.runtimeTargetUri,
              deviceId: targetDevice?.id ?? launch.deviceId,
            ),
            targetDevice: targetDevice,
            recordingController:
                scenarioFile.scenario.recording?.enabled == true
                ? ScreenRecorderRecordingController(
                    recorder: screen_recorder.ScreenRecorder.defaultRecorder(),
                    deviceSelector: targetDevice!.id,
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
        final ScenarioRunReport scenarioReport =
            await _runScenarioWithInterrupt(runFuture);
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
      await launchHeartbeat?.stop();
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
      await launchHeartbeat?.stop();
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

  Future<ScenarioRunReport> _runScenarioWithInterrupt(
    Future<ScenarioRunReport> runFuture,
  ) async {
    StreamSubscription<void>? interruptSub;
    try {
      final Completer<ScenarioRunReport> interruptCompleter =
          Completer<ScenarioRunReport>();
      interruptSub =
          (interruptSignals ??
                  ProcessSignal.sigint.watch().map<void>((ProcessSignal _) {}))
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
  }
}
