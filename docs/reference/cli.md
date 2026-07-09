# CLI

Flutter Pilot exposes a small command surface for validating Scenarios, running
Scenarios, regenerating reports, comparing runs, and checking app setup.

```bash
flutter_pilot --help
```

## init

Initialize Flutter Pilot setup in the current Target App Package.

```bash
flutter_pilot init
```

`init` installs the MCP Toolkit runtime dependency when it is missing. It does
not rewrite `lib/main.dart`; when the MCP Toolkit bootstrap is missing, it
prints the import and `runApp` wrapper to add manually.

## doctor

Check whether the current Target App Package has the setup Flutter Pilot needs.

```bash
flutter_pilot doctor
```

Run `doctor` after `init` and after making any required `lib/main.dart` change.

## validate

Validate a Scenario YAML file without connecting to a Runtime Target.

```bash
flutter_pilot validate scenarios/login.yaml
flutter_pilot validate scenarios/login.yaml --json
```

## test

Launch the Target App Package and run a Scenario or Project Run.

```bash
flutter_pilot test
flutter_pilot test scenarios/login.yaml
flutter_pilot test pilot/regression
flutter_pilot test scenarios/login.yaml --device "iPhone 15"
flutter_pilot test scenarios/login.yaml --flavor staging
flutter_pilot test scenarios/login.yaml --target lib/main_staging.dart
flutter_pilot test scenarios/login.yaml --until wait_for_error --print widget-tree
flutter_pilot test scenarios/login.yaml --json
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

With no Scenario file, `test` discovers Project Scenarios under `pilot/`. With
a directory argument, it discovers Project Scenarios under that directory.

## report

Regenerate an HTML timeline report from an existing run directory.

```bash
flutter_pilot report .runs/2026-06-06_12-30_login_error
```

## diff

Compare two Scenario Run directories.

```bash
flutter_pilot diff .runs/before .runs/after
flutter_pilot diff .runs/before .runs/after --json
```
