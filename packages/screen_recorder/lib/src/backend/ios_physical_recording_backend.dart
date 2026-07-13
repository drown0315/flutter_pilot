import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/prepared_capture.dart';
import '../model/recording_session.dart';
import '../process/command_runner.dart';
import 'recording_backend.dart';

/// Physical iOS recording backend implemented through the in-package Swift helper.

class IosPhysicalRecordingBackend
    implements RecordingBackend, PreparedCaptureBackend {
  IosPhysicalRecordingBackend(this._commandRunner);

  static const String _backendKind = 'iosPhysical';
  static const Duration _startProbeTimeout = Duration(seconds: 1);
  static const Duration _readyTimeout = Duration(seconds: 15);
  static const Duration _protocolTimeout = Duration(seconds: 10);
  static const Duration _stopTimeout = Duration(seconds: 10);

  final ScreenRecorderCommandRunner _commandRunner;
  final Map<String, PreparedCapture> _standaloneCaptures =
      <String, PreparedCapture>{};
  final Map<String, _IosPreparedCaptureState> _preparedCaptures =
      <String, _IosPreparedCaptureState>{};
  String? _helperPath;

  @override
  RecordingDevicePlatform get platform => RecordingDevicePlatform.iosPhysical;

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
      if (device.id == selector || device.name == selector) {
        return device;
      }
    }
    for (final RecordingDevice device in devices) {
      if (device.name.toLowerCase().startsWith(selector.toLowerCase())) {
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
    final PreparedCapture capture = PreparedCapture(
      id: 'standalone-${session.id}',
      device: session.device,
    );
    await prepare(capture);
    _standaloneCaptures[session.id] = capture;
    await startRecord(capture, session, overwrite: overwrite);
  }

  Future<int?> _probeImmediateExit(ScreenRecorderProcess process) async {
    final Completer<int?> exitCode = Completer<int?>();
    final Timer timer = Timer(_startProbeTimeout, () {
      if (!exitCode.isCompleted) {
        exitCode.complete(null);
      }
    });
    process.exitCode.then((int value) {
      if (!exitCode.isCompleted) {
        exitCode.complete(value);
      }
    });
    final int? result = await exitCode.future;
    timer.cancel();
    return result;
  }

  @override
  Future<bool> prepare(PreparedCapture capture) async {
    if (_preparedCaptures.containsKey(capture.id)) {
      return true;
    }
    final String helperPath = await _ensureHelperBuilt();
    _IosPreparedCaptureState? state;
    try {
      final ScreenRecorderProcess process =
          await _commandRunner.start(helperPath, <String>[
        'serve',
        '--device-id',
        capture.device.id,
      ]);
      state = _IosPreparedCaptureState(
        capture: capture,
        process: process,
        events: StreamIterator<String>(process.stdoutLines),
      );
      _preparedCaptures[capture.id] = state;
      await _waitForEvent(
        state,
        'ready',
        timeout: _readyTimeout,
        failureCode: ScreenRecorderErrorCode.startFailed,
      );
      return true;
    } on ScreenRecorderException {
      await _cleanupFailedPrepare(capture, state);
      rethrow;
    } on Object catch (error) {
      await _cleanupFailedPrepare(capture, state);
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'Failed to prepare physical iOS helper capture.',
        backendKind: _backendKind,
        deviceSelector: capture.device.id,
        cause: error,
      );
    }
  }

  @override
  Future<void> startRecord(
    PreparedCapture capture,
    RecordingSession session, {
    required bool overwrite,
  }) async {
    final _IosPreparedCaptureState state = _requirePrepared(capture);
    if (state.activeSessionId != null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.alreadyRecording,
        message: 'Physical iOS prepared capture already has an active segment.',
        backendKind: _backendKind,
        deviceSelector: capture.device.id,
      );
    }
    state.activeSessionId = session.id;
    state.process.writeLine(
      jsonEncode(<String, String>{
        'operation': 'start',
        'outputPath': session.expectedOutputPath,
      }),
    );
    try {
      await _waitForEvent(
        state,
        'started',
        timeout: _protocolTimeout,
        failureCode: ScreenRecorderErrorCode.startFailed,
      );
    } on Object {
      state.activeSessionId = null;
      rethrow;
    }
  }

  @override
  Future<void> stopRecord(
    PreparedCapture capture,
    RecordingSession session,
  ) async {
    final _IosPreparedCaptureState state = _requirePrepared(capture);
    if (state.activeSessionId != session.id) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'Physical iOS prepared capture did not own ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    state.process.writeLine(jsonEncode(<String, String>{'operation': 'stop'}));
    await _waitForEvent(
      state,
      'saved',
      timeout: _stopTimeout,
      failureCode: ScreenRecorderErrorCode.stopFailed,
    );
    state.activeSessionId = null;
    _verifyOutputFile(session);
  }

  static String _joinDiagnostics(List<String> lines) {
    return lines.where((String line) => line.isNotEmpty).join('\n');
  }

  @override
  Future<void> stop(RecordingSession session) async {
    final PreparedCapture? capture = _standaloneCaptures.remove(session.id);
    if (capture == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message:
            'Physical iOS recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    await stopRecord(capture, session);
    await dispose(capture);
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final PreparedCapture? capture = _standaloneCaptures.remove(session.id);
    if (capture == null) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.discardFailed,
        message:
            'Physical iOS recording state was not found for ${session.id}.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
      );
    }
    await discardRecord(capture, session);
    await dispose(capture);
  }

  @override
  Future<void> discardRecord(
    PreparedCapture capture,
    RecordingSession session,
  ) async {
    final _IosPreparedCaptureState state = _requirePrepared(capture);
    if (state.activeSessionId == session.id) {
      state.process.writeLine(
        jsonEncode(<String, String>{'operation': 'stop'}),
      );
      await _waitForEvent(
        state,
        'saved',
        timeout: _stopTimeout,
        failureCode: ScreenRecorderErrorCode.discardFailed,
      );
      state.activeSessionId = null;
    }
    final File outputFile = File(session.expectedOutputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }

  @override
  Future<void> dispose(PreparedCapture capture) async {
    final _IosPreparedCaptureState? state = _preparedCaptures.remove(
      capture.id,
    );
    if (state == null || state.disposed) {
      return;
    }
    await _shutdownPreparedState(capture, state, throwOnFailure: true);
  }

  Future<void> _cleanupFailedPrepare(
    PreparedCapture capture,
    _IosPreparedCaptureState? state,
  ) async {
    if (state == null) {
      return;
    }
    _preparedCaptures.remove(capture.id);
    try {
      await _shutdownPreparedState(capture, state, throwOnFailure: false);
    } on Object {
      state.process.kill(ProcessSignal.sigkill);
    }
  }

  Future<void> _shutdownPreparedState(
    PreparedCapture capture,
    _IosPreparedCaptureState state, {
    required bool throwOnFailure,
  }) async {
    if (state.disposed) {
      return;
    }
    state.disposed = true;
    state.process.writeLine(
      jsonEncode(<String, String>{'operation': 'shutdown'}),
    );
    final int exitCode = await state.process.exitCode.timeout(
      _stopTimeout + Duration(seconds: 5),
      onTimeout: () {
        state.process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (exitCode != 0 && throwOnFailure) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'Physical iOS helper shutdown failed.',
        backendKind: _backendKind,
        deviceSelector: capture.device.id,
        rawOutput: _joinDiagnostics(<String>[
          'helper exitCode: $exitCode',
          await state.process.stdout,
          await state.process.stderr,
        ]),
      );
    }
  }

  _IosPreparedCaptureState _requirePrepared(PreparedCapture capture) {
    final _IosPreparedCaptureState? state = _preparedCaptures[capture.id];
    if (state == null || state.disposed) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.sessionNotFound,
        message: 'Physical iOS prepared capture is not active: ${capture.id}',
        backendKind: _backendKind,
        deviceSelector: capture.device.id,
      );
    }
    return state;
  }

  Future<void> _waitForEvent(
    _IosPreparedCaptureState state,
    String expectedEvent, {
    required Duration timeout,
    required ScreenRecorderErrorCode failureCode,
  }) async {
    final bool received = await state.events.moveNext().timeout(
          timeout,
          onTimeout: () => false,
        );
    if (!received) {
      final int? immediateExitCode = await _probeImmediateExit(state.process);
      throw ScreenRecorderException(
        code: failureCode,
        message: 'Timed out waiting for physical iOS helper $expectedEvent.',
        backendKind: _backendKind,
        deviceSelector: state.capture.device.id,
        rawOutput: _joinDiagnostics(<String>[
          if (immediateExitCode != null) 'helper exitCode: $immediateExitCode',
          await state.process.stdout.timeout(
            Duration(milliseconds: 100),
            onTimeout: () => '',
          ),
          await state.process.stderr.timeout(
            Duration(milliseconds: 100),
            onTimeout: () => '',
          ),
        ]),
      );
    }
    final String line = state.events.current;
    final Object? decoded = jsonDecode(line);
    if (decoded is Map<String, Object?> && decoded['event'] == expectedEvent) {
      return;
    }
    if (decoded
        case <String, Object?>{
          'event': 'error',
          'message': final Object? message,
        }) {
      throw ScreenRecorderException(
        code: failureCode,
        message: 'Physical iOS helper reported an error.',
        backendKind: _backendKind,
        deviceSelector: state.capture.device.id,
        rawOutput: message?.toString(),
      );
    }
    throw ScreenRecorderException(
      code: failureCode,
      message:
          'Physical iOS helper emitted unexpected event while waiting for $expectedEvent.',
      backendKind: _backendKind,
      deviceSelector: state.capture.device.id,
      rawOutput: line,
    );
  }

  void _verifyOutputFile(RecordingSession session) {
    final File outputFile = File(session.expectedOutputPath);
    if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'Physical iOS recording output was not created.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: <String>[
          'output exists: ${outputFile.existsSync()}',
          if (outputFile.existsSync())
            'output size: ${outputFile.lengthSync()}',
        ].join('\n'),
      );
    }
  }

  Future<String> _ensureHelperBuilt() async {
    final String? existingPath = _helperPath;
    if (existingPath != null) {
      return existingPath;
    }
    final Uri? packageUri = await Isolate.resolvePackageUri(
      Uri.parse('package:screen_recorder/'),
    );
    final String packageRoot;
    if (packageUri != null) {
      packageRoot = Directory(packageUri.toFilePath()).parent.path;
    } else {
      packageRoot = Directory.current.path;
    }
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

class _IosPreparedCaptureState {
  _IosPreparedCaptureState({
    required this.capture,
    required this.process,
    required this.events,
  });

  final PreparedCapture capture;
  final ScreenRecorderProcess process;
  final StreamIterator<String> events;
  String? activeSessionId;
  bool disposed = false;
}
