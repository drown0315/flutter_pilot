import 'target_app_launch_progress_renderer.dart';

/// Return the user-facing reason for the selected Target Device.
TargetDeviceSelectionReason? targetDeviceSelectionReason({
  required String? deviceSelector,
  required bool recordingRequired,
}) {
  if (deviceSelector != null) {
    return TargetDeviceSelectionReason.explicit(selector: deviceSelector);
  }
  if (recordingRequired) {
    return const TargetDeviceSelectionReason.autoSelectedForRecording();
  }
  return null;
}
