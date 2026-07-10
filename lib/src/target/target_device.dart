/// Target Device models and resolution rules for Scenario test runs.
///
/// A Target Device is selected from Flutter's device list and remains separate
/// from Recording Device backend details. The resolver can return `null` when
/// a non-recording run intentionally lets Flutter choose its default device.
library;

import 'dart:convert';

/// Flutter Device data used to select a Target Device.
///
/// The fields mirror the stable values Flutter exposes through
/// `flutter devices --machine` that Flutter Pilot needs for app launch and run
/// reports.
class FlutterDevice {
  /// Creates a Flutter Device record from Flutter tooling data.
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.isSupported,
    required this.emulator,
    required this.sdk,
  });

  /// Stable Flutter Device id passed to `flutter run --device-id`.
  final String id;

  /// Human-readable Flutter Device name.
  final String name;

  /// Flutter target platform string, such as `android-arm64` or `ios`.
  final String targetPlatform;

  /// Whether Flutter reports the device as supported for the current app.
  final bool isSupported;

  /// Whether Flutter reports this device as an emulator or simulator.
  final bool emulator;

  /// Flutter-reported SDK description for display and reports.
  final String sdk;
}

/// Recording Device identity used for id-only Target Device alignment.
///
/// This keeps Target Device resolution independent from `screen_recorder`
/// backend objects while preserving the only field needed for consistency:
/// the Recording Device id.
class RecordingDeviceIdentity {
  /// Creates a Recording Device identity for Target Device matching.
  const RecordingDeviceIdentity({required this.id});

  /// Backend-specific Recording Device id.
  final String id;
}

/// Target Device selected for a Scenario test run.
///
/// It carries Flutter Device metadata for launch and reporting. It intentionally
/// omits Flutter capabilities and Recording Device backend details.
class TargetDevice {
  /// Creates the Target Device model used by Flutter Pilot.
  const TargetDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.emulator,
    required this.sdk,
  });

  /// Flutter Device id used to launch the Target App Package.
  final String id;

  /// Human-readable Flutter Device name.
  final String name;

  /// Flutter target platform string.
  final String targetPlatform;

  /// Whether Flutter reports this device as an emulator or simulator.
  final bool emulator;

  /// Flutter-reported SDK description.
  final String sdk;
}

/// Failure raised when Target Device resolution cannot select exactly one device.
///
/// CLI code should present `message` to the user and map this exception to a
/// usage error because resolution fails before app launch or run artifacts.
class TargetDeviceResolutionException implements Exception {
  /// Creates a Target Device resolution failure.
  const TargetDeviceResolutionException(this.message);

  /// Human-readable Target Device selection error.
  final String message;

  @override
  String toString() {
    return message;
  }
}

/// Parses Flutter Device records from `flutter devices --machine` output.
class TargetDeviceParser {
  TargetDeviceParser._();

  /// Parse Flutter's machine-readable device list.
  ///
  /// Args:
  /// `machineJson` is the stdout from `flutter devices --machine`.
  ///
  /// Returns:
  /// Flutter Device records preserving supported and unsupported devices so the
  /// resolver can distinguish unsupported selectors from missing selectors.
  static List<FlutterDevice> parseMachineJson(String machineJson) {
    final Object? decoded = jsonDecode(machineJson);
    if (decoded is! List<Object?>) {
      throw const FormatException('Expected a Flutter Device list.');
    }
    return <FlutterDevice>[
      for (final Object? item in decoded) _parseDevice(item),
    ];
  }

  /// Parse one Flutter Device JSON object.
  static FlutterDevice _parseDevice(Object? item) {
    if (item is! Map<String, Object?>) {
      throw const FormatException('Expected a Flutter Device object.');
    }
    return FlutterDevice(
      id: _readString(item, 'id'),
      name: _readString(item, 'name'),
      targetPlatform: _readString(item, 'targetPlatform'),
      isSupported: _readBool(item, 'isSupported'),
      emulator: _readBool(item, 'emulator'),
      sdk: _readString(item, 'sdk'),
    );
  }

  /// Read a required string field from a Flutter Device object.
  static String _readString(Map<String, Object?> item, String field) {
    final Object? value = item[field];
    if (value is String) {
      return value;
    }
    throw FormatException('Expected Flutter Device field "$field" as string.');
  }

  /// Read a required boolean field from a Flutter Device object.
  static bool _readBool(Map<String, Object?> item, String field) {
    final Object? value = item[field];
    if (value is bool) {
      return value;
    }
    throw FormatException('Expected Flutter Device field "$field" as boolean.');
  }
}

/// Resolves user Target Device selectors against Flutter and Recording Devices.
class TargetDeviceResolver {
  TargetDeviceResolver._();

  /// Resolve a Target Device for a Scenario test run.
  ///
  /// Args:
  /// `selector` is the optional user `--device` value.
  /// `recordingRequired` tells whether Scenario Recording requires id alignment
  /// with a Recording Device.
  /// `flutterDevices` are devices discovered from Flutter tooling.
  /// `recordingDevices` are Recording Device identities available for capture.
  ///
  /// Returns:
  /// A Target Device, or `null` when no selector is provided and recording is
  /// not required.
  static TargetDevice? resolve({
    required String? selector,
    required bool recordingRequired,
    required List<FlutterDevice> flutterDevices,
    required List<RecordingDeviceIdentity> recordingDevices,
  }) {
    if (selector == null && !recordingRequired) {
      return null;
    }
    final List<FlutterDevice> supportedDevices = <FlutterDevice>[
      for (final FlutterDevice device in flutterDevices)
        if (device.isSupported) device,
    ];
    final Set<String> recordingDeviceIds = <String>{
      for (final RecordingDeviceIdentity device in recordingDevices) device.id,
    };
    if (selector == null && recordingRequired) {
      final List<FlutterDevice> recordableDevices = <FlutterDevice>[
        for (final FlutterDevice device in supportedDevices)
          if (recordingDeviceIds.contains(device.id)) device,
      ];
      if (recordableDevices.length == 1) {
        return _targetFromFlutterDevice(recordableDevices.single);
      }
      if (recordableDevices.isEmpty) {
        throw const TargetDeviceResolutionException(
          'No recordable Target Device is available. Pass --device with a Flutter Device id that is also a Recording Device id.',
        );
      }
      throw TargetDeviceResolutionException(
        'Multiple recordable Target Devices are available. Pass --device with one of: '
        '${_formatCandidates(recordableDevices)}.',
      );
    }
    final String? normalizedSelector = selector?.trim();
    if (normalizedSelector == null || normalizedSelector.isEmpty) {
      throw const TargetDeviceResolutionException(
        'Target Device selector must not be empty.',
      );
    }
    final _TargetDeviceMatch selectedDevice = _resolveBySelector(
      normalizedSelector,
      supportedDevices,
    );
    if (selectedDevice case _SelectedTargetDeviceMatch(:final device)) {
      if (recordingRequired && !recordingDeviceIds.contains(device.id)) {
        throw TargetDeviceResolutionException(
          'Target Device ${device.id} (${device.name}) is not available as a Recording Device.',
        );
      }
      return _targetFromFlutterDevice(device);
    }
    final bool unsupportedExactMatch = flutterDevices.any(
      (FlutterDevice device) =>
          !device.isSupported &&
          (device.id == normalizedSelector ||
              device.name == normalizedSelector),
    );
    if (unsupportedExactMatch) {
      throw TargetDeviceResolutionException(
        'unsupported Target Device "$normalizedSelector".',
      );
    }
    if (selectedDevice case _AmbiguousTargetDeviceMatch(:final devices)) {
      throw TargetDeviceResolutionException(
        'ambiguous Target Device selector "$normalizedSelector". Candidates: '
        '${_formatCandidates(devices)}.',
      );
    }
    throw TargetDeviceResolutionException(
      'No Target Device matches "$normalizedSelector".',
    );
  }

  /// Resolve a non-empty selector against supported Flutter Devices.
  ///
  /// Exact id and exact name matches are preferred before unique id or name
  /// prefixes.
  static _TargetDeviceMatch _resolveBySelector(
    String selector,
    List<FlutterDevice> devices,
  ) {
    for (final FlutterDevice device in devices) {
      if (device.id == selector || device.name == selector) {
        return _TargetDeviceMatch.selected(device);
      }
    }
    final List<FlutterDevice> prefixMatches = <FlutterDevice>[
      for (final FlutterDevice device in devices)
        if (device.id.startsWith(selector) || device.name.startsWith(selector))
          device,
    ];
    if (prefixMatches.length == 1) {
      return _TargetDeviceMatch.selected(prefixMatches.single);
    }
    if (prefixMatches.length > 1) {
      return _TargetDeviceMatch.ambiguous(prefixMatches);
    }
    return const _TargetDeviceMatch.none();
  }

  /// Convert a Flutter Device into the public Target Device model.
  static TargetDevice _targetFromFlutterDevice(FlutterDevice device) {
    return TargetDevice(
      id: device.id,
      name: device.name,
      targetPlatform: device.targetPlatform,
      emulator: device.emulator,
      sdk: device.sdk,
    );
  }

  /// Format Target Device candidates for user-facing ambiguity errors.
  static String _formatCandidates(List<FlutterDevice> devices) {
    return devices
        .map((FlutterDevice device) => '${device.id} (${device.name})')
        .join(', ');
  }
}

/// Internal result for selector matching before errors are rendered.
sealed class _TargetDeviceMatch {
  const factory _TargetDeviceMatch.selected(FlutterDevice device) =
      _SelectedTargetDeviceMatch;

  const factory _TargetDeviceMatch.ambiguous(List<FlutterDevice> devices) =
      _AmbiguousTargetDeviceMatch;

  const factory _TargetDeviceMatch.none() = _NoTargetDeviceMatch;
}

class _SelectedTargetDeviceMatch implements _TargetDeviceMatch {
  const _SelectedTargetDeviceMatch(this.device);

  final FlutterDevice device;
}

class _AmbiguousTargetDeviceMatch implements _TargetDeviceMatch {
  const _AmbiguousTargetDeviceMatch(this.devices);

  final List<FlutterDevice> devices;
}

class _NoTargetDeviceMatch implements _TargetDeviceMatch {
  const _NoTargetDeviceMatch();
}
