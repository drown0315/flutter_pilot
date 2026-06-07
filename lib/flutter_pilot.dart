/// Public API for parsing Scenario YAML and invoking the Flutter Pilot CLI.
///
/// Consumers that only need validation should use `ScenarioParser`. The CLI
/// entrypoint uses `FlutterPilotCli` to convert parse failures into process
/// exit codes and terminal output.
library;

export 'src/cli.dart';
export 'src/scenario.dart';
export 'src/scenario_parser.dart';
