# mcp_flutter Calibration - 2026-06-09

Issue: `#1 Define Runtime Adapter Contract`

## Purpose

This calibration records what was manually checked before implementing the real
`mcp_flutter` adapter. The Runtime Adapter contract should stay in Flutter Pilot
terms while the real implementation chooses the best available `mcp_flutter`
API or CLI path.

## Discovery

Command:

```bash
flutter-mcp-toolkit exec --name discover_debug_apps --args "{}"
```

Result:

- `ok`: `true`
- target count: `1`
- target id: `ws://127.0.0.1:64198/86P2GkwJSx4=/ws`
- discovery source: `flutter_tool_machine`
- strategy used: `machine_only`

Implication:

- The CLI discovery path can find a running Flutter debug app.
- `RuntimeTarget.vmServiceUri` as a `Uri` is still the right first-version
  target representation.

## API vs CLI

Status: not completed in this pass.

Decision for implementation:

- Prefer a direct `mcp_flutter` API/SDK call path if it is available and exposes
  structured data.
- Use `flutter-mcp-toolkit` CLI subprocess execution only as a fallback.
- Do not leak API or CLI raw response shapes into the runner-facing Runtime
  Adapter contract.

## Pending Manual Checks

These still need to be run against the discovered target before the real
`mcp_flutter` adapter implementation is locked:

- screenshot capture, preferring PNG output
- semantic snapshot structure
- Logs capture, including whether runtime errors are included
- Finder by exact text
- Finder by logical key string is not available through the calibrated
  `semantic_snapshot` response shape
- Finder by semantic node type from `mcp_flutter` `semantic_snapshot`
- multiple Finder Match descriptions
- WidgetBounds availability and coordinate space
- scroll by delta without a Finder Match

## Contract Notes

- `FinderMatch.id` remains opaque and valid only for the action immediately
  following the Finder resolution that produced it.
- `ScreenshotCapture` contains one `Uint8List` image and a MIME type.
- `SnapshotCapture`, `WidgetTreeCapture`, and `LogsCapture` carry decoded
  JSON-compatible `Object` data in the first version. Stronger structures can be
  introduced after real `mcp_flutter` responses are calibrated.

## Finder Support Boundary - 2026-06-19

Issue: `#44 Calibrate real Finder support and document byKey boundary`

The real smoke integration path should verify the Finder fields that are part
of the current Scenario DSL: `byText`, `byType`, and combined constraints using
both fields. `byKey` remains outside the current Scenario contract because
`mcp_flutter` does not currently provide stable key-based Finder matching.

| Product capability | Technical evidence | Status | Decision |
| --- | --- | --- | --- |
| `byText` Finder | `McpFlutterRuntimeAdapter` resolves text from `semantic_snapshot` node fields such as `label`, `text`, or `name`. | Supported | Current DSL and smoke integration coverage. |
| `byType` Finder | `McpFlutterRuntimeAdapter` resolves semantic node type from `semantic_snapshot` node fields such as `type` or `widgetType`. | Supported | Current DSL and smoke integration coverage. |
| Combined Finder constraints | The adapter applies every configured Finder field to the same semantic Snapshot node before producing a Finder Match. | Supported | Current DSL and smoke integration coverage for `byText` plus `byType`. |
| `byKey` Finder | The calibrated `mcp_flutter` path does not expose stable key-based matching for Scenario Finders. | Unsupported | Future capability only; do not add to Scenario YAML, parser, or examples yet. |

Contract decision:

- Current Finder integration coverage should target `byText`, `byType`, and
  combined `byText` plus `byType`.
- `byKey` should stay documented as unsupported in the current Scenario DSL.
- If a future `mcp_flutter` version exposes stable key data, recalibrate the
  real response shape before adding `byKey` to the parser or public docs.

## Widget Tree Calibration Follow-Up - 2026-06-13

Command currently used by Flutter Pilot:

```bash
flutter-mcp-toolkit exec --name get_view_details --args '{"connection":{"mode":"uri","uri":"ws://127.0.0.1:<port>/<token>/ws"}}'
```

Flutter Pilot reads `data.widgetTree` from that response for
`--print widget-tree`.

Observed behavior against `examples/smoke_app`:

- `get_view_details.widgetTree` is a toolkit view-details tree, not a guaranteed
  complete source-level Flutter Widget tree.
- The tree contains many framework/runtime wrapper nodes such as `RootWidget`,
  `View`, `RawView`, `_FocusInheritedScope`, `Semantics`, `Actions`, and
  `Shortcuts`.
- The tree exposed `SmokeApp`, but did not expose `SmokeHomePage` in the tested
  run even though `SmokeHomePage` exists in `examples/smoke_app/lib/main.dart`.
- `semantic_snapshot` exposed the text field as `type: textField` with label
  `Email` and value `smoke@example.com`, but `get_view_details.widgetTree` did
  not reliably expose an app-level `TextField` node in the terminal-relevant
  portion of the returned tree.

Implications:

- `--print snapshot` remains the reliable path for visible text, text fields,
  buttons, scrollables, and interaction-oriented state.
- `--print widget-tree` should be treated as raw or near-raw runtime hierarchy
  context, not as a complete source Widget tree.
- Flutter Pilot's terminal renderer may filter framework wrapper nodes for
  readability, but it must keep raw `printedDiagnostics` in `run_report.json`
  so the underlying toolkit response remains available.
- If future work needs source-level widgets such as `SmokeHomePage`, recalibrate
  whether `flutter-mcp-toolkit` can expose `ext.flutter.inspector.getRootWidgetTree`,
  `ext.flutter.inspector.getRootWidgetSummaryTree`, or `ext.flutter.debugDumpApp`
  through a stable command/API path. The current `capabilities` output exposes
  dump commands such as `debug_dump_render_tree` and
  `debug_dump_semantics_tree`, but those are render/semantics trees rather than
  source Widget trees.
