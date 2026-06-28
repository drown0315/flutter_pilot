library;

import 'recording_session.dart';

/// Saved recording result model.
///
/// A Recording Result is returned only after a Recording Session is stopped and
/// the backend has produced a local video artifact.

/// Result returned after a Recording Session is stopped and saved.
///
/// The result confirms the final file path and carries basic metadata that
/// downstream tools can display or attach to reports.
class RecordingResult {
  /// Creates metadata for a saved Device Video Recording.
  const RecordingResult({
    required this.session,
    required this.outputPath,
    required this.startTime,
    required this.stopTime,
    required this.duration,
    required this.fileSizeBytes,
    required this.mimeType,
  });

  /// Session that produced this saved recording.
  final RecordingSession session;

  /// Local video file path created by stopping the session.
  final String outputPath;

  /// Time when recording started.
  final DateTime startTime;

  /// Time when recording stopped and the file was finalized.
  final DateTime stopTime;

  /// Elapsed time between session start and stop.
  final Duration duration;

  /// Size of the saved video file in bytes.
  final int fileSizeBytes;

  /// MIME type for the backend-native video format.
  final String mimeType;
}
