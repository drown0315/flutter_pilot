import 'dart:async';
import 'dart:io';

import 'runtime/runtime_contract.dart';
import 'target_app_launch_progress_renderer.dart';
import 'target_app_launcher.dart';
import 'target_device.dart';
import 'test_command_models.dart';
import 'test_device_discovery.dart';
import 'test_target_device_selection.dart';

/// Starts the shared execution lifetime used by `flutter_pilot test`.
abstract interface class TestExecutionSessionFactory {
  /// Launch the Target App Package and return a session ready for Scenarios.
  ///
  /// `deviceSelector`, `flavor`, and `target` are command-line inputs.
  /// `recordingRequired` forces Target Device resolution before launch so
  /// Scenario Recording can use the same device. `onLaunchProgress` receives
  /// Target App Launch Progress events when human-readable output is enabled.
  Future<TestExecutionSession> start({
    required String? deviceSelector,
    required String? flavor,
    required String? target,
    required bool recordingRequired,
    required bool launchHeartbeatEnabled,
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
  });
}

/// Shared Target App lifetime for one `flutter_pilot test` execution.
abstract interface class TestExecutionSession {
  /// Runtime Target selected from the launched Target App Package.
  RuntimeTarget get runtimeTarget;

  /// Target Device selected before launch, when Flutter Pilot selected one.
  TargetDevice? get targetDevice;

  /// Run `operation` and complete with interruption when Ctrl-C is received.
  Future<T> runWithInterrupt<T>(Future<T> operation);

  /// Request a hot restart from the launched Target App Package.
  Future<void> hotRestart();

  /// Clean up the launched Target App Package.
  Future<void> close();
}

/// Failure from the shared Test Execution Session lifecycle.
sealed class TestExecutionSessionException implements Exception {
  /// Creates a lifecycle failure with a user-facing message.
  const TestExecutionSessionException(this.message);

  /// Human-readable failure reason.
  final String message;
}

/// Failure raised when Target Device resolution cannot prepare launch inputs.
final class TestExecutionTargetDeviceException
    extends TestExecutionSessionException {
  /// Creates a Target Device lifecycle failure.
  const TestExecutionTargetDeviceException(super.message);
}

/// Failure raised when the Target App Package cannot launch or be controlled.
final class TestExecutionLaunchException extends TestExecutionSessionException {
  /// Creates a Target App launch lifecycle failure.
  const TestExecutionLaunchException(
    super.message, {
    this.stderrLines = const <String>[],
    this.alreadyRendered = false,
  });

  /// Flutter stderr lines captured during launch.
  final List<String> stderrLines;

  /// Whether Target App Launch Progress already rendered the failure.
  final bool alreadyRendered;
}

/// Default Test Execution Session factory for the `test` command.
class DefaultTestExecutionSessionFactory
    implements TestExecutionSessionFactory {
  /// Creates a factory with injectable launch, discovery, and clock boundaries.
  const DefaultTestExecutionSessionFactory({
    this.deviceDiscovery = const DefaultTestDeviceDiscovery(),
    this.launcher = const TargetAppLauncher(),
    this.interruptSignals,
    this.launchHeartbeatTicks,
    this.launchClock = DateTime.now,
  });

  /// Discovers Flutter and Recording Devices before launch when needed.
  final TestDeviceDiscovery deviceDiscovery;

  /// Starts and controls the Target App Package.
  final TargetAppLauncher launcher;

  /// Optional interrupt stream used by tests and Ctrl-C handling.
  final Stream<void>? interruptSignals;

  /// Optional heartbeat stream used by launch progress tests.
  final Stream<void>? launchHeartbeatTicks;

  /// Clock used for Target App Launch Progress events.
  final TargetAppLaunchClock launchClock;

  @override
  Future<TestExecutionSession> start({
    required String? deviceSelector,
    required String? flavor,
    required String? target,
    required bool recordingRequired,
    required bool launchHeartbeatEnabled,
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
  }) async {
    final TargetDevice? targetDevice = await _resolveTargetDevice(
      deviceSelector: deviceSelector,
      recordingRequired: recordingRequired,
    );
    final DateTime launchStartedAt = launchClock();
    final TargetAppLaunchChoices launchChoices = TargetAppLaunchChoices(
      targetDevice: targetDevice,
      selectionReason: targetDeviceSelectionReason(
        deviceSelector: deviceSelector,
        recordingRequired: recordingRequired,
      ),
      flavor: flavor,
      target: target,
    );
    final TargetAppLaunchStartedEvent startedEvent =
        TargetAppLaunchStartedEvent(
          startedAt: launchStartedAt,
          choices: launchChoices,
        );
    onLaunchProgress?.call(startedEvent);
    TargetAppLaunchHeartbeat? launchHeartbeat;
    if (onLaunchProgress != null && launchHeartbeatEnabled) {
      launchHeartbeat = TargetAppLaunchHeartbeat(
        ticks:
            launchHeartbeatTicks ??
            Stream<void>.periodic(const Duration(seconds: 10)),
        onProgress: onLaunchProgress,
        clock: launchClock,
      );
      launchHeartbeat.start(startedEvent);
    }
    try {
      final TargetAppLaunch launch = await launcher.launch(
        TargetAppLaunchCommand(
          deviceId: targetDevice?.id,
          flavor: flavor,
          target: target,
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
      return _DefaultTestExecutionSession(
        launch: launch,
        targetDevice: targetDevice,
        interruptSignals: interruptSignals,
      );
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
      throw TestExecutionLaunchException(
        '${error.message}$stderrContext',
        stderrLines: error.stderrLines,
        alreadyRendered: onLaunchProgress != null,
      );
    }
  }

  Future<TargetDevice?> _resolveTargetDevice({
    required String? deviceSelector,
    required bool recordingRequired,
  }) async {
    if (deviceSelector == null && !recordingRequired) {
      return null;
    }
    try {
      final List<FlutterDevice> flutterDevices = await deviceDiscovery
          .listFlutterDevices();
      final List<RecordingDeviceIdentity> recordingDevices = recordingRequired
          ? await deviceDiscovery.listRecordingDevices()
          : const <RecordingDeviceIdentity>[];
      return TargetDeviceResolver.resolve(
        selector: deviceSelector,
        recordingRequired: recordingRequired,
        flutterDevices: flutterDevices,
        recordingDevices: recordingDevices,
      );
    } on TargetDeviceResolutionException catch (error) {
      throw TestExecutionTargetDeviceException(error.message);
    } on DeviceDiscoveryException catch (error) {
      throw TestExecutionTargetDeviceException(error.message);
    }
  }
}

class _DefaultTestExecutionSession implements TestExecutionSession {
  _DefaultTestExecutionSession({
    required TargetAppLaunch launch,
    required this.targetDevice,
    required this.interruptSignals,
  }) : _launch = launch,
       runtimeTarget = RuntimeTarget(
         vmServiceUri: launch.runtimeTargetUri,
         deviceId: targetDevice?.id ?? launch.deviceId,
       );

  final TargetAppLaunch _launch;
  final Stream<void>? interruptSignals;

  @override
  final RuntimeTarget runtimeTarget;

  @override
  final TargetDevice? targetDevice;

  @override
  Future<T> runWithInterrupt<T>(Future<T> operation) async {
    StreamSubscription<void>? interruptSub;
    try {
      final Completer<T> interruptCompleter = Completer<T>();
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
      return await Future.any(<Future<T>>[
        operation,
        interruptCompleter.future,
      ]);
    } finally {
      operation.ignore();
      await interruptSub?.cancel();
    }
  }

  @override
  Future<void> hotRestart() async {
    try {
      await _launch.hotRestart();
    } on TargetAppLaunchException catch (error) {
      throw TestExecutionLaunchException(
        error.message,
        stderrLines: error.stderrLines,
      );
    }
  }

  @override
  Future<void> close() {
    return _launch.cleanup();
  }
}
