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
