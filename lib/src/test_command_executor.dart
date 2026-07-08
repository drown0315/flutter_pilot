import 'dart:async';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;

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
      selectionReason: targetDeviceSelectionReason(
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
      final TestScenarioRunner runner;
      try {
        runner = runnerFactory.create(
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
      } on RuntimeAdapterSelectionException catch (error) {
        throw TestCommandException(message: error.message, exitCode: 1);
      }
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
}
