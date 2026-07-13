import 'dart:io';

import '../backend/recording_backend.dart';
import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/prepared_capture.dart';
import '../model/recording_result.dart';
import '../model/recording_session.dart';

/// Coordinates Recording Session lifecycle around a selected backend.
class ScreenRecorderService {
  /// Creates a service that delegates backend-specific work to `backend`.
  ScreenRecorderService(this._backend);

  final RecordingBackend _backend;
  final Map<String, RecordingSession> _activeSessions =
      <String, RecordingSession>{};
  final Map<String, _PreparedCaptureState> _preparedCaptures =
      <String, _PreparedCaptureState>{};
  final Set<String> _activeDeviceIds = <String>{};
  int _nextSessionNumber = 1;
  int _nextCaptureNumber = 1;

  /// Lists the Recording Devices currently available to this recorder.
  Future<List<RecordingDevice>> listDevices() {
    return _backend.listDevices();
  }

  /// Starts recording the selected Recording Device.
  ///
  /// `deviceSelector` matches the backend-specific device id, the exact device
  /// name, or a case-insensitive device-name prefix. `outputDirectory` is the
  /// local directory where the final video will be saved. `outputName` omits
  /// any extension because the backend chooses the native format.
  Future<RecordingSession> startRecord({
    String? deviceSelector,
    PreparedCapture? preparedCapture,
    required String outputDirectory,
    String? outputName,
    bool overwrite = false,
  }) async {
    validateOutputName(outputName);
    if ((deviceSelector == null) == (preparedCapture == null)) {
      throw const ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message:
            'Provide exactly one of deviceSelector or preparedCapture to startRecord.',
      );
    }
    final PreparedCapture? capture = preparedCapture;
    if (capture != null) {
      return _startRecordFromPreparedCapture(
        capture,
        outputDirectory: outputDirectory,
        outputName: outputName,
        overwrite: overwrite,
      );
    }
    return _startDirectRecord(
      deviceSelector: deviceSelector!,
      outputDirectory: outputDirectory,
      outputName: outputName,
      overwrite: overwrite,
    );
  }

  Future<RecordingSession> _startDirectRecord({
    required String deviceSelector,
    required String outputDirectory,
    required String? outputName,
    required bool overwrite,
  }) async {
    final RecordingDevice device = await _backend.resolveDevice(deviceSelector);
    if (_activeDeviceIds.contains(device.id)) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.alreadyRecording,
        message: 'Device is already being recorded: ${device.name}',
        deviceSelector: deviceSelector,
      );
    }
    final String outputPath = buildOutputPath(
      outputDirectory: outputDirectory,
      outputName: outputName,
      device: device,
    );
    if (!overwrite && File(outputPath).existsSync()) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.outputAlreadyExists,
        message: 'Output file already exists: $outputPath',
        deviceSelector: deviceSelector,
      );
    }
    final RecordingSession session = RecordingSession(
      id: 'recording-${_nextSessionNumber++}',
      device: device,
      startTime: DateTime.now().toUtc(),
      expectedOutputPath: outputPath,
    );
    _activeSessions[session.id] = session;
    _activeDeviceIds.add(device.id);
    try {
      await _backend.start(session, overwrite: overwrite);
    } on Object {
      _releaseActiveSession(session);
      rethrow;
    }
    return session;
  }

  /// Prepares the selected Recording Device for future Recording Sessions.
  ///
  /// Physical iOS uses this to start native capture before the Target App
  /// launches. Backends without a prepared mode return a direct capture handle;
  /// their actual recording process still starts in [startRecord].
  Future<PreparedCapture> prepare({
    required String deviceSelector,
  }) async {
    final RecordingDevice device = await _backend.resolveDevice(deviceSelector);
    final PreparedCapture capture = PreparedCapture(
      id: 'capture-${_nextCaptureNumber++}',
      device: device,
    );
    bool backendPrepared = false;
    final RecordingBackend backend = _backend;
    if (backend is PreparedCaptureBackend) {
      backendPrepared = await backend.prepare(capture);
    }
    _preparedCaptures[capture.id] = _PreparedCaptureState(
      capture: capture,
      backendPrepared: backendPrepared,
    );
    return capture;
  }

  /// Starts one Recording Session from a prepared capture.
  Future<RecordingSession> _startRecordFromPreparedCapture(
    PreparedCapture capture, {
    required String outputDirectory,
    String? outputName,
    bool overwrite = false,
  }) async {
    final _PreparedCaptureState state = _requirePreparedCapture(capture);
    if (state.activeSessionId != null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.alreadyRecording,
        message: 'Prepared capture already has an active Recording Session.',
        deviceSelector: capture.device.id,
      );
    }
    if (_activeDeviceIds.contains(capture.device.id)) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.alreadyRecording,
        message: 'Device is already being recorded: ${capture.device.name}',
        deviceSelector: capture.device.id,
      );
    }
    final String outputPath = buildOutputPath(
      outputDirectory: outputDirectory,
      outputName: outputName,
      device: capture.device,
    );
    if (!overwrite && File(outputPath).existsSync()) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.outputAlreadyExists,
        message: 'Output file already exists: $outputPath',
        deviceSelector: capture.device.id,
      );
    }
    final RecordingSession session = RecordingSession(
      id: 'recording-${_nextSessionNumber++}',
      device: capture.device,
      startTime: DateTime.now().toUtc(),
      expectedOutputPath: outputPath,
    );
    _activeSessions[session.id] = session;
    _activeDeviceIds.add(capture.device.id);
    state.activeSessionId = session.id;
    try {
      if (state.backendPrepared) {
        await (_backend as PreparedCaptureBackend).startRecord(
          capture,
          session,
          overwrite: overwrite,
        );
      } else {
        await _backend.start(session, overwrite: overwrite);
      }
    } on Object {
      state.activeSessionId = null;
      _activeSessions.remove(session.id);
      _activeDeviceIds.remove(capture.device.id);
      rethrow;
    }
    return session;
  }

  /// Stops an active Recording Session and returns saved video metadata.
  Future<RecordingResult> stopRecord(RecordingSession session) async {
    final RecordingSession sessionToStop = _requireActiveSession(session);
    final _PreparedCaptureState? preparedState =
        _preparedStateForSession(sessionToStop);
    if (preparedState != null && preparedState.backendPrepared) {
      await (_backend as PreparedCaptureBackend).stopRecord(
        preparedState.capture,
        sessionToStop,
      );
      preparedState.activeSessionId = null;
    } else {
      await _backend.stop(sessionToStop);
      preparedState?.activeSessionId = null;
    }
    _releaseActiveSession(sessionToStop);
    final File outputFile = File(sessionToStop.expectedOutputPath);
    final DateTime stopTime = DateTime.now().toUtc();
    final int fileSizeBytes =
        outputFile.existsSync() ? outputFile.lengthSync() : 0;
    return RecordingResult(
      session: sessionToStop,
      outputPath: sessionToStop.expectedOutputPath,
      startTime: sessionToStop.startTime,
      stopTime: stopTime,
      duration: stopTime.difference(sessionToStop.startTime),
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeTypeFor(sessionToStop.device.platform),
    );
  }

  /// Stops an active Recording Session and discards any local output file.
  ///
  /// Discard is used for canceled recordings. It cleans up backend artifacts and
  /// does not return a Recording Result because no saved video should remain.
  Future<void> discardRecord(RecordingSession session) async {
    final RecordingSession sessionToDiscard = _requireActiveSession(session);
    final _PreparedCaptureState? preparedState =
        _preparedStateForSession(sessionToDiscard);
    if (preparedState != null && preparedState.backendPrepared) {
      await (_backend as PreparedCaptureBackend).discardRecord(
        preparedState.capture,
        sessionToDiscard,
      );
      preparedState.activeSessionId = null;
    } else {
      await _backend.discard(sessionToDiscard);
      preparedState?.activeSessionId = null;
    }
    _releaseActiveSession(sessionToDiscard);
  }

  /// Releases a prepared capture. Repeated disposal is harmless.
  Future<void> dispose(PreparedCapture capture) async {
    final _PreparedCaptureState? state = _preparedCaptures[capture.id];
    if (state == null || state.disposed) {
      return;
    }
    final String? activeSessionId = state.activeSessionId;
    if (activeSessionId != null) {
      final RecordingSession? activeSession = _activeSessions[activeSessionId];
      if (activeSession != null) {
        await discardRecord(activeSession);
      } else {
        state.activeSessionId = null;
      }
    }
    if (state.backendPrepared) {
      await (_backend as PreparedCaptureBackend).dispose(capture);
    }
    state.disposed = true;
    _preparedCaptures.remove(capture.id);
  }

  /// Removes an active Recording Session from this recorder instance.
  ///
  /// A session must belong to this recorder and still be active. Sessions from
  /// another recorder, already stopped sessions, and already discarded sessions
  /// fail with `sessionNotFound`.
  RecordingSession _requireActiveSession(RecordingSession session) {
    final RecordingSession? activeSession = _activeSessions[session.id];
    if (activeSession == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.sessionNotFound,
        message: 'Recording Session is not active: ${session.id}',
      );
    }
    return activeSession;
  }

  void _releaseActiveSession(RecordingSession session) {
    _activeSessions.remove(session.id);
    _activeDeviceIds.remove(session.device.id);
  }

  _PreparedCaptureState _requirePreparedCapture(
    PreparedCapture capture,
  ) {
    final _PreparedCaptureState? state = _preparedCaptures[capture.id];
    if (state == null || state.disposed) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.sessionNotFound,
        message: 'Prepared recording capture is not active: ${capture.id}',
        deviceSelector: capture.device.id,
      );
    }
    return state;
  }

  _PreparedCaptureState? _preparedStateForSession(RecordingSession session) {
    for (final _PreparedCaptureState state in _preparedCaptures.values) {
      if (state.activeSessionId == session.id) {
        return state;
      }
    }
    return null;
  }

  /// Builds the final local output path using the backend-native extension.
  ///
  /// `outputName` is either caller-provided or generated without an extension.
  /// The returned path is only guaranteed to exist after `stopRecord`
  /// successfully completes.
  static String buildOutputPath({
    required String outputDirectory,
    required String? outputName,
    required RecordingDevice device,
  }) {
    final String name = outputName ?? _generatedOutputName(device);
    final String extension = extensionFor(device.platform);
    return '$outputDirectory${Platform.pathSeparator}$name$extension';
  }

  /// Rejects output names that would bypass backend-native extension selection.
  ///
  /// The caller may omit `outputName` entirely. When present, it must be a bare
  /// file name without path separators or any extension.
  static void validateOutputName(String? outputName) {
    if (outputName == null) {
      return;
    }
    final bool hasPathSeparator =
        outputName.contains('/') || outputName.contains(r'\');
    final bool hasExtension = outputName.contains('.');
    if (outputName.isEmpty || hasPathSeparator || hasExtension) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.invalidOutputName,
        message:
            'Output name must be a file name without path separators or an extension.',
      );
    }
  }

  /// Generates a readable output name from UTC time and Recording Device name.
  ///
  /// The timestamp keeps quick recordings distinct, while the sanitized device
  /// name makes files easier to identify in a shared output directory.
  static String _generatedOutputName(RecordingDevice device) {
    final String timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final String safeDeviceName = device.name.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '_',
        );
    return 'recording_${timestamp}_$safeDeviceName';
  }

  /// Returns the native file extension chosen for a Recording Device platform.
  static String extensionFor(RecordingDevicePlatform platform) {
    return switch (platform) {
      RecordingDevicePlatform.android => '.mp4',
      RecordingDevicePlatform.iosSimulator => '.mov',
      RecordingDevicePlatform.iosPhysical => '.mov',
    };
  }

  /// Returns the MIME type for the platform-native recording format.
  static String mimeTypeFor(RecordingDevicePlatform platform) {
    return switch (platform) {
      RecordingDevicePlatform.android => 'video/mp4',
      RecordingDevicePlatform.iosSimulator => 'video/quicktime',
      RecordingDevicePlatform.iosPhysical => 'video/quicktime',
    };
  }
}

class _PreparedCaptureState {
  _PreparedCaptureState({
    required this.capture,
    required this.backendPrepared,
  });

  final PreparedCapture capture;
  final bool backendPrepared;
  String? activeSessionId;
  bool disposed = false;
}
