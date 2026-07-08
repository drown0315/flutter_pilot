# Summary Tree Probe

This calibration CLI fetches Flutter Inspector summary Widget Tree data from a
running Flutter debug app. It follows the same VM Service approach used by:

```text
/Users/drown/ai_project/ask_ui/apps/bridge
```

## Usage

From this directory:

```bash
dart pub get
dart run bin/summary_tree_probe.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --project-root /path/to/flutter/app
```

To include Flutter Inspector full details, including `creationLocation` when
Flutter can provide it:

```bash
dart run bin/summary_tree_probe.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --project-root /path/to/flutter/app \
  --full-details
```

To write the report to a file instead of stdout:

```bash
dart run bin/summary_tree_probe.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --project-root /path/to/flutter/app \
  --full-details \
  --output out/summary-tree.txt
```

The command prints:

- the main isolate id
- the Inspector service-extension calls used
- a field inventory across the returned diagnostics tree
- a compact node listing
- the full decoded Inspector summary tree JSON

When `--output` is provided, the same report is written to that file and the
terminal prints only the saved path.

When `--full-details` is provided, the probe passes `fullDetails: "true"` to
`ext.flutter.inspector.getRootWidgetTree`. Flutter Inspector may then include
fields such as `creationLocation` and `locationId`. The compact tree prints
`location=<file>:<line>:<column>` when `creationLocation` is available.

To record the Flutter/Dart service extensions available on a plain debug app,
run:

```bash
dart run bin/service_extension_inventory.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --output out/plain-runtime-service-extensions-macos.txt
```

The inventory is useful for proving which official Flutter debug extensions are
available without a Flutter Pilot app hook.

Recent outputs used by `docs-internal/mcp-toolkit-replacement-research.md`:

```text
out/plain-runtime-service-extensions-macos.txt
out/plain-runtime-full-details-macos.txt
out/pilot-runtime-probe-full-details-macos.txt
```

## Notes

This is calibration code only. It should not be treated as a Flutter Pilot
Runtime Adapter implementation.
