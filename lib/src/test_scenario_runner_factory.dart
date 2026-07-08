import 'dart:io';

import 'artifacts/artifact_store.dart';
import 'recording/recording_contract.dart';
import 'runtime/runtime_adapter_selector.dart';
import 'runtime/runtime_contract.dart';
import 'scenario.dart';
import 'scenario_runner.dart';
import 'target_device.dart';

/// Creates a Scenario runner for one launched Runtime Target.
abstract interface class TestScenarioRunnerFactory {
  /// Create a runner bound to the launched Runtime Target.
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  });
}

/// Narrow Scenario runner interface used by the `test` command executor.
abstract interface class TestScenarioRunner {
  /// Run `scenario` with optional stop, diagnostic, and Step progress controls.
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics,
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  });
}

/// Default Scenario runner factory backed by the selected Runtime Adapter.
///
/// The normal path remains `McpFlutterRuntimeAdapter`; experimental adapters
/// are selected by `RuntimeAdapterSelector` through hidden environment state.
class DefaultTestScenarioRunnerFactory implements TestScenarioRunnerFactory {
  /// Creates the default runner factory.
  const DefaultTestScenarioRunnerFactory();

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    final RuntimeAdapter adapter = RuntimeAdapterSelector.select(
      target: runtimeTarget,
    );
    return _ScenarioRunnerAdapter(
      ScenarioRunner(
        adapter: adapter,
        recordingController: recordingController,
        targetDevice: targetDevice,
        outputDirectory: Directory.current,
      ),
    );
  }
}

class _ScenarioRunnerAdapter implements TestScenarioRunner {
  const _ScenarioRunnerAdapter(this._runner);

  final ScenarioRunner _runner;

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) {
    return _runner.run(
      scenario,
      stopPoint: stopPoint,
      printDiagnostics: printDiagnostics,
      onProgress: onProgress,
      runArtifactWriter: runArtifactWriter,
    );
  }
}
