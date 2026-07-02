# CLI

Flutter Pilot exposes a small command surface for validating Scenarios, running
Scenarios, regenerating reports, comparing runs, and checking app setup.

```bash
flutter_pilot --help
```

## validate

Validate a Scenario YAML file without connecting to a Runtime Target.

```bash
flutter_pilot validate scenarios/login.yaml
flutter_pilot validate scenarios/login.yaml --json
```

## test

Launch the Target App Package and run a Scenario.

```bash
flutter_pilot test scenarios/login.yaml
flutter_pilot test scenarios/login.yaml --device "iPhone 15"
flutter_pilot test scenarios/login.yaml --flavor staging
flutter_pilot test scenarios/login.yaml --target lib/main_staging.dart
flutter_pilot test scenarios/login.yaml --until wait_for_error --print snapshot
```

Useful options:

| Option | Meaning |
| --- | --- |
| `--device` | Select the Target Device. |
| `--flavor` | Select the Flutter flavor. |
| `--target` | Select the Flutter app entrypoint file. |
| `--until` | Stop after a Step number or Step label. |
| `--print` | Print diagnostics after an `--until` stop. |
| `--json` | Use machine-readable output where supported. |

## report

Regenerate an HTML timeline report from an existing run directory.

```bash
flutter_pilot report .runs/2026-06-06_12-30_login_error
```

## diff

Compare two Scenario Run directories.

```bash
flutter_pilot diff .runs/before .runs/after
```

## doctor

Check whether the current Target App Package has the setup Flutter Pilot needs.

```bash
flutter_pilot doctor
```

## init

Initialize Flutter Pilot setup in a Target App Package.

```bash
flutter_pilot init
```
