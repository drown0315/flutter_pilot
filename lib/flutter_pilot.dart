/// Public API for parsing Scenario YAML and invoking the Flutter Pilot CLI.
///
/// Consumers that only need validation should use `ScenarioParser`. The CLI
/// entrypoint uses `FlutterPilotCli` to convert parse failures into process
/// exit codes and terminal output.
library;

export 'src/cli.dart';
export 'src/artifacts/artifact_store.dart';
export 'src/app_setup.dart';
export 'src/diagnostics/diagnostic_reducer.dart';
export 'src/diagnostics/diagnostic_text_renderer.dart';
export 'src/reports/html_timeline_report.dart';
export 'src/recording/recording_contract.dart';
export 'src/recording/screen_recorder_recording_controller.dart';
export 'src/scenario/project_scenario_discovery.dart';
export 'src/reports/project_run_report.dart';
export 'src/runtime/pilot_runtime_adapter.dart';
export 'src/runtime/pilot_runtime_vm_service.dart';
export 'src/runtime/runtime_adapter_selector.dart';
export 'src/runtime/runtime_contract.dart';
export 'src/diff/run_diff.dart';
export 'src/scenario/scenario.dart';
export 'src/scenario/scenario_dsl_docs.dart';
export 'src/scenario/scenario_parser.dart';
export 'src/execution/scenario_runner.dart';
export 'src/target/step_progress_renderer.dart';
export 'src/target/target_app_launch_progress_renderer.dart';
export 'src/target/target_app_launcher.dart';
export 'src/target/target_device.dart';
export 'src/execution/test_command_support.dart';
export 'src/terminal_style.dart';
