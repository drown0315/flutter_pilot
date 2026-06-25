/// Stable screen recorder exception and error code contract.
///
/// Callers should branch on `ScreenRecorderErrorCode` instead of parsing
/// messages because backend output can vary across host tools and platforms.
library;

/// Stable failure categories exposed by `ScreenRecorderException`.
enum ScreenRecorderErrorCode {
  /// No Recording Device matched the caller's selector.
  deviceNotFound,

  /// More than one Recording Device matched where one was required.
  ambiguousDevice,

  /// The selected backend family is not supported on the current host.
  unsupportedPlatform,

  /// The requested output name contains a path segment or file extension.
  invalidOutputName,

  /// The final output file already exists and overwrite was not enabled.
  outputAlreadyExists,

  /// The selected Recording Device already has an active session.
  alreadyRecording,

  /// A backend failed while starting a recording.
  startFailed,

  /// A backend failed while stopping a recording.
  stopFailed,

  /// A backend failed while discarding a recording.
  discardFailed,

  /// The supplied Recording Session is not active in this recorder instance.
  sessionNotFound,

  /// A required host tool or helper is missing.
  missingDependency,

  /// The host denied permission required for screen capture.
  permissionDenied,
}

/// Exception type thrown by the screen recorder public API.
///
/// `code` is the stable machine-readable failure category. `message` is for
/// display and logs. Backend-specific diagnostics may be carried in
/// `backendKind`, `deviceSelector`, `rawOutput`, or `cause`.
class ScreenRecorderException implements Exception {
  /// Creates a screen recorder failure with stable code and optional context.
  const ScreenRecorderException({
    required this.code,
    required this.message,
    this.backendKind,
    this.deviceSelector,
    this.rawOutput,
    this.cause,
  });

  /// Stable failure category for programmatic handling.
  final ScreenRecorderErrorCode code;

  /// Human-readable explanation of the failure.
  final String message;

  /// Backend family that reported the failure, when known.
  final String? backendKind;

  /// Caller-provided device selector related to the failure, when any.
  final String? deviceSelector;

  /// Raw backend output useful for diagnosing host tool failures.
  final String? rawOutput;

  /// Original lower-level error, when the recorder is wrapping one.
  final Object? cause;

  @override
  String toString() => 'ScreenRecorderException($code): $message';
}
