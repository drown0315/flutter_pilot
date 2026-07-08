# Pilot Runtime Hook Probe

This calibration CLI verifies a minimal `pilot_runtime`-style app hook against
the Flutter Pilot smoke app.

Start the probe target:

```bash
cd examples/smoke_app
flutter run -d macos --debug -t lib/pilot_runtime_probe_app.dart
```

Copy the VM Service WebSocket URI from Flutter output, then run:

```bash
cd calibrate/pilot_runtime_hook_probe
dart pub get
dart run bin/pilot_runtime_hook_probe.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --output out/hook-probe-macos.txt
```

The same probe can run against Android when a device is connected:

```bash
cd examples/smoke_app
flutter run -d <android-device-id> --debug -t lib/pilot_runtime_probe_app.dart

cd calibrate/pilot_runtime_hook_probe
dart run bin/pilot_runtime_hook_probe.dart \
  --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \
  --output out/hook-probe-android.txt
```

The report records:

- available `ext.flutter_pilot.*` service extensions
- a snapshot response excerpt
- `byKey` resolution and tap result
- `byWidgetType` resolution and tap result
- semantic `byType` resolution and tap result
- logical-coordinate `tapAt` result

This is calibration code only. It is not a production `pilot_runtime` package
or Flutter Pilot Runtime Adapter implementation.
