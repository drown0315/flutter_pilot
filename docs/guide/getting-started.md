# Getting Started

Flutter Pilot is a Dart CLI for replaying Flutter UI Scenarios and collecting
debugging artifacts. A Scenario is a YAML file that describes the UI path to
reproduce.

## Install

Install the Flutter Pilot CLI:

```bash
dart pub global activate flutter_pilot
```

After activation, the command is available as:

```bash
flutter_pilot --help
```

From the Target App Package, initialize the app-side setup:

```bash
flutter_pilot init
```

`init` adds the `mcp_toolkit` runtime dependency when it is missing and prints
the `lib/main.dart` bootstrap code to add manually when needed.

Check the setup after making any required `lib/main.dart` change:

```bash
flutter_pilot doctor
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

## Local Development

When working from this repository instead of an installed package, run the local
executable through Dart:

```bash
dart run flutter_pilot --help
```
