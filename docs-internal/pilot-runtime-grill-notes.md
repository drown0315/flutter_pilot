# pilot_runtime Grill Notes

Date: 2026-07-08

These notes preserve the current shared understanding from the
`grill-with-docs` session about introducing `pilot_runtime`. They are working
design memory, not a final PRD.

## Accepted Direction

- Build `pilot_runtime` as an independent Flutter package under
  `packages/pilot_runtime/`.
- Keep `mcp_flutter` and `McpFlutterRuntimeAdapter` as the default while
  `pilot_runtime` is implemented and calibrated.
- Add a `PilotRuntimeAdapter` behind the hidden experimental environment switch
  `FLUTTER_PILOT_RUNTIME=pilot_runtime`. Leaving the variable unset, empty, or
  set to `mcp_flutter` keeps the default adapter.
- Do not start replacing `mcp_toolkit` setup, `doctor`, `init`, or the default
  runtime path until `pilot_runtime` is complete enough to replace the current
  adapter.
- `pilot_runtime` v1 uses Invasive Runtime Access. The Target App Package must
  depend on `pilot_runtime` and initialize `PilotRuntimeBinding`.
- There is no Non-invasive Runtime Access fallback for `pilot_runtime` v1.
  Missing app-side runtime initialization is a run-level initialization failure
  before any Scenario Step executes.
- `pilot_runtime` v1 supports Debug Runtime Targets only. macOS desktop and
  Android debug are the first calibrated targets. iOS requires later
  calibration. Flutter Web, profile builds, and release builds are not v1
  support targets.

## Public Package Shape

- `pilot_runtime` exposes one public package:

  ```dart
  import 'package:pilot_runtime/pilot_runtime.dart';
  ```

- The package exports both the Flutter app-side hook API and client API.
- Flutter Pilot consumes the package through `PilotRuntimeAdapter`; runner code
  must not depend directly on VM Service details, Flutter Inspector extension
  names, or app hook extension names.
- The app-side setup uses an explicit debug-mode branch:

  ```dart
  if (kDebugMode) {
    PilotRuntimeBinding.ensureInitialized();
  }
  ```

- `PilotRuntimeBinding.ensureInitialized()` is a no-op outside debug mode.
- CLI execution derives `projectRoot` from the Target App Package working
  directory through the runtime adapter selector/factory path. Users should not
  need to pass project root manually for ordinary `flutter_pilot test` runs.

## Service Extension Protocol

- App-side extensions use the `ext.flutter_pilot.runtime.*` prefix.
- `ext.flutter_pilot.runtime.handshake` is the protocol handshake extension.
- `initialize()` checks the handshake, validates `protocolVersion == 1`, and
  verifies required capabilities before any Scenario Step executes.
- Protocol version mismatches are run-level initialization failures.
- Hot reload and hot restart are `pilot_runtime` client capabilities, but they
  should use VM Service or Flutter runtime paths rather than app-side
  `ext.flutter_pilot.runtime.*` hook extensions.

## Finder DSL

- `byText`, semantic `byType`, `byKey`, and `byWidget` are public Scenario DSL
  Finder fields.
- All Finder fields are single strings.
- All configured Finder fields use AND semantics.
- Strict cardinality remains unchanged: zero matches fail, one match proceeds,
  multiple matches fail.
- `byType` remains a Semantic Node Type such as `button`, `textField`, `text`,
  `scrollable`, or `header`. It is not a Dart widget runtime type.
- `byWidget` is the public field for exact Dart widget runtime type display name
  matching. It intentionally uses the shorter name rather than `byWidgetType`.
- `byKey` v1 supports only `ValueKey<String>` values.
- `byKey` and `byWidget` are general Finder fields, not tap-only fields. They
  apply to `tap`, `type`, `waitFor`, and the optional `scroll` target Finder.
- No `match`, OR semantics, first-match behavior, priority, or fallback chain is
  added.

## Finder Runtime Semantics

- `resolveFinder` returns visible Runtime Target matches, not necessarily
  targets that can execute every action.
- `waitFor` only requires a unique visible match.
- `tap`, `type`, and `scroll` validate action-specific capability when the
  action executes.
- Finder matching should ignore offstage targets, inactive routes, zero-size
  render boxes, and targets known to be invisible. Overlay occlusion is not a
  strong v1 guarantee.
- `byText` is exact user-visible text from Flutter semantics or editable text
  state. It does not promise hidden, offstage, or internal text matching.
- Finder constraints may be satisfied across the same visible target subtree.
  For example, `byWidget` can match an app-authored wrapper while `byText` and
  semantic `byType` match a child button, as long as the runtime can collapse
  the evidence to one Runtime Target match.
- Finder match diagnostics distinguish:
  - `matchedWidgetType`: the widget type that satisfied `byWidget`
  - `actionWidgetType`: the widget type or target that the action will operate
    on when applicable
  - `semanticType`
  - `text`
  - `key`
  - Flutter logical global `bounds`
- Action execution uses an opaque Runtime Handle returned with the match. The
  runner may pass it back for the immediately following action and record it for
  diagnostics, but must not parse it or treat it as stable identity.

## Action Semantics

- `tap` first attempts `SemanticsAction.tap` when available, then falls back to
  a pointer down/up at the target center on calibrated platforms.
- `type` v1 only supports editable text targets. It replaces existing text and
  does not simulate keyboard or IME input.
- `scroll` v1 uses pointer drag gestures and Flutter logical pixel deltas. It
  does not use semantic scroll actions.
- Scroll with a Finder validates that the unique match can be scrolled.
- Scroll without a Finder targets the primary scrollable. If the primary
  scrollable cannot be uniquely determined, the action fails.

## Widget Tree And Capture Artifacts

- Scenario YAML removes the `snapshot` capture option. `snapshot` is not kept as
  a compatibility alias.
- The Runtime Adapter contract should remove `captureSnapshot()`,
  `SnapshotCapture`, and `RuntimeOperation.captureSnapshot`.
- CLI print diagnostics should remove `snapshot`; users should use
  `widget-tree`.
- `capture: {}` defaults to Screenshot, Widget Tree, and Logs.
- Automatic failure diagnostics also include Widget Tree by default.
- Widget Tree artifacts use file names like:

  ```text
  captures/0001_checkpoint_widget_tree.json
  ```

- Run report artifact type is `widgetTree`.
- Widget Tree v1 is a normalized Inspector Summary Widget Tree, not the raw
  Inspector response.
- Widget Tree capture uses:

  ```text
  ext.flutter.inspector.setPubRootDirectories
  ext.flutter.inspector.getRootWidgetTree
  ```

  with:

  ```text
  groupName: pilot_runtime_widget_tree
  isSummaryTree: true
  withPreviews: true
  fullDetails: false
  ```

- Widget Tree capture requires the CLI-derived `projectRoot`. If setting pub
  root directories fails, the Widget Tree capture fails.
- Widget Tree top-level JSON includes:

  ```json
  {
    "schema": "flutter_pilot.widget_tree.v1",
    "source": "flutter_inspector_summary_tree",
    "root": {}
  }
  ```

- Node fields include normalized Inspector data such as:
  - `description`
  - `widgetRuntimeType`
  - `inspectorValueId` from Inspector `valueId`
  - `textPreview` when present
  - `createdByLocalProject` when present
  - `children`
- Widget Tree v1 does not parse keys out of Inspector `description`; `byKey`
  must come from app-side runtime access to real `ValueKey<String>` values.
- `inspectorValueId` is diagnostic only. It is not a Finder Match ref, Runtime
  Handle, key, or stable widget identity.

## Other Runtime Capabilities

- `captureScreenshot` v1 should use a Flutter layer or Flutter Inspector
  screenshot path, not device screenshots.
- `collectLogs()` remains in the Runtime Adapter contract, but `pilot_runtime`
  v1 returns a not-implemented logs payload. A `logs: true` capture should still
  pass and write an artifact that says log collection is not implemented.
- Hot reload and hot restart are required `pilot_runtime` v1 capabilities before
  replacing `mcp_toolkit`, but they are not Scenario Step actions.

## Capability Set Before Replacing mcp_toolkit

`pilot_runtime` should not replace `mcp_toolkit` until these capabilities are
implemented and calibrated:

- initialize and protocol handshake
- resolve Finder fields: `byText`, semantic `byType`, `byKey`, and `byWidget`
- tap
- replace text
- scroll with a Finder
- scroll without a Finder
- capture Screenshot
- capture normalized Widget Tree
- collect Logs as a not-implemented payload
- hot reload
- hot restart
- dispose runtime resources

## ADR

Create an ADR for choosing a Flutter Pilot-owned `pilot_runtime` with Invasive
Runtime Access. This decision reverses earlier product assumptions that
Flutter Pilot would not reimplement low-level runtime control and that
Non-invasive Runtime Access could be the default path.
