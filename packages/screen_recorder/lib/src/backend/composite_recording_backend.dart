import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/prepared_capture.dart';
import '../model/recording_session.dart';
import 'recording_backend.dart';

/// Recording backend that resolves devices across backend priority order.

class CompositeRecordingBackend
    implements RecordingBackend, PreparedCaptureBackend {
  CompositeRecordingBackend(this._backends);

  final List<RecordingBackend> _backends;
  final Map<String, RecordingBackend> _sessionBackends =
      <String, RecordingBackend>{};
  final Map<String, RecordingBackend> _captureBackends =
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
      try {
        await backend.start(session, overwrite: overwrite);
      } on Object {
        _sessionBackends.remove(session.id);
        rethrow;
      }
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
    final RecordingBackend? backend = _sessionBackends[session.id];
    if (backend == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'No backend was found for Recording Session ${session.id}.',
        deviceSelector: session.device.id,
      );
    }
    await backend.stop(session);
    _sessionBackends.remove(session.id);
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final RecordingBackend? backend = _sessionBackends[session.id];
    if (backend == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.discardFailed,
        message: 'No backend was found for Recording Session ${session.id}.',
        deviceSelector: session.device.id,
      );
    }
    await backend.discard(session);
    _sessionBackends.remove(session.id);
  }

  @override
  Future<bool> prepare(PreparedCapture capture) async {
    final RecordingBackend backend = _backendForDevice(capture.device);
    _captureBackends[capture.id] = backend;
    if (backend is PreparedCaptureBackend) {
      return backend.prepare(capture);
    }
    return false;
  }

  @override
  Future<void> startRecord(
    PreparedCapture capture,
    RecordingSession session, {
    required bool overwrite,
  }) async {
    final RecordingBackend backend = _backendForCapture(capture);
    _sessionBackends[session.id] = backend;
    if (backend is PreparedCaptureBackend) {
      try {
        await backend.startRecord(capture, session, overwrite: overwrite);
      } on Object {
        _sessionBackends.remove(session.id);
        rethrow;
      }
      return;
    }
    try {
      await backend.start(session, overwrite: overwrite);
    } on Object {
      _sessionBackends.remove(session.id);
      rethrow;
    }
  }

  @override
  Future<void> stopRecord(
    PreparedCapture capture,
    RecordingSession session,
  ) async {
    final RecordingBackend backend = _backendForCapture(capture);
    if (backend is PreparedCaptureBackend) {
      await backend.stopRecord(capture, session);
      _sessionBackends.remove(session.id);
      return;
    }
    await backend.stop(session);
    _sessionBackends.remove(session.id);
  }

  @override
  Future<void> discardRecord(
    PreparedCapture capture,
    RecordingSession session,
  ) async {
    final RecordingBackend backend = _backendForCapture(capture);
    if (backend is PreparedCaptureBackend) {
      await backend.discardRecord(capture, session);
      _sessionBackends.remove(session.id);
      return;
    }
    await backend.discard(session);
    _sessionBackends.remove(session.id);
  }

  @override
  Future<void> dispose(PreparedCapture capture) async {
    final RecordingBackend? backend = _captureBackends[capture.id];
    if (backend is PreparedCaptureBackend) {
      await backend.dispose(capture);
    }
    _captureBackends.remove(capture.id);
  }

  RecordingBackend _backendForDevice(RecordingDevice device) {
    for (final RecordingBackend backend in _backends) {
      if (backend.platform == device.platform) {
        return backend;
      }
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.startFailed,
      message: 'No backend was found for ${device.name}.',
      deviceSelector: device.id,
    );
  }

  RecordingBackend _backendForCapture(PreparedCapture capture) {
    return _captureBackends[capture.id] ?? _backendForDevice(capture.device);
  }
}
