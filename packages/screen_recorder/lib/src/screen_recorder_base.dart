/// Core domain objects and programmatic API for device screen recording.
///
/// The first package slice exposes an in-memory fake backend so callers and
/// tests can exercise Recording Device discovery and Recording Session
/// lifecycle behavior without Android or iOS tooling.
library;

import 'dart:io';

/// Supported Recording Device platform families.
///
/// The platform identifies which backend family owns a Recording Device. It is
/// distinct from a Flutter Runtime Target because screen recording happens at
/// the device display level.
enum RecordingDevicePlatform {
  /// Android devices discovered through Android Debug Bridge.
  android,

  /// iOS simulators discovered through simulator tooling.
  iosSimulator,

  /// Physical iOS devices discovered through native screen capture discovery.
  iosPhysical,
}

/// Stable failure categories exposed by `ScreenRecorderException`.
///
/// Callers should branch on these values instead of parsing human-readable
/// messages because backend output can vary across host tools and platforms.
enum ScreenRecorderErrorCode {
  /// No Recording Device matched the caller's selector.
  deviceNotFound,

  /// More than one Recording Device matched where one was required.
  ambiguousDevice,

  /// The selected backend family is not supported on the current host.
  unsupportedPlatform,

  /// The requested output name contains a path segment or file extension.
  invalidOutputName,

  /// The final output file already exists and overwrite was not enabled.
  outputAlreadyExists,

  /// The selected Recording Device already has an active session.
  alreadyRecording,

  /// A backend failed while starting a recording.
  startFailed,

  /// A backend failed while stopping a recording.
  stopFailed,

  /// A backend failed while discarding a recording.
  discardFailed,

  /// The supplied Recording Session is not active in this recorder instance.
  sessionNotFound,

  /// A required host tool or helper is missing.
  missingDependency,

  /// The host denied permission required for screen capture.
  permissionDenied,
}

/// Exception type thrown by the screen recorder public API.
///
/// `code` is the stable machine-readable failure category. `message` is for
/// display and logs. Backend-specific diagnostics may be carried in
/// `backendKind`, `deviceSelector`, `rawOutput`, or `cause`.
class ScreenRecorderException implements Exception {
  /// Creates a screen recorder failure with stable code and optional context.
  const ScreenRecorderException({
    required this.code,
    required this.message,
    this.backendKind,
    this.deviceSelector,
    this.rawOutput,
    this.cause,
  });

  /// Stable failure category for programmatic handling.
  final ScreenRecorderErrorCode code;

  /// Human-readable explanation of the failure.
  final String message;

  /// Backend family that reported the failure, when known.
  final String? backendKind;

  /// Caller-provided device selector related to the failure, when any.
  final String? deviceSelector;

  /// Raw backend output useful for diagnosing host tool failures.
  final String? rawOutput;

  /// Original lower-level error, when the recorder is wrapping one.
  final Object? cause;

  @override
  String toString() => 'ScreenRecorderException($code): $message';
}

/// A device that can be selected as the source for a Recording Session.
///
/// The `id` is the backend-specific stable identity used by scripts. The
/// `name` is the human-readable label a caller may show or match against. The
/// `platform` tells the recorder which backend family owns the device.
class RecordingDevice {
  /// Creates a Recording Device returned by device discovery.
  const RecordingDevice({
    required this.id,
    required this.name,
    required this.platform,
  });

  /// Backend-specific stable identity for the device.
  final String id;

  /// Human-readable device name.
  final String name;

  /// Backend family that can record this device.
  final RecordingDevicePlatform platform;

  @override
  bool operator ==(Object other) {
    return other is RecordingDevice &&
        other.id == id &&
        other.name == name &&
        other.platform == platform;
  }

  @override
  int get hashCode => Object.hash(id, name, platform);
}

/// A currently active device screen recording.
///
/// The session is returned by `startRecord` and must be passed back to
/// `stopRecord` or discard behavior. The final saved video path is not a
/// completed artifact until `stopRecord` returns a Recording Result.
class RecordingSession {
  /// Creates a public handle for an active Recording Session.
  const RecordingSession({
    required this.id,
    required this.device,
    required this.startTime,
    required this.expectedOutputPath,
  });

  /// Unique session identity within one recorder instance.
  final String id;

  /// Recording Device whose screen is being recorded.
  final RecordingDevice device;

  /// Time when recording started.
  final DateTime startTime;

  /// Final local output path expected when the session is stopped and saved.
  final String expectedOutputPath;
}

/// Result returned after a Recording Session is stopped and saved.
///
/// The result confirms the final file path and carries basic metadata that
/// downstream tools can display or attach to reports.
class RecordingResult {
  /// Creates metadata for a saved Device Video Recording.
  const RecordingResult({
    required this.session,
    required this.outputPath,
    required this.startTime,
    required this.stopTime,
    required this.duration,
    required this.fileSizeBytes,
    required this.mimeType,
  });

  /// Session that produced this saved recording.
  final RecordingSession session;

  /// Local video file path created by stopping the session.
  final String outputPath;

  /// Time when recording started.
  final DateTime startTime;

  /// Time when recording stopped and the file was finalized.
  final DateTime stopTime;

  /// Elapsed time between session start and stop.
  final Duration duration;

  /// Size of the saved video file in bytes.
  final int fileSizeBytes;

  /// MIME type for the backend-native video format.
  final String mimeType;
}

/// Programmatic entry point for discovering devices and controlling recordings.
class ScreenRecorder {
  ScreenRecorder._(this._backend);

  /// Creates a recorder backed by in-memory fake device data.
  ///
  /// The fake backend is intended for package tests and callers that need to
  /// exercise the public API without depending on real recording tools.
  factory ScreenRecorder.fake(
      {List<RecordingDevice> devices = const <RecordingDevice>[]}) {
    return ScreenRecorder._(_FakeRecordingBackend(devices));
  }

  /// Creates a recorder that discovers and records Android devices through ADB.
  ///
  /// `commandRunner` may be supplied by tests to avoid invoking host tools.
  /// Production callers can omit it to use the host `adb` executable.
  factory ScreenRecorder.android({ScreenRecorderCommandRunner? commandRunner}) {
    return ScreenRecorder._(
      _AndroidRecordingBackend(commandRunner ?? _ProcessCommandRunner()),
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
      _IosSimulatorRecordingBackend(
        commandRunner ?? _ProcessCommandRunner(),
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
      _IosPhysicalRecordingBackend(
        commandRunner ?? _ProcessCommandRunner(),
      ),
    );
  }

  final _RecordingBackend _backend;
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
    _validateOutputName(outputName);
    final RecordingDevice device = await _backend.resolveDevice(deviceSelector);
    if (_activeDeviceIds.contains(device.id)) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.alreadyRecording,
        message: 'Device is already being recorded: ${device.name}',
        deviceSelector: deviceSelector,
      );
    }
    final String outputPath = _buildOutputPath(
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
    final int fileSizeBytes = outputFile.lengthSync();
    return RecordingResult(
      session: sessionToStop,
      outputPath: sessionToStop.expectedOutputPath,
      startTime: sessionToStop.startTime,
      stopTime: stopTime,
      duration: stopTime.difference(sessionToStop.startTime),
      fileSizeBytes: fileSizeBytes,
      mimeType: _mimeTypeFor(sessionToStop.device.platform),
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
  static String _buildOutputPath({
    required String outputDirectory,
    required String? outputName,
    required RecordingDevice device,
  }) {
    final String name = outputName ?? _generatedOutputName(device);
    final String extension = _extensionFor(device.platform);
    return '$outputDirectory${Platform.pathSeparator}$name$extension';
  }

  /// Rejects output names that would bypass backend-native extension selection.
  ///
  /// The caller may omit `outputName` entirely. When present, it must be a bare
  /// file name without path separators or any extension.
  static void _validateOutputName(String? outputName) {
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
    final String safeDeviceName =
        device.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'recording_${timestamp}_$safeDeviceName';
  }

  /// Returns the native file extension chosen for a Recording Device platform.
  static String _extensionFor(RecordingDevicePlatform platform) {
    return switch (platform) {
      RecordingDevicePlatform.android => '.mp4',
      RecordingDevicePlatform.iosSimulator => '.mov',
      RecordingDevicePlatform.iosPhysical => '.mov',
    };
  }

  /// Returns the MIME type for the platform-native recording format.
  static String _mimeTypeFor(RecordingDevicePlatform platform) {
    return switch (platform) {
      RecordingDevicePlatform.android => 'video/mp4',
      RecordingDevicePlatform.iosSimulator => 'video/quicktime',
      RecordingDevicePlatform.iosPhysical => 'video/quicktime',
    };
  }
}

/// Result returned by a completed host command.
///
/// Backends use this to inspect exit status and raw output without depending on
/// `dart:io` process objects in tests.
class ScreenRecorderCommandResult {
  /// Creates captured output for one completed host command.
  const ScreenRecorderCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Exit code reported by the host command.
  final int exitCode;

  /// Standard output captured as text.
  final String stdout;

  /// Standard error captured as text.
  final String stderr;
}

/// Started host process controlled by a recording backend.
abstract interface class ScreenRecorderProcess {
  /// Terminates the process with the backend's default signal.
  bool kill();

  /// Completes with the process exit code after it exits.
  Future<int> get exitCode;
}

/// Boundary for running host commands and starting long-running processes.
abstract interface class ScreenRecorderCommandRunner {
  /// Runs a host command to completion and captures stdout/stderr.
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  );

  /// Starts a long-running host process for an active Recording Session.
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  );
}

class _ProcessCommandRunner implements ScreenRecorderCommandRunner {
  @override
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final ProcessResult result = await Process.run(executable, arguments);
    return ScreenRecorderCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  @override
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final Process process = await Process.start(executable, arguments);
    return _DartIoScreenRecorderProcess(process);
  }
}

class _DartIoScreenRecorderProcess implements ScreenRecorderProcess {
  _DartIoScreenRecorderProcess(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill() => _process.kill();
}

/// Backend boundary used by the core recorder to discover Recording Devices.
abstract interface class _RecordingBackend {
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

/// In-memory backend used to drive tests through the public recorder API.
class _FakeRecordingBackend implements _RecordingBackend {
  _FakeRecordingBackend(List<RecordingDevice> devices)
      : _devices = List<RecordingDevice>.unmodifiable(devices);

  final List<RecordingDevice> _devices;

  @override
  Future<List<RecordingDevice>> listDevices() async {
    return _devices;
  }

  @override
  Future<RecordingDevice> resolveDevice(String selector) async {
    if (selector.isEmpty) {
      throw const ScreenRecorderException(
        code: ScreenRecorderErrorCode.deviceNotFound,
        message: 'No Recording Device selector was provided.',
      );
    }
    for (final RecordingDevice device in _devices) {
      if (device.id == selector ||
          device.name == selector ||
          device.name.toLowerCase().startsWith(selector.toLowerCase())) {
        return device;
      }
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.deviceNotFound,
      message: 'No Recording Device matched selector: $selector',
      deviceSelector: selector,
    );
  }

  @override
  Future<void> start(
    RecordingSession session, {
    required bool overwrite,
  }) async {}

  @override
  Future<void> stop(RecordingSession session) async {
    final File outputFile = File(session.expectedOutputPath);
    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsBytesSync(<int>[0, 1, 2, 3]);
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final File outputFile = File(session.expectedOutputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }
}

class _AndroidRecordingBackend implements _RecordingBackend {
  _AndroidRecordingBackend(this._commandRunner);

  static const String _backendKind = 'android';

  final ScreenRecorderCommandRunner _commandRunner;
  final Map<String, _AndroidRecordingState> _recordings =
      <String, _AndroidRecordingState>{};

  @override
  Future<List<RecordingDevice>> listDevices() async {
    final ScreenRecorderCommandResult devicesResult = await _runAdb(
      <String>['devices'],
      ScreenRecorderErrorCode.missingDependency,
    );
    final List<String> deviceIds = _parseOnlineDeviceIds(devicesResult.stdout);
    final List<RecordingDevice> devices = <RecordingDevice>[];
    for (final String deviceId in deviceIds) {
      final ScreenRecorderCommandResult modelResult = await _runAdb(
        <String>[
          '-s',
          deviceId,
          'shell',
          'getprop',
          'ro.product.model',
        ],
        ScreenRecorderErrorCode.startFailed,
      );
      final String model = modelResult.stdout.trim();
      devices.add(
        RecordingDevice(
          id: deviceId,
          name: model.isEmpty ? deviceId : model,
          platform: RecordingDevicePlatform.android,
        ),
      );
    }
    return devices;
  }

  @override
  Future<RecordingDevice> resolveDevice(String selector) async {
    final List<RecordingDevice> devices = await listDevices();
    for (final RecordingDevice device in devices) {
      if (device.id == selector ||
          device.name == selector ||
          device.name.toLowerCase().startsWith(selector.toLowerCase())) {
        return device;
      }
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.deviceNotFound,
      message: 'No Android Recording Device matched selector: $selector',
      backendKind: _backendKind,
      deviceSelector: selector,
    );
  }

  @override
  Future<void> start(
    RecordingSession session, {
    required bool overwrite,
  }) async {
    final String deviceTempPath = _deviceTempPath(session);
    try {
      final ScreenRecorderProcess process = await _commandRunner.start(
        'adb',
        <String>[
          '-s',
          session.device.id,
          'shell',
          'screenrecord',
          deviceTempPath,
        ],
      );
      _recordings[session.id] = _AndroidRecordingState(
        process: process,
        deviceTempPath: deviceTempPath,
      );
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'Failed to start Android screenrecord.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        cause: error,
      );
    }
  }

  @override
  Future<void> stop(RecordingSession session) async {
    final _AndroidRecordingState? state = _recordings.remove(session.id);
    if (state == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'Android recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    state.process.kill();
    await state.process.exitCode;
    try {
      await _runAdb(
        <String>[
          '-s',
          session.device.id,
          'pull',
          state.deviceTempPath,
          session.expectedOutputPath,
        ],
        ScreenRecorderErrorCode.stopFailed,
      );
      final File outputFile = File(session.expectedOutputPath);
      if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.stopFailed,
          message: 'Android recording output was not created.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
        );
      }
    } finally {
      await _runAdb(
        <String>[
          '-s',
          session.device.id,
          'shell',
          'rm',
          '-f',
          state.deviceTempPath,
        ],
        ScreenRecorderErrorCode.stopFailed,
      );
    }
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final _AndroidRecordingState? state = _recordings.remove(session.id);
    if (state == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.discardFailed,
        message: 'Android recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    state.process.kill();
    await state.process.exitCode;
    await _runAdb(
      <String>[
        '-s',
        session.device.id,
        'shell',
        'rm',
        '-f',
        state.deviceTempPath
      ],
      ScreenRecorderErrorCode.discardFailed,
    );
  }

  Future<ScreenRecorderCommandResult> _runAdb(
    List<String> arguments,
    ScreenRecorderErrorCode failureCode,
  ) async {
    try {
      final ScreenRecorderCommandResult result = await _commandRunner.run(
        'adb',
        arguments,
      );
      if (result.exitCode != 0) {
        throw ScreenRecorderException(
          code: failureCode,
          message: 'ADB command failed: adb ${arguments.join(' ')}',
          backendKind: _backendKind,
          rawOutput: '${result.stdout}${result.stderr}',
        );
      }
      return result;
    } on ScreenRecorderException {
      rethrow;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.missingDependency,
        message: 'Failed to run adb.',
        backendKind: _backendKind,
        cause: error,
      );
    }
  }

  static List<String> _parseOnlineDeviceIds(String adbDevicesOutput) {
    final List<String> deviceIds = <String>[];
    final List<String> lines = adbDevicesOutput.split('\n');
    for (final String line in lines.skip(1)) {
      final String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }
      final List<String> columns = trimmedLine.split(RegExp(r'\s+'));
      if (columns.length >= 2 && columns[1] == 'device') {
        deviceIds.add(columns.first);
      }
    }
    return deviceIds;
  }

  static String _deviceTempPath(RecordingSession session) {
    final String safeSessionId = session.id.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]+'),
      '_',
    );
    return '/sdcard/screen_recorder_$safeSessionId.mp4';
  }
}

class _AndroidRecordingState {
  _AndroidRecordingState({
    required this.process,
    required this.deviceTempPath,
  });

  final ScreenRecorderProcess process;
  final String deviceTempPath;
}

class _IosSimulatorRecordingBackend implements _RecordingBackend {
  _IosSimulatorRecordingBackend(this._commandRunner);

  static const String _backendKind = 'iosSimulator';

  final ScreenRecorderCommandRunner _commandRunner;
  final Map<String, ScreenRecorderProcess> _recordings =
      <String, ScreenRecorderProcess>{};

  @override
  Future<List<RecordingDevice>> listDevices() async {
    final ScreenRecorderCommandResult result = await _runSimctl(
      <String>['list', 'devices'],
      ScreenRecorderErrorCode.missingDependency,
    );
    return _parseDevices(result.stdout);
  }

  @override
  Future<RecordingDevice> resolveDevice(String selector) async {
    final List<RecordingDevice> devices = await listDevices();
    for (final RecordingDevice device in devices) {
      if (device.id == selector ||
          device.name == selector ||
          device.name.toLowerCase().startsWith(selector.toLowerCase())) {
        return device;
      }
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.deviceNotFound,
      message: 'No iOS Simulator Recording Device matched selector: $selector',
      backendKind: _backendKind,
      deviceSelector: selector,
    );
  }

  @override
  Future<void> start(
    RecordingSession session, {
    required bool overwrite,
  }) async {
    try {
      final ScreenRecorderProcess process = await _commandRunner.start(
        'xcrun',
        <String>[
          'simctl',
          'io',
          session.device.id,
          'recordVideo',
          session.expectedOutputPath,
        ],
      );
      _recordings[session.id] = process;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'Failed to start iOS Simulator recordVideo.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        cause: error,
      );
    }
  }

  @override
  Future<void> stop(RecordingSession session) async {
    final ScreenRecorderProcess? process = _recordings.remove(session.id);
    if (process == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message:
            'iOS Simulator recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    process.kill();
    await process.exitCode;
    final File outputFile = File(session.expectedOutputPath);
    if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'iOS Simulator recording output was not created.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final ScreenRecorderProcess? process = _recordings.remove(session.id);
    if (process == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.discardFailed,
        message:
            'iOS Simulator recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    process.kill();
    await process.exitCode;
    final File outputFile = File(session.expectedOutputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }

  Future<ScreenRecorderCommandResult> _runSimctl(
    List<String> arguments,
    ScreenRecorderErrorCode failureCode,
  ) async {
    try {
      final ScreenRecorderCommandResult result = await _commandRunner.run(
        'xcrun',
        <String>['simctl', ...arguments],
      );
      if (result.exitCode != 0) {
        throw ScreenRecorderException(
          code: failureCode,
          message: 'simctl command failed: simctl ${arguments.join(' ')}',
          backendKind: _backendKind,
          rawOutput: '${result.stdout}${result.stderr}',
        );
      }
      return result;
    } on ScreenRecorderException {
      rethrow;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.missingDependency,
        message: 'Failed to run xcrun simctl.',
        backendKind: _backendKind,
        cause: error,
      );
    }
  }

  static List<RecordingDevice> _parseDevices(String simctlOutput) {
    final List<RecordingDevice> devices = <RecordingDevice>[];
    bool inIosSection = false;
    final RegExp sectionPattern = RegExp(r'^--\s+(.+)\s+--$');
    final RegExp devicePattern =
        RegExp(r'^\s+(.+?) \(([0-9A-Fa-f-]{36})\) \(([^)]+)\)(.*)$');
    for (final String line in simctlOutput.split('\n')) {
      final RegExpMatch? sectionMatch = sectionPattern.firstMatch(line.trim());
      if (sectionMatch != null) {
        final String sectionName = sectionMatch.group(1)!;
        inIosSection = sectionName.startsWith('iOS ');
        continue;
      }
      if (!inIosSection) {
        continue;
      }
      final RegExpMatch? deviceMatch = devicePattern.firstMatch(line);
      if (deviceMatch == null) {
        continue;
      }
      final String suffix = deviceMatch.group(4)!;
      if (suffix.contains('unavailable')) {
        continue;
      }
      devices.add(
        RecordingDevice(
          id: deviceMatch.group(2)!,
          name: deviceMatch.group(1)!,
          platform: RecordingDevicePlatform.iosSimulator,
        ),
      );
    }
    return devices;
  }
}

class _IosPhysicalRecordingBackend implements _RecordingBackend {
  _IosPhysicalRecordingBackend(this._commandRunner);

  static const String _backendKind = 'iosPhysical';

  final ScreenRecorderCommandRunner _commandRunner;
  final Map<String, ScreenRecorderProcess> _recordings =
      <String, ScreenRecorderProcess>{};
  String? _helperPath;

  @override
  Future<List<RecordingDevice>> listDevices() async {
    final String helperPath = await _ensureHelperBuilt();
    final ScreenRecorderCommandResult result = await _runHelper(
      helperPath,
      <String>['list'],
      ScreenRecorderErrorCode.permissionDenied,
    );
    return _parseDevices(result.stdout);
  }

  @override
  Future<RecordingDevice> resolveDevice(String selector) async {
    final List<RecordingDevice> devices = await listDevices();
    for (final RecordingDevice device in devices) {
      if (device.id == selector ||
          device.name == selector ||
          device.name.toLowerCase().startsWith(selector.toLowerCase())) {
        return device;
      }
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.deviceNotFound,
      message: 'No physical iOS Recording Device matched selector: $selector',
      backendKind: _backendKind,
      deviceSelector: selector,
    );
  }

  @override
  Future<void> start(
    RecordingSession session, {
    required bool overwrite,
  }) async {
    final String helperPath = await _ensureHelperBuilt();
    try {
      final ScreenRecorderProcess process = await _commandRunner.start(
        helperPath,
        <String>[
          'record',
          '--device-id',
          session.device.id,
          '--output',
          session.expectedOutputPath,
        ],
      );
      _recordings[session.id] = process;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'Failed to start physical iOS helper recording.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        cause: error,
      );
    }
  }

  @override
  Future<void> stop(RecordingSession session) async {
    final ScreenRecorderProcess? process = _recordings.remove(session.id);
    if (process == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message:
            'Physical iOS recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    process.kill();
    await process.exitCode;
    final File outputFile = File(session.expectedOutputPath);
    if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'Physical iOS recording output was not created.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final ScreenRecorderProcess? process = _recordings.remove(session.id);
    if (process == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.discardFailed,
        message:
            'Physical iOS recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    process.kill();
    await process.exitCode;
    final File outputFile = File(session.expectedOutputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }

  Future<String> _ensureHelperBuilt() async {
    final String? existingPath = _helperPath;
    if (existingPath != null) {
      return existingPath;
    }
    final String packageRoot = Directory.current.path;
    final String sourcePath =
        '$packageRoot${Platform.pathSeparator}tool${Platform.pathSeparator}ios_physical${Platform.pathSeparator}ios_physical_capture.swift';
    final String outputPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}screen_recorder_ios_physical_capture';
    try {
      final ScreenRecorderCommandResult result = await _commandRunner.run(
        'swiftc',
        <String>[sourcePath, '-o', outputPath],
      );
      if (result.exitCode != 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.missingDependency,
          message: 'Failed to build physical iOS helper with swiftc.',
          backendKind: _backendKind,
          rawOutput: '${result.stdout}${result.stderr}',
        );
      }
      _helperPath = outputPath;
      return outputPath;
    } on ScreenRecorderException {
      rethrow;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.missingDependency,
        message: 'Failed to run swiftc for physical iOS helper.',
        backendKind: _backendKind,
        cause: error,
      );
    }
  }

  Future<ScreenRecorderCommandResult> _runHelper(
    String helperPath,
    List<String> arguments,
    ScreenRecorderErrorCode failureCode,
  ) async {
    try {
      final ScreenRecorderCommandResult result = await _commandRunner.run(
        helperPath,
        arguments,
      );
      if (result.exitCode != 0) {
        throw ScreenRecorderException(
          code: failureCode,
          message: 'Physical iOS helper command failed: ${arguments.join(' ')}',
          backendKind: _backendKind,
          rawOutput: '${result.stdout}${result.stderr}',
        );
      }
      return result;
    } on ScreenRecorderException {
      rethrow;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: failureCode,
        message: 'Failed to run physical iOS helper.',
        backendKind: _backendKind,
        cause: error,
      );
    }
  }

  static List<RecordingDevice> _parseDevices(String helperOutput) {
    final List<RecordingDevice> devices = <RecordingDevice>[];
    final List<String> lines = helperOutput.split('\n');
    for (final String line in lines.skip(1)) {
      final String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }
      final List<String> columns = trimmedLine.split('\t');
      if (columns.length < 2) {
        continue;
      }
      devices.add(
        RecordingDevice(
          id: columns[0],
          name: columns[1],
          platform: RecordingDevicePlatform.iosPhysical,
        ),
      );
    }
    return devices;
  }
}
