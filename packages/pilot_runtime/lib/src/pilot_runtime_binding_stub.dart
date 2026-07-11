/// App-side runtime binding placeholder for non-Flutter Dart consumers.
///
/// The real `PilotRuntimeBinding` is exported from `pilot_runtime.dart` only
/// when `dart:ui` is available. Dart CLI code can still import the package's
/// single public entrypoint without pulling Flutter framework libraries.
class PilotRuntimeBinding {
  PilotRuntimeBinding._();

  /// Always fails because the runtime binding can only run inside Flutter.
  static void ensureInitialized({
    PilotRuntimeExtensionRegistrar? registerExtension,
    bool? debugMode,
    bool? captureLogs,
  }) {
    throw UnsupportedError(
      'PilotRuntimeBinding.ensureInitialized() is only available in Flutter.',
    );
  }

  /// Clear registration state in Flutter tests.
  static void debugResetForTesting() {}
}

/// Handles one app-side Flutter Pilot service extension request.
typedef PilotRuntimeExtensionHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> parameters);

/// Registers one Flutter Pilot service extension with the debug VM Service.
typedef PilotRuntimeExtensionRegistrar =
    void Function(String extensionName, PilotRuntimeExtensionHandler handler);
