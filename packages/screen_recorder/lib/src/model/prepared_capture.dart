import 'recording_device.dart';

/// Prepared device capture handle used to start one or more Recording Sessions.
///
/// A prepared capture reserves backend state for a Recording Device before a
/// specific output file is selected. Backends that support preparation can keep
/// device capture warm and create a video segment only when
/// `startRecord` is called with this capture.
class PreparedCapture {
  /// Creates a handle owned by one `ScreenRecorder` instance.
  const PreparedCapture({
    required this.id,
    required this.device,
  });

  /// Unique capture identity within one recorder instance.
  final String id;

  /// Recording Device whose screen is prepared for segment recording.
  final RecordingDevice device;
}
