import 'dart:async';
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
  static const Duration _startProbeTimeout = Duration(seconds: 1);
  static const Duration _stopTimeout = Duration(seconds: 10);

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
      final String simctlPath = await _resolveSimctlPath();
      final ScreenRecorderProcess process = await _commandRunner.start(
        simctlPath,
        <String>[
          'io',
          session.device.id,
          'recordVideo',
          session.expectedOutputPath,
        ],
      );
      final int? immediateExitCode = await _probeImmediateExit(process);
      if (immediateExitCode != null) {
        throw ScreenRecorderException(
          code: ScreenRecorderErrorCode.startFailed,
          message: 'iOS Simulator recordVideo exited immediately.',
          backendKind: _backendKind,
          deviceSelector: session.device.id,
          rawOutput: _joinDiagnostics(
            <String>[
              'simctl exitCode: $immediateExitCode',
              await process.stdout,
              await process.stderr,
            ],
          ),
        );
      }
      _recordings[session.id] = process;
    } on ScreenRecorderException {
      rethrow;
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

  Future<String> _resolveSimctlPath() async {
    final ScreenRecorderCommandResult result = await _commandRunner.run(
      'xcrun',
      <String>['--find', 'simctl'],
    );
    if (result.exitCode != 0 || result.stdout.trim().isEmpty) {
      throw ScreenRecorderException(
        code: ScreenRecorderErrorCode.missingDependency,
        message: 'Failed to locate simctl.',
        backendKind: _backendKind,
        rawOutput: '${result.stdout}${result.stderr}',
      );
    }
    return result.stdout.trim();
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
    process.kill(ProcessSignal.sigint);
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
        message: 'iOS Simulator recording output was not created.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: _joinDiagnostics(
          <String>[
            'simctl exitCode: $exitCode',
            'output exists: ${outputFile.existsSync()}',
            if (outputFile.existsSync())
              'output size: ${outputFile.lengthSync()}',
            stdout,
            stderr,
          ],
        ),
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
    process.kill(ProcessSignal.sigint);
    await process.exitCode.timeout(
      _stopTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
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
      final String state = deviceMatch.group(3)!;
      if (suffix.contains('unavailable') || state != 'Booted') {
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

  static String _joinDiagnostics(List<String> values) {
    return values
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .join('\n');
  }
}
