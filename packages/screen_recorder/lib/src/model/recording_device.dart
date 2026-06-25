/// Recording Device model and supported backend platform families.
///
/// A Recording Device is a device that can be selected as the source for a
/// Recording Session. It is intentionally separate from Flutter Runtime Target
/// identity.
library;

/// Supported Recording Device platform families.
enum RecordingDevicePlatform {
  /// Android devices discovered through Android Debug Bridge.
  android,

  /// iOS simulators discovered through simulator tooling.
  iosSimulator,

  /// Physical iOS devices discovered through native screen capture discovery.
  iosPhysical,
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
