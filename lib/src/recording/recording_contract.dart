import '../scenario/scenario.dart';

/// Boundary used by the runner to control full-run Scenario Recording.
///
/// Recording is separate from the Runtime Adapter because it captures the
/// device display rather than Flutter UI semantics. Implementations should
/// normalize platform recording startup and shutdown into this small contract.
abstract interface class RecordingController {
  /// Start a Recording Session for a Scenario Run.
  ///
  /// Args:
  /// `scenario` is the parsed Scenario whose metadata requested recording.
  ///
  /// Throws:
  /// `RecordingException` when the Recording Session cannot be started.
  Future<void> start(Scenario scenario);

  /// Stop the active Recording Session and return the saved video metadata.
  ///
  /// Returns:
  /// A `RecordingResult` containing the final video path. The path belongs to
  /// stop-time output because recording backends generally do not know the
  /// final saved file until the session is finalized.
  ///
  /// Throws:
  /// `RecordingException` when the active session cannot be stopped.
  Future<RecordingResult> stop();
}

/// Recording operation names used for normalized run-level failures.
enum RecordingOperation { start, stop }

/// Final Device Video Recording produced by a Recording Session.
///
/// `path` is the video file path recorded in run-level artifact metadata.
/// `mimeType` describes the encoded video format when the backend knows it.
class RecordingResult {
  const RecordingResult({required this.path, this.mimeType});

  final String path;
  final String? mimeType;
}

/// Failure raised when Scenario Recording cannot complete an operation.
///
/// `message` is the run-level failure reason shown by Flutter Pilot. `cause`
/// preserves the backend-specific error for debugging without making it part
/// of the stable report contract.
class RecordingException implements Exception {
  const RecordingException({
    required this.operation,
    required this.message,
    this.cause,
  });

  final RecordingOperation operation;
  final String message;
  final Object? cause;

  @override
  String toString() {
    return 'RecordingException(${operation.name}): $message';
  }
}
