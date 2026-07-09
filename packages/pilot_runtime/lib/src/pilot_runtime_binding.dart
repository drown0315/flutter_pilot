import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'finder_resolver.dart';
import 'pilot_runtime_protocol.dart';
import 'scroll_performer.dart';
import 'tap_performer.dart';
import 'text_performer.dart';

/// Handles one app-side Flutter Pilot service extension request.
///
/// The first runtime slice only needs a zero-argument handshake request. Later
/// capabilities can add their own typed request handlers without changing the
/// handshake registration contract.
typedef PilotRuntimeExtensionHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> parameters);

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
    registrar(
      PilotRuntimeProtocol.resolveFinderExtension,
      _handleResolveFinder,
    );
    registrar(PilotRuntimeProtocol.tapExtension, _handleTap);
    registrar(PilotRuntimeProtocol.clearTextExtension, _handleClearText);
    registrar(PilotRuntimeProtocol.enterTextExtension, _handleEnterText);
    registrar(PilotRuntimeProtocol.scrollExtension, _handleScroll);
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

  static Future<Map<String, Object?>> _handleHandshake(
    Map<String, Object?> parameters,
  ) async {
    return PilotRuntimeHandshakeResponse.current().toJson();
  }

  static Future<Map<String, Object?>> _handleResolveFinder(
    Map<String, Object?> parameters,
  ) async {
    return PilotRuntimeFinderResolver.resolve(
      byText: _optionalString(parameters, 'byText'),
      byType: _optionalString(parameters, 'byType'),
      byKey: _optionalString(parameters, 'byKey'),
      byWidget: _optionalString(parameters, 'byWidget'),
    );
  }

  static Future<Map<String, Object?>> _handleTap(
    Map<String, Object?> parameters,
  ) async {
    return PilotRuntimeTapPerformer.tap(
      handle: _requiredString(parameters, 'handle', 'tap'),
    );
  }

  static Future<Map<String, Object?>> _handleClearText(
    Map<String, Object?> parameters,
  ) async {
    return PilotRuntimeTextPerformer.clearText(
      handle: _requiredString(parameters, 'handle', 'clearText'),
    );
  }

  static Future<Map<String, Object?>> _handleEnterText(
    Map<String, Object?> parameters,
  ) async {
    return PilotRuntimeTextPerformer.enterText(
      handle: _requiredString(parameters, 'handle', 'enterText'),
      text: _requiredString(parameters, 'text', 'enterText'),
    );
  }

  static Future<Map<String, Object?>> _handleScroll(
    Map<String, Object?> parameters,
  ) async {
    return PilotRuntimeScrollPerformer.scroll(
      handle: _optionalString(parameters, 'handle'),
      deltaX: _requiredDouble(parameters, 'deltaX', 'scroll'),
      deltaY: _requiredDouble(parameters, 'deltaY', 'scroll'),
    );
  }

  static String? _optionalString(
    Map<String, Object?> parameters,
    String field,
  ) {
    final Object? value = parameters[field];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('resolveFinder parameter $field must be a string.');
  }

  static String _requiredString(
    Map<String, Object?> parameters,
    String field,
    String operation,
  ) {
    final Object? value = parameters[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('$operation parameter $field must be a string.');
  }

  static double _requiredDouble(
    Map<String, Object?> parameters,
    String field,
    String operation,
  ) {
    final Object? value = parameters[field];
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    if (value is String) {
      final double? parsedValue = double.tryParse(value);
      if (parsedValue != null) {
        return parsedValue;
      }
    }
    throw FormatException('$operation parameter $field must be a number.');
  }

  static void _registerVmServiceExtension(
    String extensionName,
    PilotRuntimeExtensionHandler handler,
  ) {
    registerExtension(extensionName, (
      String method,
      Map<String, String> parameters,
    ) async {
      final Map<String, Object?> payload = await handler(
        Map<String, Object?>.from(parameters),
      );
      return ServiceExtensionResponse.result(jsonEncode(payload));
    });
  }
}
