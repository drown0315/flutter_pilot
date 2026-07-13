/// Public facade for device screen recording.
///
/// The implementation is split into service, backend, process, model, and
/// common modules so platform-specific behavior stays out of the facade.
library;

import 'backend/android_recording_backend.dart';
import 'backend/composite_recording_backend.dart';
import 'backend/fake_recording_backend.dart';
import 'backend/ios_physical_recording_backend.dart';
import 'backend/ios_simulator_recording_backend.dart';
import 'backend/recording_backend.dart';
import 'model/recording_device.dart';
import 'model/prepared_capture.dart';
import 'model/recording_result.dart';
import 'model/recording_session.dart';
import 'process/command_runner.dart';
import 'service/screen_recorder_service.dart';

export 'common/screen_recorder_exception.dart';
export 'model/prepared_capture.dart';
export 'model/recording_device.dart';
export 'model/recording_result.dart';
export 'model/recording_session.dart';
export 'process/command_runner.dart';

/// Programmatic entry point for discovering devices and controlling recordings.
class ScreenRecorder {
  ScreenRecorder._(this._service);

  /// Creates a recorder backed by in-memory fake device data.
  ///
  /// The fake backend is intended for package tests and callers that need to
  /// exercise the public API without depending on real recording tools.
  factory ScreenRecorder.fake({
    List<RecordingDevice> devices = const <RecordingDevice>[],
  }) {
    return ScreenRecorder._(
      ScreenRecorderService(FakeRecordingBackend(devices)),
    );
  }

  /// Creates the default recorder using all supported backend families.
  ///
  /// Resolution searches Android, then iOS Simulator, then physical iOS. The
  /// first backend with a matching Recording Device owns the session.
  factory ScreenRecorder.defaultRecorder({
    ScreenRecorderCommandRunner? commandRunner,
    RecordingDevicePlatform? platform,
  }) {
    final ScreenRecorderCommandRunner runner =
        commandRunner ?? ProcessCommandRunner();
    final List<RecordingBackend> backends = <RecordingBackend>[
      if (platform == null || platform == RecordingDevicePlatform.android)
        AndroidRecordingBackend(runner),
      if (platform == null || platform == RecordingDevicePlatform.iosSimulator)
        IosSimulatorRecordingBackend(runner),
      if (platform == null || platform == RecordingDevicePlatform.iosPhysical)
        IosPhysicalRecordingBackend(runner),
    ];
    return ScreenRecorder._(
      ScreenRecorderService(CompositeRecordingBackend(backends)),
    );
  }

  /// Creates a recorder that discovers and records Android devices through ADB.
  ///
  /// `commandRunner` may be supplied by tests to avoid invoking host tools.
  /// Production callers can omit it to use the host `adb` executable.
  factory ScreenRecorder.android({ScreenRecorderCommandRunner? commandRunner}) {
    return ScreenRecorder._(
      ScreenRecorderService(
        AndroidRecordingBackend(commandRunner ?? ProcessCommandRunner()),
      ),
    );
  }

  /// Creates a recorder that discovers and records iOS simulators through simctl.
  ///
  /// `commandRunner` may be supplied by tests to avoid invoking `xcrun`.
  /// Production callers can omit it to use the host simulator tooling.
  factory ScreenRecorder.iosSimulator({
    ScreenRecorderCommandRunner? commandRunner,
  }) {
    return ScreenRecorder._(
      ScreenRecorderService(
        IosSimulatorRecordingBackend(commandRunner ?? ProcessCommandRunner()),
      ),
    );
  }

  /// Creates a recorder that discovers and records physical iOS devices.
  ///
  /// The backend builds the in-package Swift helper and uses AVFoundation /
  /// CoreMediaIO discovery through that helper. Tests may inject a fake
  /// `commandRunner` so no physical iPhone or Swift toolchain is required.
  factory ScreenRecorder.iosPhysical({
    ScreenRecorderCommandRunner? commandRunner,
  }) {
    return ScreenRecorder._(
      ScreenRecorderService(
        IosPhysicalRecordingBackend(commandRunner ?? ProcessCommandRunner()),
      ),
    );
  }

  final ScreenRecorderService _service;

  /// Lists the Recording Devices currently available to this recorder.
  Future<List<RecordingDevice>> listDevices() {
    return _service.listDevices();
  }

  /// Starts recording the selected Recording Device.
  Future<RecordingSession> startRecord({
    String? deviceSelector,
    PreparedCapture? preparedCapture,
    required String outputDirectory,
    String? outputName,
    bool overwrite = false,
  }) {
    return _service.startRecord(
      deviceSelector: deviceSelector,
      preparedCapture: preparedCapture,
      outputDirectory: outputDirectory,
      outputName: outputName,
      overwrite: overwrite,
    );
  }

  /// Prepares the selected Recording Device for one or more later sessions.
  Future<PreparedCapture> prepare({
    required String deviceSelector,
  }) {
    return _service.prepare(deviceSelector: deviceSelector);
  }

  /// Stops an active Recording Session and returns saved video metadata.
  Future<RecordingResult> stopRecord(RecordingSession session) {
    return _service.stopRecord(session);
  }

  /// Stops an active Recording Session and discards any local output file.
  Future<void> discardRecord(RecordingSession session) {
    return _service.discardRecord(session);
  }

  /// Releases a prepared capture. Calling this more than once is harmless.
  Future<void> dispose(PreparedCapture capture) {
    return _service.dispose(capture);
  }
}
