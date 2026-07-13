import '../model/recording_device.dart';
import '../model/prepared_capture.dart';
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

/// Optional backend capability for preparing capture before segment recording.
///
/// Backends return `true` from [prepare] when they created backend-owned state
/// for the capture. Returning `false` lets the recorder service fall back to the
/// existing direct `start` / `stop` lifecycle for that platform.
abstract interface class PreparedCaptureBackend implements RecordingBackend {
  /// Prepares backend capture for `capture.device`.
  Future<bool> prepare(PreparedCapture capture);

  /// Starts one saved video segment on a prepared capture.
  Future<void> startRecord(
    PreparedCapture capture,
    RecordingSession session, {
    required bool overwrite,
  });

  /// Stops the active segment and keeps the prepared capture alive.
  Future<void> stopRecord(
    PreparedCapture capture,
    RecordingSession session,
  );

  /// Stops the active segment and removes its output file.
  Future<void> discardRecord(
    PreparedCapture capture,
    RecordingSession session,
  );

  /// Releases backend state associated with `capture`.
  Future<void> dispose(PreparedCapture capture);
}
