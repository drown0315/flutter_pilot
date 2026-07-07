# mcp_toolkit Replacement Runtime Research

Date: 2026-07-07

This report designs a Flutter Pilot-owned runtime package, tentatively
`pilot_runtime`, that can gradually replace the current
`mcp_toolkit` / `flutter-mcp-toolkit` dependency. It is based on local Flutter
SDK source, current `mcp_toolkit` source, and live probes against real Flutter
debug Runtime Targets.

The conclusion is intentionally split:

- App-side hook access is the replacement path for interaction replay.
- Non-invasive Runtime Access is valuable for diagnostics, especially Inspector
  Widget Tree data, but the verified Flutter debug surfaces do not provide a
  stable tap or coordinate action boundary.

No current Scenario DSL change is recommended in this research slice.

## Environment And Evidence

Verified local SDK:

```text
Flutter 3.44.0 stable
Dart 3.12.0
DevTools 2.57.0
```

Live verification targets:

```text
macOS debug app: examples/smoke_app/lib/pilot_runtime_probe_app.dart
Android debug app: examples/smoke_app/lib/pilot_runtime_probe_app.dart
Plain macOS debug app: examples/smoke_app/lib/plain_runtime_probe_app.dart
```

Calibration artifacts added or updated:

```text
examples/smoke_app/lib/pilot_runtime_probe_app.dart
examples/smoke_app/lib/plain_runtime_probe_app.dart
calibrate/pilot_runtime_hook_probe/bin/pilot_runtime_hook_probe.dart
calibrate/pilot_runtime_hook_probe/out/hook-probe-macos.txt
calibrate/pilot_runtime_hook_probe/out/hook-probe-android.txt
calibrate/summary_tree_probe/bin/service_extension_inventory.dart
calibrate/summary_tree_probe/out/plain-runtime-service-extensions-macos.txt
calibrate/summary_tree_probe/out/plain-runtime-full-details-macos.txt
```

Existing supporting evidence:

```text
docs-internal/calibration/flutter-click-injection-2026-07-07.md
docs-internal/calibration/inspector-summary-tree-2026-07-06.md
docs-internal/calibration/inspector-widget-location-2026-07-06.md
docs-internal/calibration/mcp_flutter-2026-06-09.md
docs-internal/pilot-runtime-grill-notes.md
```

Local source references:

- Dart `developer.registerExtension` requires `ext.` names and string
  parameters:
  `/Users/drown/development/flutter/bin/cache/dart-sdk/lib/developer/extension.dart`
- Flutter service extensions wrap `developer.registerExtension`:
  `/Users/drown/development/flutter/packages/flutter/lib/src/foundation/binding.dart`
- Flutter Inspector registers `ext.flutter.inspector.getRootWidgetTree` and
  emits `valueId`, `creationLocation`, and `createdByLocalProject`:
  `/Users/drown/development/flutter/packages/flutter/lib/src/widgets/widget_inspector.dart`
- `WidgetController.tap` delegates to `tapAt`, and `tapAt` dispatches a
  pointer down/up sequence:
  `/Users/drown/development/flutter/packages/flutter_test/lib/src/controller.dart`
- `flutter_driver` supports `find.byValueKey`, `find.byType`, and
  `driver.tap`, but only through an app-side driver extension:
  `/Users/drown/development/flutter/packages/flutter_driver/lib/src/driver/driver.dart`
  and
  `/Users/drown/development/flutter/packages/flutter_driver/lib/src/common/handler_factory.dart`
- `mcp_toolkit` uses a semantic Snapshot ref followed by `tap_widget(ref)`;
  it prefers `SemanticsOwner.performAction(..., SemanticsAction.tap)` and falls
  back to `GestureBinding.instance.handlePointerEvent` on non-web platforms:
  `/Users/drown/.pub-cache/hosted/pub.dev/mcp_toolkit-3.0.0/lib/src/services/semantic_snapshot_service.dart`
  and
  `/Users/drown/.pub-cache/hosted/pub.dev/mcp_toolkit-3.0.0/lib/src/services/gesture_interaction_service.dart`

## Product Expectations

- Find and tap widgets by Flutter `ValueKey`.
- Find and tap widgets by Dart widget runtime type or app-authored widget
  class.
- Preserve existing semantic `byType`, where `button`, `textField`, `text`,
  `scrollable`, and `header` are Semantic Node Types, not Dart widget classes.
- Tap an explicit coordinate when no stable Finder is available.
- Avoid exposing Scenario DSL capabilities until a real runtime boundary proves
  the matching and action behavior.

## Current Baseline

Flutter Pilot currently resolves Scenario Finders through
`McpFlutterRuntimeAdapter`:

```text
Scenario Finder -> semantic_snapshot -> FinderMatch(ref) -> tap_widget(ref)
```

Current public Finder behavior remains:

- `byText`: exact visible text from the semantic Snapshot path
- `byType`: Semantic Node Type from `mcp_flutter`, not Dart widget class name
- combined Finder fields use AND semantics
- Finder Match cardinality is strict: zero fails, one executes, many fail
- Finder Match refs are opaque and valid only for the immediate action

This research keeps that contract intact.

## Candidate Architecture

`pilot_runtime` should be an independent package with two cooperating sides:

```text
Target App Package
  -> depends on pilot_runtime
  -> initializes PilotRuntimeBinding in debug-capable builds
  -> registers ext.flutter_pilot.* service extensions

Flutter Pilot CLI
  -> PilotRuntimeAdapter
    -> pilot_runtime client
      -> VM Service
        -> ext.flutter_pilot.* app hook
```

Recommended package shape:

```text
packages/pilot_runtime/
  lib/pilot_runtime.dart
  lib/src/client/pilot_runtime_client.dart
  lib/src/client/runtime_target.dart
  lib/src/client/runtime_responses.dart
  lib/src/hook/pilot_runtime_binding.dart
  lib/src/hook/snapshot_service.dart
  lib/src/hook/gesture_service.dart
  lib/src/hook/service_extension_protocol.dart
```

The public package API should keep VM Service and Flutter extension details
behind Flutter Pilot-owned types:

```dart
final PilotRuntimeClient client = await PilotRuntimeClient.connect(
  RuntimeTarget(vmServiceUri: uri),
);

final PilotSnapshot snapshot = await client.captureSnapshot();
final List<PilotFinderMatch> matches = await client.resolveFinder(finder);
await client.tap(matches.single.ref);
await client.tapAt(const PilotOffset.logicalGlobal(x: 222, y: 196));
```

The app-side setup should be explicit and debug-safe:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  runApp(const MyApp());
}
```

Production requirements for that hook:

- Register extensions only in debug/profile-capable builds, with clear release
  guardrails.
- Keep response shapes owned by `pilot_runtime`; do not clone
  `mcp_toolkit` command names as Flutter Pilot's public contract.
- Preserve the current "fresh snapshot -> opaque ref -> immediate action"
  pattern.
- Treat refs as snapshot/session scoped, not stable widget identities.

## Invasive Runtime Access

Invasive Runtime Access means the Target App Package depends on and initializes
`pilot_runtime`. The runtime code executes inside the app isolate and registers
VM service extensions such as:

```text
ext.flutter_pilot.snapshot
ext.flutter_pilot.resolve
ext.flutter_pilot.tap
ext.flutter_pilot.tapAt
ext.flutter_pilot.state
```

The calibration hook used this mechanism directly through
`dart:developer.registerExtension`. It traversed Elements, read widget keys and
runtime types, calculated global logical bounds from `RenderBox.localToGlobal`,
and dispatched taps with `GestureBinding.instance.handlePointerEvent`.

The production hook should improve the prototype by using the Flutter semantics
tree for semantic Snapshot roles. The prototype still proves the key boundary:
app-side code can emit a semantic role distinct from Dart `widgetType` and can
execute the resulting action by ref or coordinate.

### Invasive Verification Commands

macOS:

```bash
cd examples/smoke_app
flutter run -d macos --debug -t lib/pilot_runtime_probe_app.dart --machine

cd calibrate/pilot_runtime_hook_probe
dart run bin/pilot_runtime_hook_probe.dart \
  --vm-service-uri ws://127.0.0.1:63175/sOQgyJypC68=/ws \
  --output out/hook-probe-macos.txt
```

Android:

```bash
cd examples/smoke_app
flutter run -d 19271FDF6007TY --debug \
  -t lib/pilot_runtime_probe_app.dart --machine

cd calibrate/pilot_runtime_hook_probe
dart run bin/pilot_runtime_hook_probe.dart \
  --vm-service-uri ws://127.0.0.1:65052/_K67zUN0SoE=/ws \
  --output out/hook-probe-android.txt
```

Available hook extensions:

```text
- ext.flutter_pilot.resolve
- ext.flutter_pilot.snapshot
- ext.flutter_pilot.state
- ext.flutter_pilot.tap
- ext.flutter_pilot.tapAt
```

### Invasive Verification Results

#### byKey

Mechanism:

- app-side Element traversal
- `widget.key is ValueKey`
- match by `ValueKey.value.toString()`
- action by cached ref center in Flutter logical global coordinates

Input:

```json
{"byKey":"submit-smoke"}
```

macOS output excerpt:

```json
{
  "matchCount": 1,
  "matches": [{
    "ref": "p_2_284",
    "widgetType": "ProbeSubmitButton",
    "key": {"kind": "ValueKey", "value": "submit-smoke", "valueType": "String"},
    "bounds": {"left": 24.0, "top": 180.0, "width": 396.0, "height": 32.0},
    "center": {"x": 222.0, "y": 196.0}
  }]
}
```

Tap output:

```json
{
  "tappedRef": "p_2_284",
  "coordinateSpace": "flutterLogicalGlobal",
  "tapPosition": {"x": 222.0, "y": 196.0},
  "state": {"submitTapCount": 1}
}
```

Android output used the same shape and ended with
`"state": {"submitTapCount": 1}` after the byKey tap.

Feasibility:

- Supported with app-side hook code.

Limitations and risks:

- Contract must define key types. Flutter Driver only supports `String` and
  `int` values for `byValueKey`; the probe only validated `ValueKey<String>`.
- Private or object-valued keys should not enter the public DSL until
  separately calibrated.
- Inspector `description` strings also show key-like suffixes, but those are
  display text and should not be treated as the stable key source.

Impact:

- Add a future `Finder.byKey` field to `pilot_runtime` and, later, Scenario
  YAML.
- Keep current Scenario DSL unchanged until the production hook supports
  strict cardinality, typed key values, and clear failure messages.

#### byWidget / byWidgetType

Mechanism:

- app-side Element traversal
- compare `element.widget.runtimeType.toString()`
- use a distinct Finder name so current semantic `byType` is not overloaded

Input:

```json
{"byWidgetType":"ProbeSubmitButton"}
```

macOS output excerpt:

```json
{
  "matchCount": 1,
  "matches": [{
    "ref": "p_3_284",
    "widgetType": "ProbeSubmitButton",
    "key": {"kind": "ValueKey", "value": "submit-smoke", "valueType": "String"},
    "center": {"x": 222.0, "y": 196.0}
  }],
  "state": {"submitTapCount": 1}
}
```

Tap output:

```json
{
  "tappedRef": "p_3_284",
  "coordinateSpace": "flutterLogicalGlobal",
  "tapPosition": {"x": 222.0, "y": 196.0},
  "state": {"submitTapCount": 2}
}
```

Android output used the same shape and ended with
`"state": {"submitTapCount": 2}` after the byWidgetType tap.

Feasibility:

- Supported with app-side hook code.

Limitations and risks:

- `runtimeType.toString()` can include private class names and generic type
  strings such as `ValueListenableBuilder<int>`.
- Minification and release builds are not supported for this v0 contract.
- Multiple instances of the same widget type are common, so strict cardinality
  errors will be frequent unless combined Finders are supported.

Impact:

- Use `byWidgetType`, not `byType`, for Dart widget runtime type matching.
- Flutter Pilot's current `Finder` model can grow this field later without
  changing the current `byType` meaning.

#### Semantic byType

Mechanism:

- app-side Snapshot emits a `semanticType` field distinct from `widgetType`
- production should classify from Flutter `SemanticsData` flags/actions
- current `mcp_toolkit` source classifies `isTextField`, `isButton`,
  `isHeader`, scroll actions, and labels into strings such as `textField`,
  `button`, `header`, `scrollable`, and `text`

Input:

```json
{"byType":"button"}
```

macOS output excerpt:

```json
{
  "matchCount": 1,
  "matches": [{
    "ref": "p_4_285",
    "widgetType": "FilledButton",
    "semanticType": "button",
    "bounds": {"left": 24.0, "top": 180.0, "width": 396.0, "height": 32.0},
    "center": {"x": 222.0, "y": 196.0}
  }],
  "state": {"submitTapCount": 2}
}
```

Tap output:

```json
{
  "tappedRef": "p_4_285",
  "coordinateSpace": "flutterLogicalGlobal",
  "tapPosition": {"x": 222.0, "y": 196.0},
  "state": {"submitTapCount": 3}
}
```

Android output used the same `widgetType: FilledButton` plus
`semanticType: button` distinction and ended with
`"state": {"submitTapCount": 3}` after the semantic byType tap.

Feasibility:

- Supported with app-side hook code.
- The verified output preserves the required semantic distinction:
  `byType: button` does not mean Dart class `FilledButton`.

Limitations and risks:

- The calibration hook used a minimal semantic-role mapping. Production should
  port the semantics-tree classification pattern, not rely only on widget
  classes.
- Accessibility semantics can be absent, merged, excluded, or changed by app
  code.
- Flutter Web needs special handling: the current `mcp_toolkit` source returns
  a structured failure when a semantic tap action is absent because pointer
  fallback does not drive the browser gesture pipeline.

Impact:

- Preserve existing Scenario `byType` exactly as Semantic Node Type.
- `pilot_runtime` Snapshot nodes should expose `semanticType`, not
  `widgetType`, for this Finder.

#### Coordinate Tap

Mechanism:

- app-side action `tapAt(x, y)`
- coordinate space is Flutter logical global coordinates for the current view
- prototype dispatches `PointerDownEvent` / `PointerUpEvent` through
  `GestureBinding.instance.handlePointerEvent`

Input from macOS:

```json
{"x":222.0,"y":196.0}
```

macOS output:

```json
{
  "coordinateSpace": "flutterLogicalGlobal",
  "tapPosition": {"x": 222.0, "y": 196.0},
  "state": {"submitTapCount": 4}
}
```

Android input and output:

```json
{
  "input": {"x": "205.71428571428572", "y": "260.76190476190476"},
  "coordinateSpace": "flutterLogicalGlobal",
  "tapPosition": {"x": 205.71428571428572, "y": 260.76190476190476},
  "state": {"submitTapCount": 4}
}
```

Feasibility:

- Supported with app-side hook code on macOS and Android in this calibration.

Limitations and risks:

- Coordinates are logical Flutter view coordinates, not physical screen pixels.
  The same button center differed across macOS and Android.
- Hard-coded coordinates are not portable across device sizes, text scaling,
  orientation, platform chrome, overlays, or multiple views.
- The current prototype uses one global view coordinate space. Production must
  decide how to include `viewId` or reject multi-view ambiguity.
- Web remains a separate risk because pointer events injected inside Flutter may
  not enter the browser gesture pipeline for every target.

Impact:

- `pilot_runtime` should expose `tapAt` as a low-level runtime operation first.
- Scenario YAML should not expose `tapAt` until the coordinate contract, view
  behavior, and portability warnings are documented.

## Non-invasive Runtime Access

Non-invasive Runtime Access means Flutter Pilot connects to an ordinary Flutter
debug Runtime Target through VM Service and Flutter's built-in service
extensions. The Target App Package does not add Flutter Pilot code, hooks,
plugins, or SDK initialization.

### Non-invasive Verification Commands

Hook-free target:

```bash
cd examples/smoke_app
flutter run -d macos --debug -t lib/plain_runtime_probe_app.dart --machine
```

Service extension inventory:

```bash
cd calibrate/summary_tree_probe
dart run bin/service_extension_inventory.dart \
  --vm-service-uri ws://127.0.0.1:64284/m31C4HbG-Oc=/ws \
  --output out/plain-runtime-service-extensions-macos.txt
```

Inspector summary tree:

```bash
dart run bin/summary_tree_probe.dart \
  --vm-service-uri ws://127.0.0.1:64284/m31C4HbG-Oc=/ws \
  --project-root /Users/drown/.treehouse/flutter_pilot-b6aa0b/1/flutter_pilot/examples/smoke_app \
  --full-details \
  --output out/plain-runtime-full-details-macos.txt
```

### Non-invasive Output Shape

The plain target exposed 74 ordinary Dart/Flutter service extensions. Useful
read-only or diagnostics extensions included:

```text
- ext.flutter.debugDumpApp
- ext.flutter.debugDumpRenderTree
- ext.flutter.debugDumpSemanticsTreeInTraversalOrder
- ext.flutter.inspector.getRootWidgetTree
- ext.flutter.inspector.getRootWidgetSummaryTree
- ext.flutter.inspector.getRootWidgetSummaryTreeWithPreviews
- ext.flutter.inspector.screenshot
```

No `ext.flutter_pilot.*`, `tapByKey`, `tapByType`, `tapByWidgetType`, or
`tapAt` extension was present in the hook-free target.

The Inspector summary tree returned:

```text
nodes: 34
- description: 34 node(s); String=34
- valueId: 34 node(s); String=34
- widgetRuntimeType: 34 node(s); String=34
- creationLocation: 34 node(s); Map=34
- textPreview: 13 node(s); String=13
```

Observed tree excerpt:

```text
TextField-[<'probe-email-field'>] id=inspector-8
ProbeSubmitButton-[<'submit-smoke'>] id=inspector-10
  FilledButton id=inspector-11
    Text id=inspector-12
```

Full JSON excerpt:

```json
{
  "description": "ProbeSubmitButton-[<'submit-smoke'>]",
  "valueId": "inspector-10",
  "creationLocation": {
    "file": "file:///.../examples/smoke_app/lib/pilot_runtime_probe_app.dart",
    "line": 54,
    "column": 17,
    "name": "ProbeSubmitButton"
  },
  "widgetRuntimeType": "ProbeSubmitButton"
}
```

Fields not observed as first-class action data:

```text
key
bounds
center
semanticType
actions
tap command
tapAt command
```

### Non-invasive Capability Findings

#### byKey

Mechanism used:

- Flutter Inspector `getRootWidgetTree`
- `description` display string contained key-like suffixes

Input:

```text
ValueKey<String>('submit-smoke')
```

Output:

```text
ProbeSubmitButton-[<'submit-smoke'>]
```

Feasibility:

- Unsupported as a stable action Finder.

Limitations and risks:

- The key is not a first-class `key` field in the observed Inspector JSON.
- Parsing `description` would couple Flutter Pilot to display formatting.
- No matching tap command or bounds were available from the verified plain
  Runtime Target.

Impact:

- Do not add non-invasive `byKey` to the Scenario DSL.
- Non-invasive diagnostics may display key-like descriptions as Inspector
  details, clearly marked as non-contractual.

#### byWidget / byWidgetType

Mechanism used:

- Flutter Inspector `widgetRuntimeType`

Input:

```text
ProbeSubmitButton
```

Output:

```json
{
  "description": "ProbeSubmitButton-[<'submit-smoke'>]",
  "widgetRuntimeType": "ProbeSubmitButton",
  "valueId": "inspector-10"
}
```

Feasibility:

- Partial for diagnostics.
- Unsupported for action replay without an app-side hook.

Limitations and risks:

- Inspector exposes widget runtime type and `valueId`, but this is not a tap
  API.
- The observed shape did not include logical bounds or a center point.
- `valueId` is an Inspector object id, not a stable Flutter Pilot action ref.

Impact:

- Non-invasive `pilot_runtime` can expose `widgetRuntimeType` in Widget Tree
  diagnostics.
- Scenario `byWidgetType` should be hook-backed only until action execution is
  separately proven.

#### Semantic byType

Mechanism used:

- Flutter Inspector summary Widget Tree
- Flutter debug dump service extension inventory

Input:

```text
Semantic Node Type: button
```

Output:

```json
{
  "description": "FilledButton",
  "widgetRuntimeType": "FilledButton"
}
```

Feasibility:

- Unsupported as a replacement for current semantic `byType` action replay.

Limitations and risks:

- `widgetRuntimeType: FilledButton` is a Dart widget class, not semantic
  `button`.
- Plain Inspector summary output did not include a `semanticType` field.
- Debug semantics dumps may be useful diagnostics, but they are not a stable
  `resolve semantic node -> ref -> tap` protocol by themselves.

Impact:

- Keep current `byType` backed by `mcp_flutter` until the app-side
  `pilot_runtime` semantic Snapshot reaches parity.
- Do not reinterpret non-invasive `widgetRuntimeType` as Scenario `byType`.

#### Coordinate Tap

Mechanism used:

- VM Service extension inventory
- Inspector summary tree

Input:

```text
tapAt(x, y)
```

Output:

```text
No built-in Flutter tapAt extension observed.
No Inspector bounds or center fields observed in getRootWidgetTree output.
```

Feasibility:

- Unsupported as a Flutter-level non-invasive Runtime Adapter action.

Limitations and risks:

- Android `adb shell input tap x y` is a possible device-level route, but that
  uses physical device coordinates and is not Flutter-aware.
- iOS Simulator, physical iOS, desktop, and web each need separate device or
  browser automation paths.
- Device-level taps do not know Flutter widgets, semantics, DPR, view offsets,
  platform chrome, overlays, or whether a target is obscured.

Impact:

- Keep device coordinate tapping as a separate Target Device spike.
- Do not model it as the primary `pilot_runtime` Runtime Adapter action.

## Capability Matrix

| Product capability | Invasive hook evidence | Non-invasive evidence | Status | Decision |
| --- | --- | --- | --- | --- |
| `byKey` for `ValueKey` | macOS and Android hook probes resolved `ValueKey<String>('submit-smoke')` to one ref and tapped it. | Inspector showed key-like text only in `description`; no key field or tap command. | Supported only with hook | Add to future hook-backed `pilot_runtime`; keep out of current DSL. |
| `byWidgetType` / `byWidget` | macOS and Android hook probes resolved `ProbeSubmitButton` and tapped it. | Inspector exposes `widgetRuntimeType`, but no action boundary. | Supported with hook; partial diagnostics non-invasive | Use `byWidgetType`, not `byType`; expose non-invasive type data only as diagnostics. |
| Semantic `byType` | Hook probes resolved `byType: button` to `widgetType: FilledButton` plus `semanticType: button` and tapped it. | Inspector only exposed Dart `widgetRuntimeType`; no `semanticType` action protocol. | Supported with hook; unsupported non-invasive | Preserve current semantic `byType`; implement semantic Snapshot in app hook. |
| Coordinate tap | Hook probes ran `tapAt` on macOS and Android using `flutterLogicalGlobal` coordinates and incremented the counter. | Plain target had no `tapAt` extension and Inspector output had no bounds/center. | Supported with hook; unsupported non-invasive | Keep as low-level runtime operation first; add YAML only after coordinate contract is stable. |
| Widget Tree diagnostics | Hook can provide its own model later. | Inspector `getRootWidgetTree` produced `description`, `valueId`, `widgetRuntimeType`, `creationLocation`, and `textPreview`. | Supported non-invasive diagnostics | Build non-invasive diagnostics in `pilot_runtime` without presenting them as action replay. |
| Replace `mcp_toolkit` action replay | Hook provides the required action boundary. | Plain VM Service does not provide finder-to-tap actions. | Hook required | Use app-side hook as the migration path. |

## Runtime Adapter Impact

`PilotRuntimeAdapter` should map Flutter Pilot's existing contract onto
`pilot_runtime` without leaking service extension names:

```text
RuntimeAdapter.find(Finder)
  -> PilotRuntimeClient.resolveFinder(PilotFinder)
  -> ext.flutter_pilot.resolve

RuntimeAdapter.tap(FinderMatch)
  -> PilotRuntimeClient.tap(ref)
  -> ext.flutter_pilot.tap

RuntimeAdapter.captureSnapshot()
  -> PilotRuntimeClient.captureSnapshot()
  -> ext.flutter_pilot.snapshot
```

Initial `PilotFinder` fields:

```text
byText?        existing exact visible text
byType?        existing Semantic Node Type
byKey?         future hook-backed ValueKey support
byWidgetType?  future hook-backed Dart widget runtime type support
```

Adapter rules:

- Apply Flutter Pilot's strict cardinality at the adapter boundary if the hook
  returns multiple matches.
- Treat refs as opaque and immediate-use only.
- Convert runtime failures into existing Flutter Pilot Step failure messages.
- Keep `McpFlutterRuntimeAdapter` as the default until `PilotRuntimeAdapter`
  reaches parity for current Scenario actions and captures.

## Scenario DSL Impact

No DSL change should land from this research alone.

Future additions should be conservative:

```yaml
steps:
  - tap:
      byKey: submit-smoke

  - tap:
      byWidgetType: ProbeSubmitButton

  - tap:
      byType: button

  - tapAt:
      x: 222
      y: 196
      coordinateSpace: flutterLogicalGlobal
```

Open DSL decisions:

- whether `byKey` accepts only string values first
- whether `byKey` later needs typed values such as `{type: int, value: 42}`
- whether private widget class names are acceptable in portable Scenarios
- whether `tapAt` is a public action or an adapter/debug operation only
- whether coordinate taps should be allowed in reusable Project Scenarios

## Recommended Migration Path

1. Keep `mcp_toolkit` / `flutter-mcp-toolkit` as the default runtime bridge.
2. Create `packages/pilot_runtime/` as an independent package with a VM Service
   client and an app-side hook library.
3. Add a `PilotRuntimeAdapter` behind an experimental environment switch, not a
   public CLI flag.
4. Implement hook-backed semantic Snapshot parity first: visible text,
   Semantic Node Type, opaque refs, bounds, actions, and tap.
5. Implement `tap(ref)` with this priority:
   - semantics action: `SemanticsOwner.performAction(node.id, SemanticsAction.tap)`
   - pointer fallback: `GestureBinding.instance.handlePointerEvent` on
     platforms where the fallback is validated
6. Implement current Scenario parity before new DSL:
   - `byText`
   - semantic `byType`
   - `tap`
   - `type`
   - `scroll`
   - `waitFor`
   - screenshots, Snapshot, Widget Tree, logs
7. Add hook-backed `tapAt` as an internal operation and keep collecting
   platform evidence.
8. Add `byKey` and `byWidgetType` only after contract tests and real smoke
   tests prove cardinality, error output, and action execution.
9. Use non-invasive Inspector support for Widget Tree diagnostics in parallel,
   but do not present it as an action replay replacement.
10. Remove the `mcp_toolkit` dependency only after `PilotRuntimeAdapter` can run
    existing smoke Scenarios and produce equivalent artifacts.

## Implementation Checklist

- Create `packages/pilot_runtime/` with a package README that states
  `Debug Runtime Target` scope.
- Define app-side setup:
  `PilotRuntimeBinding.ensureInitialized()` or equivalent.
- Define release/debug safety rules and test that release builds do not expose
  control extensions.
- Define service extension protocol versions and response envelopes:
  `ok`, `protocolVersion`, `snapshotId`, `matches`, `error`.
- Implement app-side semantic Snapshot using Flutter semantics, not only widget
  class heuristics.
- Implement ref cache lifetime: fresh snapshot refs are valid only for the next
  matching action.
- Implement `resolveFinder` with strict AND semantics for Finder fields.
- Implement `tap(ref)` and return whether the tap used semantic action or
  pointer fallback.
- Implement `tapAt` with `coordinateSpace: flutterLogicalGlobal` and a future
  `viewId` field or explicit single-view limitation.
- Add contract tests around the VM Service client using fake service responses.
- Add Flutter integration smoke tests for macOS and Android first; then add iOS
  Simulator and web before claiming broader platform stability.
- Keep non-invasive Inspector Widget Tree parsing in a separate client module.
- Update Flutter Pilot docs only when the adapter behavior is production-ready.

## Follow-up Spikes

- Semantics parity spike: port the current `mcp_toolkit` semantic node
  classification into a Flutter Pilot-owned Snapshot model.
- Text input spike: verify `SemanticsAction.setText`, focus behavior, clear
  behavior, and keyboard fallback across macOS, Android, iOS Simulator, and web.
- Scroll spike: verify semantic scroll actions and pointer drag deltas with and
  without a Finder.
- Screenshot spike: compare Flutter Inspector screenshot, VM Service paths, and
  device screenshots for artifact quality and portability.
- Logs/runtime errors spike: decide whether `pilot_runtime` reads VM Service
  streams directly or exposes app-side collected logs.
- Web spike: verify which actions require semantic actions and which pointer
  paths fail.
- Multi-view spike: define `viewId`, coordinate origin, and action routing.
- DSL spike: decide when `byKey`, `byWidgetType`, and `tapAt` become public
  Scenario fields.

## Decision

Build `pilot_runtime` as a Flutter Pilot-owned runtime package with both:

- a non-invasive VM Service/Inspector diagnostics client
- an invasive app-side hook for interaction replay

Use the app-side hook as the path to replace `mcp_toolkit` action replay. Use
non-invasive access for diagnostics and calibration, not for `byKey`,
`byWidgetType`, semantic `byType`, or coordinate tapping until future Flutter
SDK evidence proves a stable action boundary.
