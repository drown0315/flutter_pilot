# pilot_runtime Grill Notes

Date: 2026-07-06

These notes preserve the current shared understanding from the `grill-with-docs`
session about introducing `pilot_runtime`. They are working design memory, not a
final PRD or ADR.

## Accepted Terms

- `pilot_runtime`: an independent Dart package that provides low-level
  capabilities against a Flutter Runtime Target.
- `PilotRuntimeAdapter`: Flutter Pilot's Runtime Adapter implementation backed
  by `pilot_runtime`.
- `Debug Runtime Target`: a Flutter debug app with a reachable VM Service URI
  and the Flutter runtime extensions needed by Flutter Pilot.
- `Non-invasive Runtime Access`: runtime access that does not require the
  Target App Package to add Flutter Pilot code, plugins, hooks, or SDK
  initialization.
- `Inspector Summary Widget Tree`: a Flutter Inspector-provided summary widget
  hierarchy used as Flutter Pilot's Widget Tree source when available.

These terms were also added to `CONTEXT.md` during the session.

## Agreed Direction

- Keep `mcp_flutter` in place while `pilot_runtime` is built and calibrated.
- Build `pilot_runtime` as an independent package under
  `packages/pilot_runtime/`.
- Flutter Pilot should consume `pilot_runtime` through a `PilotRuntimeAdapter`,
  not by depending on VM Service or Flutter Inspector details directly.
- `pilot_runtime` should target Flutter Pilot's `RuntimeAdapter` contract rather
  than cloning `mcp_flutter` command names or response shapes.
- `pilot_runtime` v0 targets Debug Runtime Targets only.
- `pilot_runtime` v0 should use Non-invasive Runtime Access. Target App Package
  code changes, hooks, or SDK initialization are not part of the v0 default.
- `pilot_runtime` should directly depend on `package:vm_service`, but keep VM
  Service types and Flutter extension names behind its own public API.
- `pilot_runtime` should expose one entry-point client while organizing
  behavior by capability internally and in the API.
- Flutter Pilot should keep `mcp_flutter` as the default bridge first.
- `pilot_runtime` should be selected initially through an experimental
  environment switch rather than a public CLI flag.
- After click injection calibration, the next `pilot_runtime` direction is to
  pursue an app-side hook path for stable interaction replay rather than trying
  to make Non-invasive Runtime Access provide `byKey`, Dart widget type, or
  coordinate-based clicks.
- Non-invasive Runtime Access remains useful for Inspector and Widget Tree
  diagnostics, but it should not be treated as the path for stable Flutter-level
  tap execution unless new Flutter SDK evidence proves otherwise.

## Capability Goal

The long-term goal is for `pilot_runtime` to support all capabilities Flutter
Pilot currently gets through `mcp_flutter`:

- initialize a Runtime Target connection
- resolve Finders
- tap
- replace text
- scroll
- capture Screenshot
- capture Snapshot
- capture Widget Tree
- collect Logs and runtime errors
- dispose runtime resources

Hot reload and hot restart are desired `pilot_runtime` capabilities, but they
are not part of Flutter Pilot's current Scenario execution contract.

Each capability should enter the usable Flutter Pilot contract only after
technical calibration against a real Flutter debug app.

## Widget Tree Direction

The Widget Tree direction should reference the approach in:

```text
/Users/drown/ai_project/ask_ui/apps/bridge
```

The relevant approach there is:

- connect through VM Service
- find the main isolate
- call `ext.flutter.inspector.setPubRootDirectories`
- call `ext.flutter.inspector.getRootWidgetTree`
- request a summary tree with previews and without full details
- normalize Flutter diagnostics output before returning it to callers

The exact `pilot_runtime` Widget Tree model is not finalized. The discussion
paused before deciding the field set, missing-field behavior, and whether the
Inspector summary tree is stable enough for the first package contract.

## Deferred For Technical Research

Do not lock these decisions before calibration:

- exact Inspector Summary Widget Tree request parameters
- exact normalized Widget Tree node model
- whether Widget Tree node ids use Flutter Inspector `valueId` directly
- tap implementation
- text input implementation
- scroll implementation
- screenshot implementation
- Snapshot implementation
- Logs and runtime error collection
- hot reload implementation
- hot restart implementation
- whether action execution can use Inspector ids directly or needs another
  runtime handle

## Recommended Next Questions

Continue the grill from the first unresolved branch:

1. Which real app should be used for the first `pilot_runtime` calibration:
   Flutter Pilot's existing `examples/smoke_app`, or a dedicated
   `pilot_runtime` fixture app?
2. What is the minimal `pilot_runtime` package skeleton and public API shape?
3. Which capability should be calibrated first after package creation?
4. What environment variable should select `PilotRuntimeAdapter` during
   experimental Flutter Pilot runs?
5. Which decisions are hard enough to justify an ADR after calibration?
