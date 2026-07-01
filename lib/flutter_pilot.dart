/// Public API for parsing Scenario YAML and invoking the Flutter Pilot CLI.
///
/// Consumers that only need validation should use `ScenarioParser`. The CLI
/// entrypoint uses `FlutterPilotCli` to convert parse failures into process
/// exit codes and terminal output.
library;

export 'src/cli.dart';
export 'src/artifacts/artifact_store.dart';
export 'src/app_setup.dart';
export 'src/diagnostic_reducer.dart';
export 'src/diagnostic_text_renderer.dart';
export 'src/html_timeline_report.dart';
export 'src/recording/fake_recording_controller.dart';
export 'src/recording/recording_contract.dart';
export 'src/recording/screen_recorder_recording_controller.dart';
export 'src/runtime/fake_runtime_adapter.dart';
export 'src/runtime/mcp_flutter_runtime_adapter.dart';
export 'src/runtime/runtime_contract.dart';
export 'src/run_diff.dart';
export 'src/scenario.dart';
export 'src/scenario_parser.dart';
export 'src/scenario_runner.dart';
export 'src/step_progress_renderer.dart';
export 'src/target_app_launcher.dart';
export 'src/target_device.dart';
export 'src/terminal_style.dart';
