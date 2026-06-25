import 'dart:io';

import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_session.dart';
import '../process/command_runner.dart';
import 'recording_backend.dart';

/// iOS Simulator recording backend implemented through xcrun simctl.

class IosSimulatorRecordingBackend implements RecordingBackend {
  IosSimulatorRecordingBackend(this._commandRunner);

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
