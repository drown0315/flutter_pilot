import 'dart:io';

import '../backend/recording_backend.dart';
import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_result.dart';
import '../model/recording_session.dart';

/// Coordinates Recording Session lifecycle around a selected backend.
class ScreenRecorderService {
  /// Creates a service that delegates backend-specific work to `backend`.
  ScreenRecorderService(this._backend);

  final RecordingBackend _backend;
  final Map<String, RecordingSession> _activeSessions =
      <String, RecordingSession>{};
  final Set<String> _activeDeviceIds = <String>{};
  int _nextSessionNumber = 1;

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
    required String deviceSelector,
    required String outputDirectory,
    String? outputName,
    bool overwrite = false,
  }) async {
    validateOutputName(outputName);
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
    await _backend.start(session, overwrite: overwrite);
    return session;
  }

  /// Stops an active Recording Session and returns saved video metadata.
  Future<RecordingResult> stopRecord(RecordingSession session) async {
    final RecordingSession sessionToStop = _takeActiveSession(session);
    await _backend.stop(sessionToStop);
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
    final RecordingSession sessionToDiscard = _takeActiveSession(session);
    await _backend.discard(sessionToDiscard);
  }

  /// Removes an active Recording Session from this recorder instance.
  ///
  /// A session must belong to this recorder and still be active. Sessions from
  /// another recorder, already stopped sessions, and already discarded sessions
  /// fail with `sessionNotFound`.
  RecordingSession _takeActiveSession(RecordingSession session) {
    final RecordingSession? activeSession = _activeSessions.remove(session.id);
    if (activeSession == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.sessionNotFound,
        message: 'Recording Session is not active: ${session.id}',
      );
    }
    _activeDeviceIds.remove(activeSession.device.id);
    return activeSession;
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
