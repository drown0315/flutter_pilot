# Getting Started

Flutter Pilot is a Dart CLI for replaying Flutter UI Scenarios and collecting
debugging artifacts. A Scenario is a YAML file that describes the UI path to
reproduce.

## Install

Use the package executable from this repository during local development:

```bash
dart run flutter_pilot --help
```

After activation or installation, the command is:

```bash
flutter_pilot --help
```

## Create a Scenario

Create a YAML file such as `scenarios/login.yaml`:

```yaml scenario
scenario:
  name: login_error
steps:
  - label: submit_login
    tap:
      byText: Log in
      byType: button
  - label: wait_for_error
    waitFor:
      byText: Invalid password
  - label: capture_error
    capture: {}
```

## Validate it

```bash
flutter_pilot validate scenarios/login.yaml
```

Validation checks the Scenario file without connecting to a Runtime Target.

## Run it

From the Target App Package directory:

```bash
flutter_pilot test scenarios/login.yaml
```

The `test` command launches the Target App Package, waits for a Runtime Target,
executes the Scenario, and writes run artifacts.
