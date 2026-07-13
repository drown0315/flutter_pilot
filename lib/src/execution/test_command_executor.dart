import 'dart:async';

import '../runtime/runtime_adapter_selector.dart';
import '../runtime/runtime_contract.dart';
import 'scenario_runner.dart';
import '../target/target_app_launch_progress_renderer.dart';
import '../target/target_app_launcher.dart';
import 'test_command_models.dart';
import '../target/test_device_discovery.dart';
import 'test_execution_session.dart';
import 'test_scenario_runner_factory.dart';

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
    TestExecutionSessionFactory? sessionFactory,
    this.runnerFactory = const DefaultTestScenarioRunnerFactory(),
    this.interruptSignals,
    this.launchHeartbeatTicks,
    this.launchClock = DateTime.now,
    this.recordingControllerFactory = defaultRecordingControllerFactory,
  }) : _sessionFactory = sessionFactory;

  final TestDeviceDiscovery deviceDiscovery;
  final TargetAppLauncher launcher;
  final TestExecutionSessionFactory? _sessionFactory;
  final TestScenarioRunnerFactory runnerFactory;
  final Stream<void>? interruptSignals;
  final Stream<void>? launchHeartbeatTicks;
  final TargetAppLaunchClock launchClock;
  final RecordingControllerFactory recordingControllerFactory;

  @override
  Future<ScenarioRunReport> run(
    TestCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    final bool recordingRequired = options.scenario.recording?.enabled == true;
    final TestExecutionSession session;
    try {
      session = await _effectiveSessionFactory.start(
        deviceSelector: options.device,
        flavor: options.flavor,
        target: options.target,
        recordingRequired: recordingRequired,
        launchHeartbeatEnabled: launchHeartbeatEnabled,
        onLaunchProgress: onLaunchProgress,
      );
    } on TestExecutionTargetDeviceException catch (error) {
      throw TestCommandException(message: error.message, exitCode: 64);
    } on TestExecutionLaunchException catch (error) {
      throw TestCommandException(
        message: error.message,
        exitCode: 1,
        alreadyRendered: error.alreadyRendered,
      );
    } on TestExecutionRecordingException catch (error) {
      throw TestCommandException(message: error.message, exitCode: 1);
    }

    bool completedNormally = false;
    try {
      final TestScenarioRunner runner;
      try {
        runner = runnerFactory.create(
          runtimeTarget: session.runtimeTarget,
          targetDevice: session.targetDevice,
          recordingController: recordingRequired
              ? session.recordingController
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
      final ScenarioRunReport report = await session.runWithInterrupt(
        runFuture,
      );
      completedNormally = true;
      return report;
    } on RuntimeOperationException catch (error) {
      throw TestCommandException(message: error.message, exitCode: 1);
    } finally {
      await _closeSession(session, reportFailure: completedNormally);
    }
  }

  Future<void> _closeSession(
    TestExecutionSession session, {
    required bool reportFailure,
  }) async {
    try {
      await session.close();
    } on TestExecutionRecordingException catch (error) {
      if (reportFailure) {
        throw TestCommandException(message: error.message, exitCode: 1);
      }
    }
  }

  TestExecutionSessionFactory get _effectiveSessionFactory {
    return _sessionFactory ??
        DefaultTestExecutionSessionFactory(
          deviceDiscovery: deviceDiscovery,
          launcher: launcher,
          interruptSignals: interruptSignals,
          launchHeartbeatTicks: launchHeartbeatTicks,
          launchClock: launchClock,
          recordingControllerFactory: recordingControllerFactory,
        );
  }
}
