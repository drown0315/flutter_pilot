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
