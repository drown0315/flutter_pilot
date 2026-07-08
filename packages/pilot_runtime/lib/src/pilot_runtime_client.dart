import 'pilot_runtime_protocol.dart';

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
  ///
  /// Returns the decoded JSON object returned by the extension. Implementations
  /// throw `PilotRuntimeServiceExtensionMissingException` when the extension is
  /// not registered on the Runtime Target.
  Future<Map<String, Object?>> callServiceExtension(String extensionName);
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
