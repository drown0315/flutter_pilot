import 'dart:io';

import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_session.dart';
import '../process/command_runner.dart';
import 'recording_backend.dart';

/// Physical iOS recording backend implemented through the in-package Swift helper.

class IosPhysicalRecordingBackend implements RecordingBackend {
  IosPhysicalRecordingBackend(this._commandRunner);

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
