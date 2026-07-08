# Build pilot_runtime with Invasive Runtime Access

Flutter Pilot will build `pilot_runtime` as a Flutter Pilot-owned runtime
package with an app-side `PilotRuntimeBinding`, a VM Service client, and a
`PilotRuntimeAdapter`, rather than relying on `mcp_toolkit` as the long-term
runtime bridge. The replacement path uses Invasive Runtime Access because local
calibration showed that plain VM Service and Flutter Inspector access can
provide useful Widget Tree diagnostics, but does not provide a stable action
boundary for `byKey`, `byWidget`, text entry, tap, or scroll replay.

`mcp_toolkit` remains the default while `pilot_runtime` is implemented and
calibrated. The new adapter will first be selected through a hidden environment
switch, and setup migration for `init`, `doctor`, and Target App Package
initialization will wait until `pilot_runtime` reaches parity for Scenario
execution and required runtime capabilities.

Consequences: Target App Packages must initialize `PilotRuntimeBinding` in
debug mode before they can be driven by `PilotRuntimeAdapter`; missing
initialization is a run-level failure before any Scenario Step executes. The
Scenario DSL will add `byKey` for `ValueKey<String>` and `byWidget` for exact
Dart widget runtime type matching, while preserving semantic `byType`. Snapshot
artifacts are removed in favor of normalized Inspector Summary Widget Tree
artifacts.
