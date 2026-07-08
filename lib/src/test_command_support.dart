/// Compatibility export for the `test` command execution support modules.
///
/// The public package API originally exposed these types through `cli.dart`.
/// Keeping this barrel lets callers import one stable support surface while the
/// implementations live in focused files.
library;

export 'project_run_command_executor.dart';
export 'test_command_executor.dart';
export 'test_command_models.dart';
export 'test_command_output.dart';
export 'test_device_discovery.dart';
export 'test_scenario_runner_factory.dart';
