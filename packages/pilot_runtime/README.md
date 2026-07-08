# pilot_runtime

`pilot_runtime` is Flutter Pilot's experimental Flutter runtime package. It
contains the debug app-side hook used by `PilotRuntimeAdapter`. The Dart-only
VM Service client lives in `pilot_runtime_client` so Flutter Pilot's root CLI
can resolve dependencies without a Flutter SDK.

Target App Packages that opt into the experimental runtime initialize the hook
from a debug-mode branch:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

void main() {
  if (kDebugMode) {
    PilotRuntimeBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

The current slice exposes a protocol handshake and normalized Flutter Inspector
Widget Tree capture. It does not yet implement Finder resolution, tap, type,
scroll, screenshot, or logs replay, so Flutter Pilot keeps `mcp_flutter` as the
default runtime bridge.

Tooling that only needs the VM Service client should depend on
`pilot_runtime_client` and import
`package:pilot_runtime_client/pilot_runtime_client.dart`.

Flutter Pilot can select this runtime for calibration with:

```bash
FLUTTER_PILOT_RUNTIME=pilot_runtime flutter_pilot test <scenario.yaml>
```

This switch is intentionally hidden while `pilot_runtime` is incomplete.
