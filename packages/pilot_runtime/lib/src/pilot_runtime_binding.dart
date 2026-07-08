import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:pilot_runtime_client/pilot_runtime_client.dart';

/// Handles one app-side Flutter Pilot service extension request.
///
/// The first runtime slice only needs a zero-argument handshake request. Later
/// capabilities can add their own typed request handlers without changing the
/// handshake registration contract.
typedef PilotRuntimeExtensionHandler = Future<Map<String, Object?>> Function();

/// Registers one Flutter Pilot service extension with the debug VM Service.
///
/// Tests can provide a fake registrar to inspect the extension name and invoke
/// the handler without launching a Flutter app. Production callers omit the
/// registrar so the binding registers through `dart:developer`.
typedef PilotRuntimeExtensionRegistrar =
    void Function(String extensionName, PilotRuntimeExtensionHandler handler);

/// App-side hook that exposes Flutter Pilot runtime service extensions.
///
/// Target App Packages call `ensureInitialized()` from app startup while
/// running in debug mode. The binding registers the protocol handshake
/// extension once per isolate and returns without side effects when debug mode
/// is disabled.
class PilotRuntimeBinding {
  PilotRuntimeBinding._();

  static bool _initialized = false;

  /// Register the Flutter Pilot debug runtime hook when debug mode is enabled.
  ///
  /// Args:
  /// - `registerExtension`: Optional registrar used by tests to avoid touching
  ///   the VM Service. When omitted, the binding registers through
  ///   `dart:developer.registerExtension`.
  /// - `debugMode`: Optional debug-mode override used by tests. When omitted,
  ///   Flutter's `kDebugMode` decides whether registration should happen.
  ///
  /// Returns without registering anything when debug mode is false. Repeated
  /// calls in the same isolate are idempotent.
  static void ensureInitialized({
    PilotRuntimeExtensionRegistrar? registerExtension,
    bool? debugMode,
  }) {
    final bool shouldRegister = debugMode ?? kDebugMode;
    if (!shouldRegister || _initialized) {
      return;
    }

    final PilotRuntimeExtensionRegistrar registrar =
        registerExtension ?? _registerVmServiceExtension;
    registrar(PilotRuntimeProtocol.handshakeExtension, _handleHandshake);
    _initialized = true;
  }

  /// Clear registration state for tests that verify binding behavior.
  ///
  /// This method does not unregister VM Service extensions. Tests should use a
  /// fake registrar when they need repeated isolated assertions.
  @visibleForTesting
  static void debugResetForTesting() {
    _initialized = false;
  }

  static Future<Map<String, Object?>> _handleHandshake() async {
    return PilotRuntimeHandshakeResponse.current().toJson();
  }

  static void _registerVmServiceExtension(
    String extensionName,
    PilotRuntimeExtensionHandler handler,
  ) {
    registerExtension(extensionName, (
      String method,
      Map<String, String> parameters,
    ) async {
      final Map<String, Object?> payload = await handler();
      return ServiceExtensionResponse.result(jsonEncode(payload));
    });
  }
}
