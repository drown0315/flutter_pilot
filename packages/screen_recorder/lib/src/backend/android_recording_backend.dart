import 'dart:async';
import 'dart:io';

import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_session.dart';
import '../process/command_runner.dart';
import 'recording_backend.dart';

/// Android recording backend implemented through Android Debug Bridge.

class AndroidRecordingBackend implements RecordingBackend {
  AndroidRecordingBackend(this._commandRunner);

  static const String _backendKind = 'android';
  static const int _fallbackFrameRate = 4;
  static const Duration _nativeStartProbeTimeout = Duration(milliseconds: 500);
  static const Duration _scrcpyStartProbeTimeout = Duration(seconds: 1);
  static const Duration _fallbackFrameInterval = Duration(milliseconds: 250);
  static const Duration _stopTimeout = Duration(seconds: 5);

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
    final _ScrcpyStartFailure? scrcpyFailure =
        await _tryStartScrcpyRecording(session);
    if (scrcpyFailure == null) {
      return;
    }
    try {
      final String deviceTempPath = _deviceTempPath(session);
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
      final _ImmediateProcessExit? immediateExit =
          await _probeImmediateExit(process, timeout: _nativeStartProbeTimeout);
      if (immediateExit == null) {
        _recordings[session.id] = _AndroidRecordingState.native(
          process: process,
          deviceTempPath: deviceTempPath,
        );
        return;
      }
      if (!_canFallbackToHostCapture(immediateExit)) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.startFailed,
          message: 'Android screenrecord exited immediately.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
          rawOutput: _joinDiagnostics(
            <String>[
              'screenrecord exitCode: ${immediateExit.exitCode}',
              immediateExit.stdout,
              immediateExit.stderr,
            ],
          ),
        );
      }
      _recordings[session.id] = await _startHostFrameCapture(
        session,
        startupDiagnostics: <String>[
          ...scrcpyFailure.diagnostics,
          'screenrecord exitCode: ${immediateExit.exitCode}',
          immediateExit.stdout,
          immediateExit.stderr,
        ],
      );
    } on ScreenRecorderException {
      rethrow;
    } on Object catch (error) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'Failed to start Android screenrecord.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: _joinDiagnostics(scrcpyFailure.diagnostics),
        cause: error,
      );
    }
  }

  Future<_ScrcpyStartFailure?> _tryStartScrcpyRecording(
    RecordingSession session,
  ) async {
    try {
      final ScreenRecorderProcess process = await _commandRunner.start(
        'scrcpy',
        <String>[
          '--serial',
          session.device.id,
          '--no-audio',
          '--no-playback',
          '--no-window',
          '--record=${session.expectedOutputPath}',
        ],
      );
      final _ImmediateProcessExit? immediateExit = await _probeImmediateExit(
        process,
        timeout: _scrcpyStartProbeTimeout,
      );
      if (immediateExit == null) {
        _recordings[session.id] = _AndroidRecordingState.scrcpy(
          process: process,
        );
        return null;
      }
      _deleteOutputIfPresent(session.expectedOutputPath);
      return _ScrcpyStartFailure(
        <String>[
          'scrcpy exitCode: ${immediateExit.exitCode}',
          immediateExit.stdout,
          immediateExit.stderr,
        ],
      );
    } on Object catch (error) {
      _deleteOutputIfPresent(session.expectedOutputPath);
      return _ScrcpyStartFailure(<String>['scrcpy start failed: $error']);
    }
  }

  Future<_AndroidRecordingState> _startHostFrameCapture(
    RecordingSession session, {
    required List<String> startupDiagnostics,
  }) async {
    final ScreenRecorderCommandResult ffmpegResult = await _commandRunner.run(
      'ffmpeg',
      <String>['-version'],
    );
    if (ffmpegResult.exitCode != 0) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.missingDependency,
        message: 'Android fallback recording requires ffmpeg.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: _joinDiagnostics(
          <String>[...startupDiagnostics, ffmpegResult.stderr],
        ),
      );
    }
    final Directory frameDirectory =
        await Directory.systemTemp.createTemp('screen_recorder_${session.id}_');
    final _AndroidRecordingState state = _AndroidRecordingState.frameCapture(
      frameDirectory: frameDirectory,
      startupDiagnostics: startupDiagnostics,
    );
    try {
      await _captureFrame(session.device.id, state);
      state.captureLoop = _captureFramesUntilStopped(
        session.device.id,
        state,
      );
      return state;
    } on ScreenRecorderException {
      await frameDirectory.delete(recursive: true);
      rethrow;
    } on Object catch (error) {
      await frameDirectory.delete(recursive: true);
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'Failed to start Android fallback frame capture.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: _joinDiagnostics(startupDiagnostics),
        cause: error,
      );
    }
  }

  Future<void> _captureFramesUntilStopped(
    String deviceId,
    _AndroidRecordingState state,
  ) async {
    while (!state.stopRequested) {
      await Future<void>.delayed(_fallbackFrameInterval);
      if (state.stopRequested) {
        return;
      }
      try {
        await _captureFrame(deviceId, state);
      } on Object catch (error) {
        state.captureError = error;
        return;
      }
    }
  }

  Future<void> _captureFrame(
    String deviceId,
    _AndroidRecordingState state,
  ) async {
    final ScreenRecorderByteCommandResult result =
        await _commandRunner.runBytes(
      'adb',
      <String>['-s', deviceId, 'exec-out', 'screencap', '-p'],
    );
    if (result.exitCode != 0 || result.stdoutBytes.isEmpty) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.startFailed,
        message: 'ADB screencap failed during Android fallback recording.',
        backendKind: _backendKind,
        deviceSelector: deviceId,
        rawOutput: _joinDiagnostics(
          <String>[...state.startupDiagnostics, result.stderr],
        ),
      );
    }
    state.frameCount++;
    final String frameName =
        'frame_${state.frameCount.toString().padLeft(6, '0')}.png';
    final File frameFile = File(
      '${state.frameDirectory!.path}${Platform.pathSeparator}$frameName',
    );
    await frameFile.writeAsBytes(result.stdoutBytes);
  }

  Future<_ImmediateProcessExit?> _probeImmediateExit(
      ScreenRecorderProcess process,
      {required Duration timeout}) async {
    final Completer<int?> exitCode = Completer<int?>();
    final Timer timer = Timer(timeout, () {
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
    if (result == null) {
      return null;
    }
    return _ImmediateProcessExit(
      exitCode: result,
      stdout: await process.stdout,
      stderr: await process.stderr,
    );
  }

  bool _canFallbackToHostCapture(_ImmediateProcessExit exit) {
    final String output = '${exit.stdout}\n${exit.stderr}'.toLowerCase();
    return output.contains('permission denied') ||
        output.contains('unable to open');
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
    if (state.isFrameCapture) {
      await _stopHostFrameCapture(session, state);
      return;
    }
    if (state.isScrcpy) {
      await _stopScrcpyRecording(session, state);
      return;
    }
    final ScreenRecorderProcess process = state.process!;
    final String deviceTempPath = state.deviceTempPath!;
    final _AndroidStopResult stopResult = await _stopDeviceScreenrecord(
      session.device.id,
      process,
    );
    try {
      final ScreenRecorderCommandResult statResult = await _commandRunner.run(
        'adb',
        <String>['-s', session.device.id, 'shell', 'ls', '-l', deviceTempPath],
      );
      final ScreenRecorderCommandResult pullResult = await _commandRunner.run(
        'adb',
        <String>[
          '-s',
          session.device.id,
          'pull',
          deviceTempPath,
          session.expectedOutputPath,
        ],
      );
      if (pullResult.exitCode != 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.stopFailed,
          message: 'ADB command failed: adb -s ${session.device.id} pull '
              '$deviceTempPath ${session.expectedOutputPath}',
          backendKind: _backendKind,
          rawOutput: _joinDiagnostics(
            <String>[
              pullResult.stdout,
              pullResult.stderr,
              statResult.stdout,
              statResult.stderr,
              'screenrecord exitCode: ${stopResult.exitCode}',
              stopResult.stdout,
              stopResult.stderr,
            ],
          ),
        );
      }
      final File outputFile = File(session.expectedOutputPath);
      if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.stopFailed,
          message: 'Android recording output was not created.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
          rawOutput: _joinDiagnostics(
            <String>[
              statResult.stdout,
              statResult.stderr,
              'screenrecord exitCode: ${stopResult.exitCode}',
              stopResult.stdout,
              stopResult.stderr,
            ],
          ),
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
          deviceTempPath,
        ],
        ScreenRecorderErrorCode.stopFailed,
      );
    }
  }

  Future<void> _stopScrcpyRecording(
    RecordingSession session,
    _AndroidRecordingState state,
  ) async {
    final ScreenRecorderProcess process = state.process!;
    process.kill(ProcessSignal.sigterm);
    final int exitCode = await process.exitCode.timeout(
      _stopTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final String stdout = await process.stdout;
    final String stderr = await process.stderr;
    final File outputFile = File(session.expectedOutputPath);
    if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.stopFailed,
        message: 'scrcpy recording output was not created.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: _joinDiagnostics(
          <String>['scrcpy exitCode: $exitCode', stdout, stderr],
        ),
      );
    }
  }

  Future<void> _stopHostFrameCapture(
    RecordingSession session,
    _AndroidRecordingState state,
  ) async {
    state.stopRequested = true;
    await state.captureLoop?.timeout(
      _stopTimeout,
      onTimeout: () => null,
    );
    try {
      final Object? captureError = state.captureError;
      if (captureError != null && state.frameCount == 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.stopFailed,
          message: 'Android fallback frame capture did not produce frames.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
          rawOutput: _joinDiagnostics(state.startupDiagnostics),
          cause: captureError,
        );
      }
      final ScreenRecorderCommandResult result = await _commandRunner.run(
        'ffmpeg',
        <String>[
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-framerate',
          _fallbackFrameRate.toString(),
          '-i',
          '${state.frameDirectory!.path}${Platform.pathSeparator}frame_%06d.png',
          '-vf',
          'format=yuv420p',
          '-movflags',
          '+faststart',
          session.expectedOutputPath,
        ],
      );
      if (result.exitCode != 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.stopFailed,
          message: 'ffmpeg failed to encode Android fallback recording.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
          rawOutput: _joinDiagnostics(
            <String>[
              ...state.startupDiagnostics,
              result.stdout,
              result.stderr,
            ],
          ),
        );
      }
      final File outputFile = File(session.expectedOutputPath);
      if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.stopFailed,
          message: 'Android fallback recording output was not created.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
          rawOutput: _joinDiagnostics(state.startupDiagnostics),
        );
      }
    } finally {
      await state.frameDirectory?.delete(recursive: true);
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
    if (state.isFrameCapture) {
      state.stopRequested = true;
      await state.captureLoop?.timeout(
        _stopTimeout,
        onTimeout: () => null,
      );
      await state.frameDirectory?.delete(recursive: true);
      return;
    }
    if (state.isScrcpy) {
      state.process!.kill(ProcessSignal.sigterm);
      await state.process!.exitCode.timeout(
        _stopTimeout,
        onTimeout: () {
          state.process!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      final File outputFile = File(session.expectedOutputPath);
      if (outputFile.existsSync()) {
        outputFile.deleteSync();
      }
      return;
    }
    await _stopDeviceScreenrecord(session.device.id, state.process!);
    await _runAdb(
      <String>[
        '-s',
        session.device.id,
        'shell',
        'rm',
        '-f',
        state.deviceTempPath!
      ],
      ScreenRecorderErrorCode.discardFailed,
    );
  }

  /*
   * The methods below handle the native Android screenrecord flow. The host-side
   * fallback above is used only when screenrecord exits immediately because the
   * device refuses to open its output file.
   */

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

  Future<_AndroidStopResult> _stopDeviceScreenrecord(
    String deviceId,
    ScreenRecorderProcess process,
  ) async {
    final ScreenRecorderCommandResult psResult = await _runAdb(
      <String>['-s', deviceId, 'shell', 'ps', '-A'],
      ScreenRecorderErrorCode.stopFailed,
    );
    final List<String> processIds = _parseScreenrecordProcessIds(
      psResult.stdout,
    );
    if (processIds.isEmpty) {
      process.kill(ProcessSignal.sigint);
    } else {
      for (final String processId in processIds) {
        await _runAdb(
          <String>[
            '-s',
            deviceId,
            'shell',
            'kill',
            '-2',
            processId,
          ],
          ScreenRecorderErrorCode.stopFailed,
        );
      }
    }
    final int exitCode = await process.exitCode.timeout(
      _stopTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigterm);
        return -1;
      },
    );
    final String stdout = await process.stdout;
    final String stderr = await process.stderr;
    return _AndroidStopResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
    );
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

  static List<String> _parseScreenrecordProcessIds(String psOutput) {
    final List<String> processIds = <String>[];
    for (final String line in psOutput.split('\n')) {
      if (!line.contains('screenrecord')) {
        continue;
      }
      final List<String> columns = line.trim().split(RegExp(r'\s+'));
      if (columns.length < 2) {
        continue;
      }
      final String processId = columns[1];
      if (int.tryParse(processId) != null) {
        processIds.add(processId);
      }
    }
    return processIds;
  }

  static String _deviceTempPath(RecordingSession session) {
    final String safeSessionId = session.id.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]+'),
      '_',
    );
    return '/sdcard/screen_recorder_$safeSessionId.mp4';
  }

  static String _joinDiagnostics(List<String> values) {
    return values
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .join('\n');
  }

  static void _deleteOutputIfPresent(String outputPath) {
    final File outputFile = File(outputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }
}

class _ImmediateProcessExit {
  _ImmediateProcessExit({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _ScrcpyStartFailure {
  _ScrcpyStartFailure(this.diagnostics);

  final List<String> diagnostics;
}

class _AndroidStopResult {
  _AndroidStopResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _AndroidRecordingState {
  _AndroidRecordingState.scrcpy({
    required ScreenRecorderProcess this.process,
  })  : deviceTempPath = null,
        frameDirectory = null,
        startupDiagnostics = const <String>[];

  _AndroidRecordingState.native({
    required ScreenRecorderProcess this.process,
    required String this.deviceTempPath,
  })  : frameDirectory = null,
        startupDiagnostics = const <String>[];

  _AndroidRecordingState.frameCapture({
    required Directory this.frameDirectory,
    required this.startupDiagnostics,
  })  : process = null,
        deviceTempPath = null;

  final ScreenRecorderProcess? process;
  final String? deviceTempPath;
  final Directory? frameDirectory;
  final List<String> startupDiagnostics;
  Future<void>? captureLoop;
  Object? captureError;
  bool stopRequested = false;
  int frameCount = 0;

  bool get isFrameCapture => frameDirectory != null;

  bool get isScrcpy => process != null && deviceTempPath == null;
}
