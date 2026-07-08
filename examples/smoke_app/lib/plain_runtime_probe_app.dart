import 'package:flutter/material.dart';

import 'pilot_runtime_probe_app.dart' as probe;

/// Starts the calibration UI without registering Flutter Pilot service hooks.
///
/// This target is used to verify Non-invasive Runtime Access through ordinary
/// Flutter debug service extensions such as Flutter Inspector. The app still
/// contains the same widgets and keys as the hook probe target, but it does not
/// call `PilotRuntimeProbeHook.register()`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const probe.PilotRuntimeProbeApp());
}
