/// Public API for app-side Flutter Pilot runtime access and client handshakes.
///
/// Target App Packages call `PilotRuntimeBinding.ensureInitialized()` in debug
/// mode. Flutter Pilot tools use `PilotRuntimeClient` to verify that the debug
/// Runtime Target exposes the expected runtime protocol before running
/// Scenarios.
library;

export 'src/pilot_runtime_binding.dart';
export 'src/pilot_runtime_client.dart';
export 'src/pilot_runtime_protocol.dart';
