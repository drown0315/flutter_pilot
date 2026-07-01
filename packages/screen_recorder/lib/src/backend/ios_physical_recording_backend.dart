import 'dart:io';
import 'dart:isolate';

import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_session.dart';
import '../process/command_runner.dart';
import 'recording_backend.dart';

/// Physical iOS recording backend implemented through the in-package Swift helper.

class IosPhysicalRecordingBackend implements RecordingBackend {
  IosPhysicalRecordingBackend(this._commandRunner);

  static const String _backendKind = 'iosPhysical';
  static const Duration _stopTimeout = Duration(seconds: 10);

  final ScreenRecorderCommandRunner _commandRunner;
  final Map<String, ScreenRecorderProcess> _recordings =
      <String, ScreenRecorderProcess>{};
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
    final List<RecordingDevice> devices = _parseDevices(result.stdout);
    try {
      final ScreenRecorderCommandResult xctraceResult =
          await _commandRunner.run('xcrun', <String>[
        'xctrace',
        'list',
        'devices',
      ]);
      if (xctraceResult.exitCode == 0) {
        _addMissingDevices(devices, _parseXctraceDevices(xctraceResult.stdout));
      }
    } on Object {
      // The helper remains the source of recordable AVFoundation devices.
      // xctrace discovery is best-effort metadata for physical devices that
      // Xcode can run but AVFoundation does not expose as capture sources.
    }
    return devices;
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
    final String helperPath = await _ensureHelperBuilt();
    try {
      final ScreenRecorderProcess process =
          await _commandRunner.start(helperPath, <String>[
        'record',
        '--device-id',
        session.device.id,
        '--output',
        session.expectedOutputPath,
      ]);
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
    final int exitCode = await process.exitCode.timeout(
      _stopTimeout + Duration(seconds: 5),
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
        message: 'Physical iOS recording output was not created.',
        backendKind: _backendKind,
        deviceSelector: session.device.id,
        rawOutput: [
          'helper exitCode: $exitCode',
          'output exists: ${outputFile.existsSync()}',
          if (outputFile.existsSync())
            'output size: ${outputFile.lengthSync()}',
          stdout,
          stderr,
        ].where((String s) => s.isNotEmpty).join('\n'),
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
    await process.exitCode.timeout(
      _stopTimeout + Duration(seconds: 5),
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

  static List<RecordingDevice> _parseXctraceDevices(String output) {
    final List<RecordingDevice> devices = <RecordingDevice>[];
    var inDevicesSection = false;
    for (final String line in output.split('\n')) {
      final String trimmedLine = line.trim();
      if (trimmedLine == '== Devices ==') {
        inDevicesSection = true;
        continue;
      }
      if (trimmedLine.startsWith('== ') && trimmedLine.endsWith(' ==')) {
        inDevicesSection = false;
        continue;
      }
      if (!inDevicesSection || trimmedLine.isEmpty) {
        continue;
      }
      final RegExpMatch? match = RegExp(
        r'^(.*?)(?: \([^)]+\))? \(([0-9a-fA-F]{40})\)$',
      ).firstMatch(trimmedLine);
      if (match == null) {
        continue;
      }
      devices.add(
        RecordingDevice(
          id: match.group(2)!,
          name: match.group(1)!.trim(),
          platform: RecordingDevicePlatform.iosPhysical,
        ),
      );
    }
    return devices;
  }

  static void _addMissingDevices(
    List<RecordingDevice> target,
    List<RecordingDevice> additions,
  ) {
    final Set<String> existingIds =
        target.map((RecordingDevice device) => device.id).toSet();
    for (final RecordingDevice device in additions) {
      if (existingIds.add(device.id)) {
        target.add(device);
      }
    }
  }
}
