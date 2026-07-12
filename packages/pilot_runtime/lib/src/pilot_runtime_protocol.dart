/// Protocol constants shared by the app-side hook and VM Service client.
///
/// Version 1 exposes runtime handshake, visible Finder resolution, tap,
/// editable text entry, scroll replay, and runtime log collection.
class PilotRuntimeProtocol {
  PilotRuntimeProtocol._();

  /// First accepted protocol version for `pilot_runtime`.
  static const int version = 1;

  /// VM Service extension used to verify that the app-side hook is installed.
  static const String handshakeExtension =
      'ext.flutter_pilot.runtime.handshake';

  /// VM Service extension used to resolve visible Runtime Target Finder Matches.
  static const String resolveFinderExtension =
      'ext.flutter_pilot.runtime.resolveFinder';

  /// VM Service extension used to wait for the current or next frame.
  static const String endOfFrameExtension =
      'ext.flutter_pilot.runtime.endOfFrame';

  /// VM Service extension used to tap one resolved Runtime Handle.
  static const String tapExtension = 'ext.flutter_pilot.runtime.tap';

  /// VM Service extension used to clear one editable text Runtime Handle.
  static const String clearTextExtension =
      'ext.flutter_pilot.runtime.clearText';

  /// VM Service extension used to append text to one editable text handle.
  static const String enterTextExtension =
      'ext.flutter_pilot.runtime.enterText';

  /// VM Service extension used to drag one scrollable Runtime Handle.
  static const String scrollExtension = 'ext.flutter_pilot.runtime.scroll';

  /// VM Service extension used to collect buffered Flutter runtime logs.
  static const String collectLogsExtension =
      'ext.flutter_pilot.runtime.collectLogs';

  /// Capability name reported when the handshake extension is available.
  static const String handshakeCapability = 'runtime.handshake';

  /// Capability name reported when visible Finder resolution is available.
  static const String resolveFinderCapability = 'runtime.finder.resolve';

  /// Capability name reported when frame synchronization is available.
  static const String endOfFrameCapability = 'runtime.frame.end';

  /// Capability name reported when tap replay is available.
  static const String tapCapability = 'runtime.action.tap';

  /// Capability name reported when editable text can be cleared directly.
  static const String clearTextCapability = 'runtime.action.clearText';

  /// Capability name reported when editable text can receive entered text.
  static const String enterTextCapability = 'runtime.action.enterText';

  /// Capability name reported when scroll replay is available.
  static const String scrollCapability = 'runtime.action.scroll';

  /// Capability name reported when runtime logs can be collected.
  static const String collectLogsCapability = 'runtime.logs.collect';

  /// Capabilities that this client requires before Scenario execution.
  static const Set<String> requiredCapabilities = <String>{
    handshakeCapability,
    resolveFinderCapability,
    endOfFrameCapability,
    tapCapability,
    clearTextCapability,
    enterTextCapability,
    scrollCapability,
    collectLogsCapability,
  };
}

/// Flutter Inspector service extension names and arguments used by the client.
///
/// Widget Tree capture first configures the Target App Package pub root and
/// then requests the compact root Widget Tree with text previews. Flutter
/// Inspector expects boolean-like options as strings in VM Service parameters.
class PilotRuntimeInspectorProtocol {
  PilotRuntimeInspectorProtocol._();

  /// Extension that tells Inspector which package roots count as local project.
  static const String setPubRootDirectoriesExtension =
      'ext.flutter.inspector.setPubRootDirectories';

  /// Extension that returns the root diagnostics Widget Tree.
  static const String getRootWidgetTreeExtension =
      'ext.flutter.inspector.getRootWidgetTree';

  /// Deterministic Inspector group for Widget Tree capture objects.
  static const String widgetTreeGroupName = 'pilot_runtime_widget_tree';

  /// Parameters for the normalized Widget Tree source request.
  static const Map<String, Object?> summaryTreeParameters = <String, Object?>{
    'groupName': widgetTreeGroupName,
    'isSummaryTree': 'true',
    'withPreviews': 'true',
    'fullDetails': 'false',
  };
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
