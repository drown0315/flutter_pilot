import 'recording_device.dart';

/// Recording Session model.

class RecordingSession {
  /// Creates a public handle for an active Recording Session.
  const RecordingSession({
    required this.id,
    required this.device,
    required this.startTime,
    required this.expectedOutputPath,
  });

  /// Unique session identity within one recorder instance.
  final String id;

  /// Recording Device whose screen is being recorded.
  final RecordingDevice device;

  /// Time when recording started.
  final DateTime startTime;

  /// Final local output path expected when the session is stopped and saved.
  final String expectedOutputPath;
}

/// Result returned after a Recording Session is stopped and saved.
///
/// The result confirms the final file path and carries basic metadata that
/// downstream tools can display or attach to reports.
