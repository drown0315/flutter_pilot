import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_session.dart';
import 'recording_backend.dart';

/// Recording backend that resolves devices across backend priority order.

class CompositeRecordingBackend implements RecordingBackend {
  CompositeRecordingBackend(this._backends);

  final List<RecordingBackend> _backends;
  final Map<String, RecordingBackend> _sessionBackends =
      <String, RecordingBackend>{};

  @override
  RecordingDevicePlatform get platform => RecordingDevicePlatform.android;

  @override
  Future<List<RecordingDevice>> listDevices() async {
    final List<RecordingDevice> devices = <RecordingDevice>[];
    for (final RecordingBackend backend in _backends) {
      try {
        devices.addAll(await backend.listDevices());
      } on ScreenRecorderException catch (error) {
        if (error.code != ScreenRecorderErrorCode.missingDependency) {
          rethrow;
        }
      }
    }
    return devices;
  }

  @override
  Future<RecordingDevice> resolveDevice(String selector) async {
    ScreenRecorderException? lastDeviceNotFound;
    for (final RecordingBackend backend in _backends) {
      try {
        return await backend.resolveDevice(selector);
      } on ScreenRecorderException catch (error) {
        if (error.code != ScreenRecorderErrorCode.deviceNotFound &&
            error.code != ScreenRecorderErrorCode.missingDependency) {
          rethrow;
        }
        if (error.code == ScreenRecorderErrorCode.deviceNotFound) {
          lastDeviceNotFound = error;
        }
      }
    }
    throw lastDeviceNotFound ??
        ScreenRecorderException(
          code: ScreenRecorderErrorCode.deviceNotFound,
          message: 'No Recording Device matched selector: $selector',
          deviceSelector: selector,
        );
  }

  @override
  Future<void> start(
    RecordingSession session, {
    required bool overwrite,
  }) async {
    for (final RecordingBackend backend in _backends) {
      if (backend.platform != session.device.platform) {
        continue;
      }
      _sessionBackends[session.id] = backend;
      await backend.start(session, overwrite: overwrite);
      return;
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.startFailed,
      message: 'No backend was found for ${session.device.name}.',
      deviceSelector: session.device.id,
    );
  }

  @override
  Future<void> stop(RecordingSession session) async {
    final RecordingBackend? backend = _sessionBackends.remove(session.id);
    if (backend == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'No backend was found for Recording Session ${session.id}.',
        deviceSelector: session.device.id,
      );
    }
    await backend.stop(session);
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final RecordingBackend? backend = _sessionBackends.remove(session.id);
    if (backend == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.discardFailed,
        message: 'No backend was found for Recording Session ${session.id}.',
        deviceSelector: session.device.id,
      );
    }
    await backend.discard(session);
  }
}
