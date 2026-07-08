# Flutter Inspector Summary Widget Tree Calibration - 2026-07-06

## Purpose

This calibration explains what data Flutter Pilot can get from Flutter
Inspector's summary Widget Tree path. It is based on the real probe output in:

```text
calibrate/summary_tree_probe/out/summary-tree2.txt
```

The probe target was:

```text
/Users/drown/flutter_project/flutter_pilot/examples/smoke_app
```

The tested screen includes a `ValueKey` whose value is:

```text
测试
```

This document is written like SDK guidance for developers who need to consume
this data from `pilot_runtime`.

## How To Fetch The Summary Widget Tree

Connect to a running Flutter debug app through VM Service, find the main
isolate, then call two Flutter Inspector service extensions.

First, configure the project root:

```text
ext.flutter.inspector.setPubRootDirectories
args={"arg0":"/path/to/flutter/app"}
```

Then fetch the root Widget Tree:

```text
ext.flutter.inspector.getRootWidgetTree
args={
  "groupName":"pilot_runtime_summary_tree_probe",
  "isSummaryTree":"true",
  "withPreviews":"true",
  "fullDetails":"false"
}
```

Use `setPubRootDirectories` when you want Inspector to mark whether nodes were
created by the configured project root. In this output, every non-root node had
`createdByLocalProject: true`.

Use `isSummaryTree: "true"` when you want the compact Inspector Widget Tree
rather than a full diagnostics dump.

Use `withPreviews: "true"` when you want text widgets to include lightweight
text preview data. In this output, 15 `Text` nodes included `textPreview`.

Use `fullDetails: "false"` for the small summary shape. This output did not
include independent fields for keys, bounds, source locations, layout
constraints, or full properties.

## Probe Output Sections

The calibration CLI writes four sections.

`Service Extension Calls` records the exact Flutter Inspector methods and args.
Use it to reproduce the probe.

`Field Inventory` summarizes which fields appeared across all diagnostics
nodes. Use it to decide which fields can be normalized.

`Compact Tree` renders `description`, `valueId`, and child count as an indented
tree. Use it for quick human inspection.

`Full Summary Tree JSON` contains the decoded Inspector diagnostics object. Use
it when implementing a parser or checking one node in detail.

## Observed Tree Shape

The run returned:

```text
nodes: 39
maxDepth: 7
unique widgetRuntimeType values: 12
```

The top of the tree was:

```text
[root]
  SmokeApp
    MaterialApp
      SmokeHomePage
        Scaffold
          ListView
          AppBar
```

The tree included app-authored widgets such as:

```text
SmokeApp
SmokeHomePage
```

This confirms that the Inspector summary tree is useful for app-level Widget
Tree diagnostics.

## Field Inventory

The observed fields were:

| Field | Count | Type | Notes |
| --- | ---: | --- | --- |
| `description` | 39 | `String` | Human-readable node label. |
| `shouldIndent` | 39 | `bool` | Inspector display hint. |
| `widgetRuntimeType` | 39 | `String` | Widget runtime type. |
| `valueId` | 39 | `String` | Inspector object id. |
| `children` | 36 | `List` | Nested child diagnostics nodes. |
| `createdByLocalProject` | 38 | `bool` | Missing only on `[root]`. |
| `textPreview` | 15 | `String` | Present on `Text` nodes in this run. |

Fields not observed:

```text
key
bounds
sourceLocation
file
line
column
constraints
semanticRole
enabled
tap coordinates
properties
```

## Field Reference

### `valueId`

Use `valueId` when you need the Inspector object id for a node in the current
tree fetch.

Example:

```json
"valueId": "inspector-11"
```

Observed behavior:

- Present on all 39 nodes.
- Values use the `inspector-N` shape.
- Treat the id as Inspector-scoped and snapshot-scoped. Do not persist it as a
  stable identity across rebuilds, hot reloads, hot restarts, app restarts, or
  later tree fetches.

### `description`

Use `description` when you need the display label for a tree row.

Examples from this output:

```text
SmokeApp
SmokeHomePage
ListView
FilledButton-[<'测试'>]
Text
```

Important key observation:

```text
FilledButton-[<'测试'>]
```

The tested `ValueKey` value `测试` did not appear as an independent `key` field.
It appeared inside the button node's `description`.

This means a developer can display key-like Inspector details from
`description`, but should not model key support as a first-class field from
this summary-tree shape alone.

### `widgetRuntimeType`

Use `widgetRuntimeType` when you need the widget runtime type.

Examples from this output:

```text
SmokeApp
MaterialApp
SmokeHomePage
Scaffold
ListView
TextField
FilledButton
AppBar
```

Observed behavior:

- Present on all 39 nodes.
- Cleaner than `description` for type-based filtering.
- For the keyed button, `widgetRuntimeType` was `FilledButton`, while
  `description` was `FilledButton-[<'测试'>]`.

Recommended use:

- Use `widgetRuntimeType` for Widget Tree type filters.
- Use `description` for display and key-like Inspector suffixes.
- Do not confuse `widgetRuntimeType` with Flutter Pilot semantic Snapshot
  `byType` values such as `button`, `textField`, or `text`.

### `children`

Use `children` to traverse the hierarchy.

Observed behavior:

- Present on 36 of 39 nodes.
- Missing on three `SizedBox` leaf nodes.
- Some leaf nodes had `children: []`; others omitted `children`.

Recommended normalized behavior:

```text
children: [] when Inspector omits children
```

This lets consumers traverse one consistent tree model.

### `createdByLocalProject`

Use `createdByLocalProject` as a hint that Inspector associated the node with
the configured pub root.

Observed behavior:

- Present on 38 of 39 nodes.
- Missing only on `[root]`.
- Every observed non-root value was `true`.

This field depends on calling:

```text
ext.flutter.inspector.setPubRootDirectories
```

Treat it as optional metadata. Do not assume future apps or Flutter versions
will mark every non-root node as local.

### `textPreview`

Use `textPreview` when you want lightweight text content from `Text` widgets.

Observed text previews:

```text
Smoke form
Submit smoke
Smoke row 0
Smoke row 1
...
Smoke row 11
Flutter Pilot Smoke
```

Observed behavior:

- Present on 15 of 39 nodes.
- All observed `textPreview` fields were on `Text` nodes.
- The `TextField` node did not include the input label or current value in this
  summary-tree output.
- The `FilledButton` node itself did not include `textPreview`; its child
  `Text` node did.

Use `textPreview` for opportunistic text extraction from widget summaries. Do
not treat it as a complete visible-text or semantics source.

### `shouldIndent`

Use `shouldIndent` only if you need to mirror Flutter Inspector's display
formatting.

Observed behavior:

- Present on all 39 nodes.
- Values were boolean.

For `pilot_runtime`, tree depth from `children` is more useful than
`shouldIndent`.

## Developer Recipes

### If You Want The Widget Hierarchy

Fetch `getRootWidgetTree` with `isSummaryTree: "true"` and traverse `children`.

Normalize each node as:

```text
InspectorSummaryWidgetNode
- id: valueId
- description
- widgetRuntimeType
- createdByLocalProject?
- textPreview?
- children
```

Normalize missing `children` to an empty list.

### If You Want App-Level Widget Names

Read `widgetRuntimeType`.

This output exposed app-level widgets:

```text
SmokeApp
SmokeHomePage
```

That makes this path useful for Widget Tree diagnostics where semantic Snapshot
data is too role-oriented.

### If You Want A Button's Widget Type

Read `widgetRuntimeType`.

For the tested button:

```text
widgetRuntimeType: FilledButton
description: FilledButton-[<'测试'>]
```

The type is cleanly available as `FilledButton`.

### If You Want The Button's ValueKey

This output does not provide a separate `key` field.

The `ValueKey('测试')` value appeared in `description`:

```text
FilledButton-[<'测试'>]
```

So there are two possible strategies:

1. Display-only support:
   Show the full `description` and let developers see the key-like suffix.

2. Experimental parser:
   Parse key-like suffixes from `description`, such as `-[<'测试'>]`.

The recommended v0 contract is display-only. Do not expose `key` as a stable
normalized field until a separate calibration proves a reliable key source or
the parser rule is intentionally accepted.

### If You Want Visible Text

Read `textPreview` from `Text` nodes.

This works for:

```text
Smoke form
Submit smoke
Smoke row N
Flutter Pilot Smoke
```

But this path did not expose `TextField` label/value content. For complete
visible UI state, keep using Snapshot or semantics-oriented capture.

### If You Want TextField Information

The summary tree exposed a `TextField` node:

```text
TextField id=inspector-9
```

It did not expose:

```text
labelText
current value
enabled state
focus state
semantic role
```

Use summary tree to locate that a `TextField` widget exists. Use another
runtime path for form state or semantic details.

### If You Want Keys, Bounds, Or Source Locations

This output does not prove first-class support for those fields.

Run separate probes before adding them to `pilot_runtime`:

```text
fullDetails: "true"
ext.flutter.inspector.getProperties
ext.flutter.inspector.getDetailsSubtree
ext.flutter.inspector.getSelectedWidget
```

## Capability Matrix

| Product capability | Technical evidence | Status | Decision |
| --- | --- | --- | --- |
| Summary Widget Tree hierarchy | `children` produced the app tree from `[root]` to `SmokeHomePage`, `Scaffold`, `ListView`, and `AppBar`. | Supported | Use as Widget Tree hierarchy source. |
| App-level widget identity | `widgetRuntimeType` included `SmokeApp` and `SmokeHomePage`. | Supported | Use for Widget Tree diagnostics. |
| Widget type filtering | `widgetRuntimeType` appeared on all 39 nodes. | Supported | Prefer this over parsing `description`. |
| Human display labels | `description` appeared on all 39 nodes. | Supported | Use for tree rendering. |
| Inspector node id | `valueId` appeared on all 39 nodes. | Supported | Use as snapshot-scoped Inspector id. |
| Local project hint | `createdByLocalProject` appeared on all non-root nodes. | Partial | Keep optional. |
| Text preview | `textPreview` appeared on 15 `Text` nodes. | Partial | Preserve when present; not a complete visible-text source. |
| ValueKey display | `ValueKey('测试')` appeared inside `description` as `FilledButton-[<'测试'>]`. | Partial | Display via `description`; do not expose stable `key` field yet. |
| First-class key field | No independent `key` field appeared. | Unsupported by this output | Requires separate calibration or accepted parser rule. |
| TextField label/value | `TextField` appeared, but no label/value fields appeared. | Unsupported by this output | Use another path. |
| Bounds or coordinates | No bounds field appeared. | Unsupported by this output | Requires separate calibration. |
| Source locations | No source/file/line fields appeared. | Unsupported by this output | Requires separate calibration. |
| Semantic roles/state | No semantic role or enabled state fields appeared. | Unsupported by this output | Keep Snapshot/semantics path separate. |

## Recommended `pilot_runtime` Contract For This Path

The first normalized model for this path should expose only fields proved by
the output:

```text
InspectorSummaryWidgetTree
- root: InspectorSummaryWidgetNode

InspectorSummaryWidgetNode
- id
- description
- widgetRuntimeType
- createdByLocalProject?
- textPreview?
- children
```

Contract rules:

- `id` comes from Flutter Inspector `valueId`.
- `id` is not stable across tree fetches.
- `children` is always present in the normalized model.
- `createdByLocalProject` and `textPreview` are optional.
- key-like strings may appear inside `description`, but `key` is not a stable
  normalized field yet.
- bounds, source locations, semantic roles, and TextField values are not part of
  this path until further calibration proves support.

## Follow-Up

- Probe `fullDetails: "true"` against the same smoke app with
  `ValueKey('测试')`.
- Probe `getProperties` or `getDetailsSubtree` for the keyed `FilledButton`
  node `valueId`.
- Decide whether parsing key suffixes from `description` is acceptable for
  display-only diagnostics or too brittle for `pilot_runtime`.
- Compare this summary tree with semantic Snapshot output for the same screen,
  especially `TextField` label/value and button role.

