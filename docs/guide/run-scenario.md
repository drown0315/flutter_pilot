# Run a Scenario

Use `validate` before a run when you only want to check the YAML contract.

```bash
flutter_pilot validate scenarios/login.yaml
```

Use `test` when you want Flutter Pilot to launch the Target App Package and run
the Scenario.

```bash
flutter_pilot test scenarios/login.yaml
```

## Select launch options

`test` follows Flutter CLI vocabulary for common launch choices:

```bash
flutter_pilot test scenarios/login.yaml --device "iPhone 15"
flutter_pilot test scenarios/login.yaml --flavor staging
flutter_pilot test scenarios/login.yaml --target lib/main_staging.dart
```

`--device` selects the Target Device. `--target` selects the Flutter app
entrypoint file.

## Stop at a checkpoint

Use `--until` with a Step number or Step label:

```bash
flutter_pilot test scenarios/login.yaml --until wait_for_error
```

Use `--print` with `--until` to inspect diagnostics from that point:

```bash
flutter_pilot test scenarios/login.yaml --until wait_for_error --print snapshot
```
