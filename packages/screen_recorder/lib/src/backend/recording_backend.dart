import '../model/recording_device.dart';
import '../model/recording_session.dart';

/// Backend contract used by the recorder service.

abstract interface class RecordingBackend {
  /// The Recording Device platform family this backend supports.
  RecordingDevicePlatform get platform;

  /// Returns the Recording Devices visible to this backend.
  Future<List<RecordingDevice>> listDevices();

  /// Resolves one Recording Device from a caller-provided selector.
  Future<RecordingDevice> resolveDevice(String selector);

  /// Starts the backend-owned recording process for `session`.
  Future<void> start(RecordingSession session, {required bool overwrite});

  /// Stops the backend-owned recording process for `session`.
  Future<void> stop(RecordingSession session);

  /// Stops the backend-owned recording process and removes saved artifacts.
  Future<void> discard(RecordingSession session);
}
