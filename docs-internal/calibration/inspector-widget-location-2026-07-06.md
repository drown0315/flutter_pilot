# Flutter Inspector Widget Location Calibration - 2026-07-06

## Purpose

This note records how to investigate source-code locations for widgets returned
by Flutter Inspector's Widget Tree APIs.

## Finding

Flutter Inspector can include widget creation locations in diagnostics JSON, but
the summary tree probe previously disabled the field by passing:

```text
fullDetails: "false"
```

Flutter SDK source shows that `creationLocation` and `locationId` are only
added when Inspector serializes full details.

Relevant local Flutter SDK source:

```text
/Users/drown/development/flutter/packages/flutter/lib/src/widgets/widget_inspector.dart
```

The important behavior:

```text
ext.flutter.inspector.getRootWidgetTree
- reads fullDetails from parameters
- defaults fullDetails to true when omitted
- passes fullDetails into _nodeToJson

InspectorSerializationDelegate.additionalNodeProperties
- reads the node creation location
- adds locationId and creationLocation only when fullDetails is true
- may still add createdByLocalProject even when fullDetails is false
```

## How To Probe Widget Code Locations

Run the summary tree probe with `--full-details`:

```bash
cd calibrate/summary_tree_probe
dart run bin/summary_tree_probe.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --project-root /path/to/flutter/app \
  --full-details \
  --output out/summary-tree-full-details.txt
```

This calls:

```text
ext.flutter.inspector.getRootWidgetTree
args={
  "groupName":"pilot_runtime_summary_tree_probe",
  "isSummaryTree":"true",
  "withPreviews":"true",
  "fullDetails":"true"
}
```

## Expected Fields

When Flutter Inspector can resolve a widget's creation location, expect fields
like:

```text
creationLocation
locationId
```

The compact tree in the probe prints a location suffix when
`creationLocation` exists:

```text
- SmokeHomePage id=inspector-3 children=1 location=/path/to/main.dart:24:9
```

The exact `creationLocation` map shape should be confirmed from real probe
output before adding it to `pilot_runtime`'s stable model. Likely fields include
file, line, and column, but the contract should be based on observed output.

## Observed Full-Details Output - 2026-07-07

The full-details probe was run against the hook-free calibration target:

```text
examples/smoke_app/lib/plain_runtime_probe_app.dart
```

Output file:

```text
calibrate/summary_tree_probe/out/plain-runtime-full-details-macos.txt
```

Observed field inventory:

```text
nodes: 34
- creationLocation: 34 node(s); Map=34
- locationId: 34 node(s); int=34
- valueId: 34 node(s); String=34
- widgetRuntimeType: 34 node(s); String=34
- textPreview: 13 node(s); String=13
```

Observed `creationLocation` shape:

```json
{
  "file": "file:///Users/drown/.treehouse/flutter_pilot-b6aa0b/1/flutter_pilot/examples/smoke_app/lib/pilot_runtime_probe_app.dart",
  "line": 54,
  "column": 17,
  "name": "ProbeSubmitButton"
}
```

The same output still did not expose first-class `key`, `bounds`, `center`, or
semantic role fields. The `ValueKey` appeared only in `description`:

```text
ProbeSubmitButton-[<'submit-smoke'>]
```

## Contract Guidance

For `pilot_runtime`, treat widget code location as optional metadata:

```text
InspectorSummaryWidgetNode
- sourceLocation?
```

Do not require it for every widget. Flutter can only provide creation locations
when the framework has that information for the diagnostics node.

Do not infer support from `createdByLocalProject`. That field can appear even
when `creationLocation` is omitted from the JSON because `fullDetails` is false.

## Follow-Up

- Keep `sourceLocation` optional in any future `pilot_runtime` Widget Tree
  model.
- Decide whether `pilot_runtime` should expose source locations immediately or
  keep them as calibration-only until more apps are tested.
- Do not infer key, bounds, or tap support from full-details Inspector output.
