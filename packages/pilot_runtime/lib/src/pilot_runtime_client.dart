import 'dart:convert';

import 'pilot_runtime_protocol.dart';
import 'widget_tree_normalizer.dart';

/// Minimal VM Service surface used by `PilotRuntimeClient`.
///
/// A concrete adapter calls service extensions on the target isolate and
/// returns decoded JSON maps. Unit tests provide fakes so the client can verify
/// protocol behavior without launching a Flutter app.
abstract interface class PilotRuntimeVmService {
  /// Call a Flutter Pilot service extension on the Runtime Target.
  ///
  /// Args:
  /// - `extensionName`: Full VM Service extension name, such as
  ///   `ext.flutter_pilot.runtime.handshake`.
  /// - `parameters`: JSON-compatible VM Service extension arguments. Flutter
  ///   Inspector expects string values for its boolean-like flags, so callers
  ///   pass normalized strings instead of Dart booleans.
  ///
  /// Returns the decoded JSON object returned by the extension. Implementations
  /// throw `PilotRuntimeServiceExtensionMissingException` when the extension is
  /// not registered on the Runtime Target.
  Future<Map<String, Object?>> callServiceExtension(
    String extensionName, {
    Map<String, Object?> parameters = const <String, Object?>{},
  });

  /// Request VM Service source reload for the selected Runtime Target isolate.
  ///
  /// Args:
  /// - `force`: `false` performs Flutter hot reload semantics. `true` forces a
  ///   full source reload and is used by Flutter Pilot as the hot restart
  ///   client capability.
  ///
  /// Returns the decoded VM Service reload report so the client can normalize
  /// success and failure into Flutter Pilot-owned result types.
  Future<Map<String, Object?>> reloadSources({required bool force});
}

/// Signals that a required Flutter Pilot service extension is not registered.
///
/// VM Service adapters throw this exception when a Runtime Target does not have
/// `PilotRuntimeBinding.ensureInitialized()` active in the app isolate.
class PilotRuntimeServiceExtensionMissingException implements Exception {
  /// Create a missing-extension failure for one VM Service extension name.
  const PilotRuntimeServiceExtensionMissingException(this.extensionName);

  /// Full VM Service extension name that could not be called.
  final String extensionName;

  @override
  String toString() {
    return 'PilotRuntimeServiceExtensionMissingException: '
        '$extensionName is not registered.';
  }
}

/// Initialization failure category reported by `PilotRuntimeClient`.
///
/// Flutter Pilot maps these values to run-level initialization failures before
/// any Scenario Step executes.
enum PilotRuntimeInitializationFailure {
  /// The Runtime Target does not expose the Flutter Pilot runtime hook.
  missingHook,

  /// The handshake response omits a capability required by this client.
  missingCapability,

  /// The Runtime Target speaks a protocol version this client does not accept.
  protocolVersionMismatch,

  /// The handshake response is not shaped like a Flutter Pilot protocol reply.
  invalidHandshake,
}

/// Clear initialization failure thrown by `PilotRuntimeClient.initialize()`.
///
/// The exception identifies the failure category, includes a user-facing
/// message, and can carry the original VM Service error when one caused the
/// failure.
class PilotRuntimeInitializationException implements Exception {
  /// Create a runtime initialization failure.
  const PilotRuntimeInitializationException({
    required this.failure,
    required this.message,
    this.cause,
  });

  /// Machine-readable failure category for adapter and runner mapping.
  final PilotRuntimeInitializationFailure failure;

  /// Human-readable explanation of the initialization failure.
  final String message;

  /// Original lower-level error when the VM Service call failed.
  final Object? cause;

  @override
  String toString() {
    return 'PilotRuntimeInitializationException: $message';
  }
}

/// Widget Tree capture failure category reported by `PilotRuntimeClient`.
///
/// Flutter Pilot can map these values to capture-step failures while preserving
/// the underlying VM Service or normalization error as context.
enum PilotRuntimeWidgetTreeCaptureFailure {
  /// Inspector failed while configuring Target App Package pub root directories.
  setPubRootDirectoriesFailed,

  /// Inspector failed while returning the root summary Widget Tree.
  getRootWidgetTreeFailed,

  /// Inspector returned a tree shape that cannot be normalized safely.
  invalidResponse,
}

/// Clear failure thrown by `PilotRuntimeClient.captureWidgetTree()`.
///
/// The exception identifies which capture stage failed and includes a message
/// suitable for run reports. The original lower-level error is retained when
/// one caused the failure.
class PilotRuntimeWidgetTreeCaptureException implements Exception {
  /// Create a Widget Tree capture failure.
  const PilotRuntimeWidgetTreeCaptureException({
    required this.failure,
    required this.message,
    this.cause,
  });

  /// Machine-readable Widget Tree capture failure category.
  final PilotRuntimeWidgetTreeCaptureFailure failure;

  /// Human-readable explanation of the capture failure.
  final String message;

  /// Original VM Service or normalization error when available.
  final Object? cause;

  @override
  String toString() {
    return 'PilotRuntimeWidgetTreeCaptureException: $message';
  }
}

/// Runtime action failure category reported by `PilotRuntimeClient`.
///
/// These failures come from a structured `pilot_runtime` action response rather
/// than from VM Service exception text.
enum PilotRuntimeActionFailure {
  /// A resolved Runtime Handle cannot receive the requested tap action.
  notTappable,

  /// A resolved Runtime Handle cannot receive editable text actions.
  notEditableText,

  /// A resolved Runtime Handle cannot receive scroll drag gestures.
  notScrollable,

  /// The primary scrollable is missing or ambiguous for untargeted scroll.
  primaryScrollableUnavailable,

  /// The app-side runtime returned an action failure code this client does not
  /// understand yet.
  unknown,
}

/// Clear failure thrown when a runtime action cannot complete.
///
/// The exception preserves the structured app-side failure category and exposes
/// a user-facing message suitable for Flutter Pilot Step failure reports.
class PilotRuntimeActionException implements Exception {
  /// Create a runtime action failure.
  const PilotRuntimeActionException({
    required this.failure,
    required this.message,
    this.cause,
  });

  /// Machine-readable action failure category.
  final PilotRuntimeActionFailure failure;

  /// Human-readable explanation of the action failure.
  final String message;

  /// Original structured response or lower-level error when available.
  final Object? cause;

  @override
  String toString() {
    return 'PilotRuntimeActionException: $message';
  }
}

/// Runtime lifecycle operation requested through VM Service source reload.
enum PilotRuntimeReloadOperation {
  /// Hot reload updates modified source without forcing a full restart.
  hotReload,

  /// Hot restart forces source reload for the selected Runtime Target isolate.
  hotRestart,
}

/// Normalized result for a runtime hot reload or hot restart request.
///
/// The result keeps the VM Service response available for diagnostics while
/// exposing operation and success fields that belong to Flutter Pilot's client
/// contract.
class PilotRuntimeReloadResult {
  /// Create one normalized VM Service reload result.
  const PilotRuntimeReloadResult({
    required this.operation,
    required this.success,
    required this.response,
  });

  /// Runtime lifecycle operation that produced this result.
  final PilotRuntimeReloadOperation operation;

  /// Whether the VM Service reported a successful reload.
  final bool success;

  /// Decoded VM Service reload response retained for diagnostics.
  final Map<String, Object?> response;
}

/// Failure thrown when a VM Service hot reload or hot restart request fails.
class PilotRuntimeReloadException implements Exception {
  /// Create a runtime reload failure.
  const PilotRuntimeReloadException({
    required this.operation,
    required this.message,
    this.cause,
  });

  /// Runtime lifecycle operation that failed.
  final PilotRuntimeReloadOperation operation;

  /// Human-readable explanation suitable for run reports or calibration logs.
  final String message;

  /// Original VM Service error or response when available.
  final Object? cause;

  @override
  String toString() {
    return 'PilotRuntimeReloadException: $message';
  }
}

/// Logical-pixel rectangle reported for a resolved Finder Match.
class PilotRuntimeBounds {
  /// Create one visible target bounds rectangle.
  const PilotRuntimeBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Decode bounds from a runtime Finder Match.
  factory PilotRuntimeBounds.fromJson(Map<String, Object?> json) {
    return PilotRuntimeBounds(
      left: _readDouble(json, 'left'),
      top: _readDouble(json, 'top'),
      width: _readDouble(json, 'width'),
      height: _readDouble(json, 'height'),
    );
  }

  /// Left edge in global logical pixels.
  final double left;

  /// Top edge in global logical pixels.
  final double top;

  /// Width in logical pixels.
  final double width;

  /// Height in logical pixels.
  final double height;

  /// Encode this rectangle for VM Service transport.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };
  }

  static double _readDouble(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    throw FormatException('Finder Match bounds.$field must be a number.');
  }
}

/// One visible Runtime Target match returned by `pilot_runtime`.
///
/// The `handle` is opaque to Flutter Pilot. Diagnostics describe why the match
/// was selected without exposing Flutter internals as the public contract.
class PilotRuntimeFinderMatch {
  /// Create one decoded runtime Finder Match.
  const PilotRuntimeFinderMatch({
    required this.handle,
    this.text,
    this.semanticType,
    this.key,
    this.matchedWidgetType,
    this.actionWidgetType,
    this.bounds,
  });

  /// Opaque Runtime Handle for the matched target.
  final String handle;

  /// User-visible text evidence when available.
  final String? text;

  /// Semantic Node Type evidence when available.
  final String? semanticType;

  /// `ValueKey<String>` evidence when available.
  final String? key;

  /// Widget runtime type that satisfied the Finder constraints when available.
  final String? matchedWidgetType;

  /// Widget type expected to receive a later action when available.
  final String? actionWidgetType;

  /// Global logical-pixel bounds when available.
  final PilotRuntimeBounds? bounds;

  /// Decode a Finder Match from the app-side runtime extension.
  factory PilotRuntimeFinderMatch.fromJson(Map<String, Object?> json) {
    final Object? handleValue = json['handle'];
    if (handleValue is! String || handleValue.isEmpty) {
      throw const FormatException(
        'Finder Match must include a non-empty opaque handle.',
      );
    }

    final Object? boundsValue = json['bounds'];
    PilotRuntimeBounds? bounds;
    if (boundsValue != null) {
      if (boundsValue is! Map<String, Object?>) {
        throw const FormatException('Finder Match bounds must be an object.');
      }
      bounds = PilotRuntimeBounds.fromJson(boundsValue);
    }

    return PilotRuntimeFinderMatch(
      handle: handleValue,
      text: _readOptionalString(json, 'text'),
      semanticType: _readOptionalString(json, 'semanticType'),
      key: _readOptionalString(json, 'key'),
      matchedWidgetType: _readOptionalString(json, 'matchedWidgetType'),
      actionWidgetType: _readOptionalString(json, 'actionWidgetType'),
      bounds: bounds,
    );
  }

  /// Encode this match for VM Service transport.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'handle': handle,
      if (text != null) 'text': text,
      if (semanticType != null) 'semanticType': semanticType,
      if (key != null) 'key': key,
      if (matchedWidgetType != null) 'matchedWidgetType': matchedWidgetType,
      if (actionWidgetType != null) 'actionWidgetType': actionWidgetType,
      if (bounds != null) 'bounds': bounds!.toJson(),
    };
  }

  static String? _readOptionalString(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Finder Match $field must be a string.');
  }
}

/// Verified runtime session returned after a successful protocol handshake.
///
/// The session records the accepted protocol version and the capabilities
/// reported by the Runtime Target. Flutter Pilot uses it as proof that the
/// target has the required debug hook before executing Scenario Steps.
class PilotRuntimeSession {
  /// Create an initialized session from one accepted handshake response.
  const PilotRuntimeSession({
    required this.protocolVersion,
    required this.capabilities,
  });

  /// Runtime protocol version accepted by this client.
  final int protocolVersion;

  /// Capabilities reported by the Runtime Target during handshake.
  final Set<String> capabilities;
}

/// VM Service client that validates the Flutter Pilot runtime protocol.
///
/// The client owns runtime initialization checks: it calls the app-side
/// handshake extension, accepts protocol version 1, and verifies required
/// capabilities before returning a session.
class PilotRuntimeClient {
  /// Create a client backed by a VM Service extension caller.
  const PilotRuntimeClient(this._vmService);

  final PilotRuntimeVmService _vmService;

  /// Initialize the Runtime Target through the protocol handshake.
  ///
  /// Returns a `PilotRuntimeSession` when the target exposes protocol version 1
  /// and all required capabilities. Throws
  /// `PilotRuntimeInitializationException` for missing hooks, unsupported
  /// protocol versions, missing capabilities, or malformed handshake data.
  Future<PilotRuntimeSession> initialize() async {
    final Map<String, Object?> response = await _callHandshake();
    final PilotRuntimeHandshakeResponse handshake = _parseHandshakeResponse(
      response,
    );

    if (handshake.protocolVersion != PilotRuntimeProtocol.version) {
      throw PilotRuntimeInitializationException(
        failure: PilotRuntimeInitializationFailure.protocolVersionMismatch,
        message:
            'pilot_runtime protocol version '
            '${handshake.protocolVersion} is incompatible with client '
            'version ${PilotRuntimeProtocol.version}.',
      );
    }

    final Set<String> missingCapabilities = PilotRuntimeProtocol
        .requiredCapabilities
        .difference(handshake.capabilities);
    if (missingCapabilities.isNotEmpty) {
      throw PilotRuntimeInitializationException(
        failure: PilotRuntimeInitializationFailure.missingCapability,
        message:
            'pilot_runtime handshake is missing required capabilities: '
            '${missingCapabilities.join(', ')}.',
      );
    }

    return PilotRuntimeSession(
      protocolVersion: handshake.protocolVersion,
      capabilities: handshake.capabilities,
    );
  }

  /// Capture a normalized Widget Tree from Flutter Inspector summary data.
  ///
  /// This method:
  /// 1. configures Flutter Inspector pub root directories from `projectRoot`
  /// 2. requests the root Widget Tree as a summary tree with previews
  /// 3. normalizes Inspector node fields into Flutter Pilot Widget Tree v1 JSON
  ///
  /// Args:
  /// - `projectRoot`: Target App Package root used by Inspector to mark local
  ///   project widgets. It is passed to
  ///   `ext.flutter.inspector.setPubRootDirectories` as `arg0`.
  ///
  /// Returns JSON with `schema`, `source`, and a normalized `root` node. Missing
  /// child lists are returned as empty `children` arrays.
  Future<Map<String, Object?>> captureWidgetTree({
    required String projectRoot,
  }) async {
    try {
      await _vmService.callServiceExtension(
        PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension,
        parameters: <String, Object?>{'arg0': projectRoot},
      );
    } catch (error) {
      throw PilotRuntimeWidgetTreeCaptureException(
        failure:
            PilotRuntimeWidgetTreeCaptureFailure.setPubRootDirectoriesFailed,
        message:
            'Flutter Inspector could not set pub root directories for '
            'Widget Tree capture: $error',
        cause: error,
      );
    }

    final Map<String, Object?> rawResponse;
    try {
      rawResponse = await _vmService.callServiceExtension(
        PilotRuntimeInspectorProtocol.getRootWidgetTreeExtension,
        parameters: PilotRuntimeInspectorProtocol.summaryTreeParameters,
      );
    } catch (error) {
      throw PilotRuntimeWidgetTreeCaptureException(
        failure: PilotRuntimeWidgetTreeCaptureFailure.getRootWidgetTreeFailed,
        message:
            'Flutter Inspector could not return the root summary '
            'Widget Tree: $error',
        cause: error,
      );
    }

    try {
      final Map<String, Object?> rawTree = _unwrapWidgetTreeResponse(
        rawResponse,
      );
      return PilotRuntimeWidgetTreeNormalizer.normalize(rawTree);
    } on FormatException catch (error) {
      throw PilotRuntimeWidgetTreeCaptureException(
        failure: PilotRuntimeWidgetTreeCaptureFailure.invalidResponse,
        message:
            'Flutter Inspector returned an invalid Widget Tree: '
            '${error.message}',
        cause: error,
      );
    }
  }

  /// Extract the Inspector diagnostics node from VM Service response wrappers.
  ///
  /// Some Flutter Inspector service extension calls return the diagnostics tree
  /// directly while others return a `Response` object with a JSON-encoded
  /// payload. Normalize both shapes before Widget Tree validation.
  static Map<String, Object?> _unwrapWidgetTreeResponse(
    Map<String, Object?> response,
  ) {
    final Object? jsonPayload = response['json'];
    if (jsonPayload is String) {
      final Object? decoded = jsonDecode(jsonPayload);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      throw const FormatException(
        'Widget Tree response json must decode to an object.',
      );
    }

    final Object? result = response['result'];
    if (result is Map<String, Object?>) {
      return result;
    }
    if (result is String) {
      final Object? decoded = jsonDecode(result);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      throw const FormatException(
        'Widget Tree response result must decode to an object.',
      );
    }

    return response;
  }

  /// Resolve one Finder through the app-side runtime extension.
  ///
  /// Args:
  /// - `byText`: Exact visible text constraint from a Scenario Finder.
  /// - `byType`: Semantic Node Type constraint from a Scenario Finder. It
  ///   names roles such as `button`, `textField`, `text`, `scrollable`, or
  ///   `header`; it is not a Dart widget runtime type.
  /// - `byKey`: `ValueKey<String>` constraint from a Scenario Finder.
  /// - `byWidget`: exact Dart widget runtime type display name constraint.
  ///
  /// Returns all visible Finder Matches. The Flutter Pilot runner applies the
  /// zero, one, and multiple-match cardinality rules.
  Future<List<PilotRuntimeFinderMatch>> resolveFinder({
    String? byText,
    String? byType,
    String? byKey,
    String? byWidget,
  }) async {
    final Map<String, Object?> parameters = <String, Object?>{};
    if (byText != null) {
      parameters['byText'] = byText;
    }
    if (byType != null) {
      parameters['byType'] = byType;
    }
    if (byKey != null) {
      parameters['byKey'] = byKey;
    }
    if (byWidget != null) {
      parameters['byWidget'] = byWidget;
    }

    final Map<String, Object?> response = await _vmService.callServiceExtension(
      PilotRuntimeProtocol.resolveFinderExtension,
      parameters: parameters,
    );
    final Object? matchesValue = response['matches'];
    if (matchesValue is! List<Object?>) {
      throw const FormatException('resolveFinder must return a matches list.');
    }
    final List<PilotRuntimeFinderMatch> matches = <PilotRuntimeFinderMatch>[];
    for (final Object? matchValue in matchesValue) {
      if (matchValue is! Map<String, Object?>) {
        throw const FormatException('Finder Match entries must be objects.');
      }
      matches.add(PilotRuntimeFinderMatch.fromJson(matchValue));
    }
    return List<PilotRuntimeFinderMatch>.unmodifiable(matches);
  }

  /// Wait for the Runtime Target's current or next Flutter frame to finish.
  ///
  /// `timeout` bounds the app-side wait. A frame timeout is a successful
  /// synchronization attempt so callers can continue with condition polling.
  Future<void> waitForEndOfFrame({required Duration timeout}) async {
    await _vmService.callServiceExtension(
      PilotRuntimeProtocol.endOfFrameExtension,
      parameters: <String, Object?>{
        'timeoutMs': timeout.inMilliseconds.clamp(1, 0x7fffffff),
      },
    );
  }

  /// Tap one Runtime Handle returned by Finder resolution.
  ///
  /// Args:
  /// - `handle`: Opaque Runtime Handle from a `PilotRuntimeFinderMatch`.
  ///   Flutter Pilot passes it back unchanged for the immediately following
  ///   action and does not parse or construct it.
  ///
  /// Returns when the app-side runtime completed the tap. Runtime action
  /// failures are reported by the service extension and surface as VM Service
  /// call failures.
  Future<void> performTap({required String handle}) async {
    final Map<String, Object?> response = await _vmService.callServiceExtension(
      PilotRuntimeProtocol.tapExtension,
      parameters: <String, Object?>{'handle': handle},
    );
    _checkActionResponse(response, actionName: 'tap');
  }

  /// Clear editable text for one Runtime Handle returned by Finder resolution.
  ///
  /// Args:
  /// - `handle`: Opaque Runtime Handle from a `PilotRuntimeFinderMatch`.
  ///
  /// Returns when the app-side runtime directly cleared the editable target.
  /// Non-editable targets throw `PilotRuntimeActionException`.
  Future<void> clearText({required String handle}) async {
    final Map<String, Object?> response = await _vmService.callServiceExtension(
      PilotRuntimeProtocol.clearTextExtension,
      parameters: <String, Object?>{'handle': handle},
    );
    _checkActionResponse(response, actionName: 'clearText');
  }

  /// Enter text for one Runtime Handle returned by Finder resolution.
  ///
  /// Args:
  /// - `handle`: Opaque Runtime Handle from a `PilotRuntimeFinderMatch`.
  /// - `text`: Text fragment to append. Flutter Pilot sends one character at a
  ///   time for Scenario `type` actions.
  Future<void> enterText({required String handle, required String text}) async {
    final Map<String, Object?> response = await _vmService.callServiceExtension(
      PilotRuntimeProtocol.enterTextExtension,
      parameters: <String, Object?>{'handle': handle, 'text': text},
    );
    _checkActionResponse(response, actionName: 'enterText');
  }

  /// Scroll a Runtime Handle or the primary scrollable by drag deltas.
  ///
  /// Args:
  /// - `handle`: Optional opaque Runtime Handle from a Finder Match. When
  ///   omitted, the app-side runtime resolves the primary scrollable.
  /// - `deltaX`: Horizontal drag distance in logical pixels.
  /// - `deltaY`: Vertical drag distance in logical pixels.
  Future<void> performScroll({
    String? handle,
    required double deltaX,
    required double deltaY,
  }) async {
    final Map<String, Object?> parameters = <String, Object?>{
      'deltaX': deltaX,
      'deltaY': deltaY,
    };
    if (handle != null) {
      parameters['handle'] = handle;
    }
    final Map<String, Object?> response = await _vmService.callServiceExtension(
      PilotRuntimeProtocol.scrollExtension,
      parameters: parameters,
    );
    _checkActionResponse(response, actionName: 'scroll');
  }

  /// Collect buffered runtime logs from the app-side runtime hook.
  ///
  /// Returns the structured Logs payload exposed by the Runtime Target. The
  /// payload includes debug print messages and Flutter runtime errors captured
  /// since `PilotRuntimeBinding.ensureInitialized()` was called.
  Future<Map<String, Object?>> collectLogs() async {
    return _vmService.callServiceExtension(
      PilotRuntimeProtocol.collectLogsExtension,
    );
  }

  /// Request a hot reload through VM Service source reload.
  ///
  /// This operation is a client capability, not a Scenario Step action and not
  /// an app-side `ext.flutter_pilot.runtime.*` hook extension.
  Future<PilotRuntimeReloadResult> hotReload() {
    return _reloadSources(
      operation: PilotRuntimeReloadOperation.hotReload,
      force: false,
    );
  }

  /// Request a hot restart through VM Service source reload.
  ///
  /// This operation is a client capability, not a Scenario Step action and not
  /// an app-side `ext.flutter_pilot.runtime.*` hook extension.
  Future<PilotRuntimeReloadResult> hotRestart() {
    return _reloadSources(
      operation: PilotRuntimeReloadOperation.hotRestart,
      force: true,
    );
  }

  void _checkActionResponse(
    Map<String, Object?> response, {
    required String actionName,
  }) {
    final Object? okValue = response['ok'];
    if (okValue == null || okValue == true) {
      return;
    }
    if (okValue != false) {
      throw FormatException('$actionName response ok must be a boolean.');
    }

    final Object? messageValue = response['message'];
    if (messageValue is! String || messageValue.isEmpty) {
      throw FormatException(
        '$actionName failure response must include a non-empty message.',
      );
    }

    final Object? codeValue = response['code'];
    final PilotRuntimeActionFailure failure = switch (codeValue) {
      'notTappable' => PilotRuntimeActionFailure.notTappable,
      'notEditableText' => PilotRuntimeActionFailure.notEditableText,
      'notScrollable' => PilotRuntimeActionFailure.notScrollable,
      'primaryScrollableUnavailable' =>
        PilotRuntimeActionFailure.primaryScrollableUnavailable,
      _ => PilotRuntimeActionFailure.unknown,
    };
    throw PilotRuntimeActionException(
      failure: failure,
      message: messageValue,
      cause: response,
    );
  }

  Future<Map<String, Object?>> _callHandshake() async {
    try {
      return await _vmService.callServiceExtension(
        PilotRuntimeProtocol.handshakeExtension,
      );
    } on PilotRuntimeServiceExtensionMissingException catch (error) {
      throw PilotRuntimeInitializationException(
        failure: PilotRuntimeInitializationFailure.missingHook,
        message:
            'PilotRuntimeBinding.ensureInitialized() is not registered '
            'on the debug Runtime Target.',
        cause: error,
      );
    }
  }

  PilotRuntimeHandshakeResponse _parseHandshakeResponse(
    Map<String, Object?> response,
  ) {
    try {
      return PilotRuntimeHandshakeResponse.fromJson(response);
    } on FormatException catch (error) {
      throw PilotRuntimeInitializationException(
        failure: PilotRuntimeInitializationFailure.invalidHandshake,
        message: error.message,
        cause: error,
      );
    }
  }

  Future<PilotRuntimeReloadResult> _reloadSources({
    required PilotRuntimeReloadOperation operation,
    required bool force,
  }) async {
    final Map<String, Object?> response;
    try {
      response = await _vmService.reloadSources(force: force);
    } catch (error) {
      throw PilotRuntimeReloadException(
        operation: operation,
        message: '${_reloadOperationLabel(operation)} failed: $error',
        cause: error,
      );
    }

    final Object? successValue = response['success'];
    if (successValue is! bool) {
      throw PilotRuntimeReloadException(
        operation: operation,
        message:
            '${_reloadOperationLabel(operation)} returned an invalid VM '
            'Service reload report.',
        cause: response,
      );
    }

    if (!successValue) {
      throw PilotRuntimeReloadException(
        operation: operation,
        message: '${_reloadOperationLabel(operation)} failed.',
        cause: response,
      );
    }

    return PilotRuntimeReloadResult(
      operation: operation,
      success: successValue,
      response: response,
    );
  }

  String _reloadOperationLabel(PilotRuntimeReloadOperation operation) {
    return switch (operation) {
      PilotRuntimeReloadOperation.hotReload => 'Hot reload',
      PilotRuntimeReloadOperation.hotRestart => 'Hot restart',
    };
  }
}
