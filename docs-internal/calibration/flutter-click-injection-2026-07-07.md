# Flutter Click Injection Calibration - 2026-07-07

## Purpose

This calibration records how Flutter Pilot can, and cannot, deliver click
events to a running Flutter app without depending on `flutter-mcp-toolkit` or
other third-party automation libraries.

The immediate product question is whether Flutter Pilot can support these
Scenario capabilities:

- tap by visible text
- tap by Dart `Key`
- tap by Dart Widget runtime type
- tap by explicit coordinates

The main boundary is whether the Target App Package must install an app-side
runtime hook. Current Flutter Pilot language calls runtime access without
Target App code, plugins, hooks, or SDK initialization **Non-invasive Runtime
Access**.

## Product Expectations

- Developers can reproduce a UI path by tapping visible UI text.
- Developers may eventually want more resilient Finders, such as `byKey`.
- Developers may want to tap an app-authored widget type, such as a custom
  button wrapper, not only semantic roles such as `button`.
- Developers may want a low-level coordinate tap for cases where no semantic
  Finder is available.
- Flutter Pilot should not expose a Scenario DSL capability until the runtime
  path is proven stable enough to test and document.

## Technical Approaches Investigated

### Plain Flutter Debug Runtime

Connect to a normal `flutter run` debug app through the VM Service and Flutter
service extensions only.

Evidence:

- Local Flutter SDK: `Flutter 3.44.0`, `Dart 3.12.0`.
- Flutter framework service extensions expose diagnostics and inspector
  surfaces such as widget dumps and Inspector trees, but no built-in stable
  `tapByText`, `tapByKey`, `tapByType`, or `tapAt` VM service extension was
  found in the local Flutter SDK.
- Flutter Inspector summary tree can expose `widgetRuntimeType`, and full
  details may expose source locations, but the calibrated summary output did
  not expose a stable first-class `key` field, bounds field, or tap command.

Decision:

- Plain VM Service access is useful for inspection and diagnostics.
- It is not enough for a stable Flutter-level click injection contract.

### Official Flutter Test And Driver APIs

Use official Flutter control APIs inside a test or driver-enabled app.

Evidence from local Flutter SDK:

- `flutter_test` `WidgetController.tap(finder)` computes the Finder target
  center and then calls `tapAt`.
- `flutter_test` `WidgetController.tapAt(Offset)` dispatches a pointer down/up
  sequence at a given logical coordinate.
- `flutter_test` supports `find.byKey`, `find.byType`, and text Finders inside
  a widget-test binding.
- `flutter_driver` supports `find.byValueKey`, `find.byType`, and
  `driver.tap(finder)`.
- `flutter_driver` implements app-side control through
  `enableFlutterDriverExtension()`. Its tap handler resolves the Finder inside
  the app, waits for a hit-testable target, and calls `WidgetController.tap`.

Decision:

- Official APIs prove that these interactions are technically possible when
  code runs in the app/test isolate.
- They do not provide Non-invasive Runtime Access to an ordinary app unless the
  app is run in a test/driver-controlled mode or registers an app-side hook.

### `mcp_toolkit` Source As Reference Design

Use `mcp_toolkit` only as evidence for an app-side hook architecture. Do not
depend on `flutter-mcp-toolkit` or `mcp_toolkit` for Flutter Pilot's proposed
runtime contract.

Local source inspected:

```text
/Users/drown/.pub-cache/hosted/pub.dev/mcp_toolkit-3.0.0/lib/src/services/semantic_snapshot_service.dart
/Users/drown/.pub-cache/hosted/pub.dev/mcp_toolkit-3.0.0/lib/src/services/gesture_interaction_service.dart
/Users/drown/.pub-cache/hosted/pub.dev/mcp_toolkit-3.0.0/lib/src/toolkits/interaction_toolkit.dart
```

Observed architecture:

```text
semantic_snapshot -> ref -> tap_widget(ref)
```

`SemanticSnapshotService`:

- keeps a `SemanticsHandle` alive with `WidgetsBinding.instance.ensureSemantics`
- walks the current Flutter semantics tree
- assigns sequential refs such as `s_0`
- caches `ref -> SemanticsNode`
- caches `ref -> global bounds`
- caches `ref -> global center`
- returns nodes with fields such as `ref`, `id`, `type`, `label`, `value`,
  `bounds`, and `actions`

`GestureInteractionService.tapAtRef(ref)`:

1. Resolves the cached `SemanticsNode` from the latest snapshot.
2. If the node exposes `SemanticsAction.tap`, calls:

   ```dart
   owner.performAction(node.id, SemanticsAction.tap);
   ```

3. Otherwise resolves the cached global center for the ref.
4. On non-web platforms, synthesizes:

   ```dart
   PointerDownEvent(pointer: pointer, position: position)
   PointerUpEvent(pointer: pointer, position: position)
   ```

   through:

   ```dart
   GestureBinding.instance.handlePointerEvent(...)
   ```

5. On Flutter Web, returns a structured failure when the semantic action is
   absent, because this fallback does not drive the browser gesture pipeline.

Decision:

- The proven pattern is app-side: build a fresh semantic snapshot, return
  opaque refs, and execute actions inside the app isolate.
- `ref` is a runtime-session reference, not a stable Flutter identity.
- This is the strongest reference design for a future Flutter Pilot
  `pilot_runtime` package.

### Device-Level Coordinate Tap

Use platform tools outside Flutter to tap a physical or virtual screen
coordinate.

Evidence:

- Android has a practical device-level route through `adb shell input tap x y`.
- iOS Simulator and physical iOS require different automation routes, such as
  XCTest-oriented tooling, and do not provide the same simple cross-platform
  official shell command.
- Device coordinates do not know Flutter widgets, semantic nodes, DPR,
  multi-view offsets, window chrome, overlays, or whether a target is obscured.

Decision:

- Device-level coordinate tap may be a separate Target Device capability,
  especially for Android.
- It should not be modeled as the primary Flutter Runtime Adapter tap path.

## Evidence Summary

### Official Flutter Test Tap

`WidgetController.tap(finder)`:

- finds the target widget
- computes its center
- delegates to `tapAt`

`WidgetController.tapAt(Offset)`:

- starts a gesture at the provided location
- sends pointer up to complete the tap

Implication:

- Coordinate tap is officially supported inside a Flutter test/controller
  context.
- The missing piece for a normal debug app is an app-side extension that can
  expose this capability through VM Service.

### Official Flutter Driver Tap

`FlutterDriver.tap(finder)` sends a `Tap` command to the driver extension.
The app-side extension:

- creates a Flutter Finder from the serialized driver Finder
- waits for a hit-testable element
- calls `WidgetController.tap`

`flutter_driver` Finder support includes:

- `find.byValueKey` for `String` and `int` values
- `find.byType`, matching `element.widget.runtimeType.toString()`
- text and semantics-label Finders

Implication:

- `byKey` and Dart widget runtime type matching are possible with app-side
  code.
- They are not available through ordinary Flutter debug service extensions by
  default.

### `mcp_toolkit` Tap

`tap_widget` does not accept text directly. Its input is a semantic ref created
by the latest `semantic_snapshot` call.

The interaction chain is:

```text
visible text -> semantic snapshot node -> ref -> tap_widget(ref)
```

The actual click delivery is:

```text
SemanticsOwner.performAction(node.id, SemanticsAction.tap)
```

or, when semantic tap is unavailable and the platform is not web:

```text
GestureBinding.instance.handlePointerEvent(PointerDownEvent)
GestureBinding.instance.handlePointerEvent(PointerUpEvent)
```

Implication:

- The reliable implementation requires code running inside the Target App
  Package.
- Flutter Pilot can use the same architecture without depending on
  `mcp_toolkit`.

## Capability Matrix

| Product capability | Technical evidence | Status | Decision |
| --- | --- | --- | --- |
| Tap by visible text with current `mcp_flutter` path | `semantic_snapshot` exposes text-like fields and refs; current adapter calls `tap_widget(ref)` through `flutter-mcp-toolkit`. | Supported in current integration | Current DSL can keep `byText` while current adapter depends on `mcp_flutter`. |
| Tap by visible text without third-party runtime | Plain Flutter VM Service does not expose `tapByText`; app-side hook can build semantic snapshot refs and invoke tap. | Partial | Requires a Flutter Pilot app-side package before becoming independent of `mcp_toolkit`. |
| Tap by semantic node type | Semantics snapshot can classify nodes as `button`, `textField`, `scrollable`, etc. | Supported with semantic snapshot path | Keep current `byType` meaning as Semantic Node Type, not Dart widget class. |
| Tap by Dart Widget runtime type | Flutter Driver can match `element.widget.runtimeType.toString()`; Inspector summary can expose `widgetRuntimeType` for diagnostics. | Partial | Future/spike for app-side hook. Do not overload current `byType`. |
| Tap by `Key` / `byKey` | Flutter Driver supports `find.byValueKey`; `flutter_test` supports `find.byKey`; current semantic and Inspector summary calibrations do not expose stable first-class keys. | Partial | Future/spike for app-side hook. Do not add to current Scenario DSL yet. |
| Tap by logical coordinate | `WidgetController.tapAt` exists; `mcp_toolkit` fallback sends pointer events with `GestureBinding.instance.handlePointerEvent`. | Supported with app-side code | Add only after `pilot_runtime` hook exists, or expose as lower-level debug action. |
| Device coordinate tap | Android ADB can tap screen coordinates; cross-platform behavior is uneven and not Flutter-aware. | Partial | Separate Target Device spike, not the primary Runtime Adapter tap implementation. |
| Non-invasive Flutter-level click injection | No stable built-in Flutter VM Service tap extension found. | Unsupported | Reject as current contract unless a new external capability is proven. |

## Contract Changes

Current:

- Keep current `byText` and semantic `byType` behavior in the existing DSL.
- Keep `byType` documented as a Semantic Node Type such as `button` or
  `textField`, not a Dart widget class name.
- Keep `byKey` out of the current Scenario DSL.
- Treat current `tap` implementation as adapter-backed behavior, not a
  capability that plain Flutter VM Service provides by itself.

Future:

- Introduce a `pilot_runtime` app-side package if Flutter Pilot should stop
  relying on `mcp_toolkit` for interaction.
- Register Flutter Pilot service extensions from the app-side package.
- Use a `semanticSnapshot -> ref -> action` protocol.
- Implement `tap(ref)` with:
  - primary path: `SemanticsOwner.performAction(node.id, SemanticsAction.tap)`
  - fallback path: `GestureBinding.instance.handlePointerEvent` with pointer
    down/up at cached logical center
- Consider `tapAt(x, y)` as a low-level app-side debug action.
- Consider a distinct `byWidgetType` Finder name if Dart runtime type matching
  becomes supported. Do not reuse current semantic `byType`.
- Consider `byKey` only if the app-side hook resolves keys through Flutter
  Widget/Element traversal or an official test/driver-style Finder path.

Removed or rejected:

- Do not claim plain VM Service can deliver Flutter tap events without app-side
  code.
- Do not parse key-like strings from Inspector `description` as a stable
  `byKey` contract.
- Do not model Android ADB coordinate tap as a Flutter Runtime Adapter Finder
  action.

## Recommended Architecture

Build a Flutter Pilot-owned app-side package, tentatively `pilot_runtime`, and
require Target App Packages to initialize it when they want stable interaction
replay without `mcp_toolkit`.

Possible app code:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PilotRuntimeBinding.instance.bootstrapFlutter(
    () => runApp(const MyApp()),
  );
}
```

The app-side package should register service extensions such as:

```text
ext.flutter_pilot.semanticSnapshot
ext.flutter_pilot.tap
ext.flutter_pilot.tapAt
```

The CLI/runtime adapter should then call those extensions over VM Service.

The first `pilot_runtime` contract should be semantic-first:

```text
semanticSnapshot -> nodes[{ref, type, label, value, bounds, actions}]
tap(ref, snapshotId?)
```

This mirrors the proven `mcp_toolkit` shape while keeping Flutter Pilot's
contract independent.

## Open Questions

- Should Flutter Pilot preserve Non-invasive Runtime Access as the default and
  make app-side `pilot_runtime` setup an explicit higher-capability mode?
- Should `tapAt(x, y)` be exposed in Scenario YAML, or kept as an adapter/debug
  operation until a real user story requires it?
- Should key matching use Widget/Element traversal, Flutter Driver-style
  serialized Finders, or only keys surfaced in a calibrated runtime snapshot?
- Should Dart widget runtime type matching be named `byWidgetType` to avoid
  conflicting with the existing semantic `byType`?
- How should Flutter Web be represented when pointer-event fallback cannot
  drive the browser gesture pipeline and semantic actions are required?

## Follow-Up

- Create a `pilot_runtime` spike issue for app-side service extensions.
- The first app-side hook prototype is now captured in:

  ```text
  examples/smoke_app/lib/pilot_runtime_probe_app.dart
  calibrate/pilot_runtime_hook_probe/bin/pilot_runtime_hook_probe.dart
  calibrate/pilot_runtime_hook_probe/out/hook-probe-macos.txt
  calibrate/pilot_runtime_hook_probe/out/hook-probe-android.txt
  ```

- The prototype verified `byKey`, `byWidgetType`, semantic `byType`, and
  `tapAt` through VM Service service extensions on macOS and Android.
- Add contract tests using a fake VM Service boundary before wiring the real
  adapter.
- Run additional manual smoke tests on iOS Simulator and web to record which
  paths use semantic action versus pointer-event fallback.
- Keep `byKey` and Dart Widget runtime type matching out of public Scenario DSL
  until the production spike proves stable matching, strict cardinality, and
  clear failure behavior.
