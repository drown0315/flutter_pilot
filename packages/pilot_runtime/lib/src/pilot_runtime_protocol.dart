/// Protocol constants shared by the app-side hook and VM Service client.
///
/// Version 1 exposes only the runtime handshake. Later runtime capabilities add
/// capability names while keeping the version gate explicit.
class PilotRuntimeProtocol {
  PilotRuntimeProtocol._();

  /// First accepted protocol version for `pilot_runtime`.
  static const int version = 1;

  /// VM Service extension used to verify that the app-side hook is installed.
  static const String handshakeExtension =
      'ext.flutter_pilot.runtime.handshake';

  /// Capability name reported when the handshake extension is available.
  static const String handshakeCapability = 'runtime.handshake';

  /// Capabilities that this client requires before Scenario execution.
  static const Set<String> requiredCapabilities = <String>{handshakeCapability};
}

/// Versioned response returned by the app-side runtime handshake.
///
/// The response contains the protocol version spoken by the Runtime Target and
/// the capability names that the client may use after initialization.
class PilotRuntimeHandshakeResponse {
  /// Create a handshake response from decoded protocol fields.
  const PilotRuntimeHandshakeResponse({
    required this.protocolVersion,
    required this.capabilities,
  });

  /// Create the current app-side handshake response.
  factory PilotRuntimeHandshakeResponse.current() {
    return const PilotRuntimeHandshakeResponse(
      protocolVersion: PilotRuntimeProtocol.version,
      capabilities: PilotRuntimeProtocol.requiredCapabilities,
    );
  }

  /// Decode one VM Service handshake payload.
  ///
  /// Args:
  /// - `json`: Decoded JSON object returned by the Runtime Target.
  ///
  /// Returns a typed handshake response when `protocolVersion` is an integer
  /// and `capabilities` is a list of strings. Throws `FormatException` when a
  /// required field is missing or cannot be parsed.
  factory PilotRuntimeHandshakeResponse.fromJson(Map<String, Object?> json) {
    final Object? protocolVersionValue = json['protocolVersion'];
    if (protocolVersionValue is! int) {
      throw const FormatException(
        'pilot_runtime handshake must include integer protocolVersion.',
      );
    }

    final Object? capabilitiesValue = json['capabilities'];
    if (capabilitiesValue is! List<Object?>) {
      throw const FormatException(
        'pilot_runtime handshake must include string capabilities.',
      );
    }

    final Set<String> capabilities = <String>{};
    for (final Object? capability in capabilitiesValue) {
      if (capability is! String) {
        throw const FormatException(
          'pilot_runtime handshake capabilities must be strings.',
        );
      }
      capabilities.add(capability);
    }

    return PilotRuntimeHandshakeResponse(
      protocolVersion: protocolVersionValue,
      capabilities: Set<String>.unmodifiable(capabilities),
    );
  }

  /// Runtime protocol version spoken by the Runtime Target.
  final int protocolVersion;

  /// Capability names reported by the Runtime Target.
  final Set<String> capabilities;

  /// Encode this response for a VM Service extension result.
  ///
  /// Returns a JSON-compatible map with `protocolVersion` and `capabilities`
  /// fields. The capability list is sorted for deterministic tests and logs.
  Map<String, Object?> toJson() {
    final List<String> sortedCapabilities = capabilities.toList()..sort();
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'capabilities': sortedCapabilities,
    };
  }
}
