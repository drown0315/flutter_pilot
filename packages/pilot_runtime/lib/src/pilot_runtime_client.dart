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

    final Map<String, Object?> rawTree;
    try {
      rawTree = await _vmService.callServiceExtension(
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
    await _vmService.callServiceExtension(
      PilotRuntimeProtocol.tapExtension,
      parameters: <String, Object?>{'handle': handle},
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
}
