import 'dart:async';
import 'dart:convert';

import 'package:flutter_pilot/flutter_pilot.dart';

/// Shared fakes and fixtures for `flutter_pilot test` orchestration tests.
class FakeTestCommandExecutor implements TestCommandExecutor {
  FakeTestCommandExecutor({required this.report, this.exception});

  final ScenarioRunReport report;
  final TestCommandException? exception;
  late TestCommandOptions options;
  void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress;
  bool? launchHeartbeatEnabled;
  void Function(StepProgressEvent event)? onProgress;

  @override
  Future<ScenarioRunReport> run(
    TestCommandOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    this.options = options;
    this.onLaunchProgress = onLaunchProgress;
    this.launchHeartbeatEnabled = launchHeartbeatEnabled;
    this.onProgress = onProgress;
    final TestCommandException? exception = this.exception;
    if (exception != null) {
      throw exception;
    }
    return report;
  }
}

class FakeProjectRunExecutor implements ProjectRunExecutor {
  FakeProjectRunExecutor({required this.report});

  final ProjectRunResult report;
  late ProjectRunOptions options;
  bool ran = false;
  void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress;
  bool? launchHeartbeatEnabled;
  void Function(StepProgressEvent event)? onProgress;

  @override
  Future<ProjectRunResult> run(
    ProjectRunOptions options, {
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
    bool launchHeartbeatEnabled = false,
    void Function(StepProgressEvent event)? onProgress,
  }) async {
    this.options = options;
    ran = true;
    this.onLaunchProgress = onLaunchProgress;
    this.launchHeartbeatEnabled = launchHeartbeatEnabled;
    this.onProgress = onProgress;
    return report;
  }
}

ProjectRunResult passedProjectRunResult() {
  return const ProjectRunResult(
    passed: true,
    status: ProjectRunStatus.passed,
    projectRunReportPath: '.runs/project-run/project_run_report.json',
    scenarioReports: <ProjectRunScenarioOutputReport>[],
  );
}

ScenarioRunReport passedScenarioRunReport({TargetDevice? targetDevice}) {
  return ScenarioRunReport(
    scenarioName: 'delegated',
    scenarioDescription: null,
    totalSteps: 0,
    status: ScenarioRunStatus.passed,
    startedAt: DateTime.utc(2026, 6, 30),
    durationMs: 1,
    steps: const <StepRunReport>[],
    runDirectoryPath: '.runs/delegated',
    artifacts: const <ArtifactReport>[],
    targetDevice: targetDevice,
  );
}

ScenarioRunReport passedScenarioRunReportFor(String scenarioName) {
  return ScenarioRunReport(
    scenarioName: scenarioName,
    scenarioDescription: null,
    totalSteps: 1,
    status: ScenarioRunStatus.passed,
    startedAt: DateTime.utc(2026, 7, 1, 9, 30),
    durationMs: 1,
    steps: const <StepRunReport>[
      StepRunReport(
        index: 1,
        label: null,
        action: 'capture',
        status: StepStatus.passed,
        durationMs: 1,
      ),
    ],
    runDirectoryPath: '.runs/child',
    artifacts: const <ArtifactReport>[
      ArtifactReport(type: ArtifactType.runReport, path: 'run_report.json'),
      ArtifactReport(type: ArtifactType.htmlReport, path: 'timeline.html'),
    ],
  );
}

ScenarioRunReport failingScenarioRunReportFor(String scenarioName) {
  return ScenarioRunReport(
    scenarioName: scenarioName,
    scenarioDescription: null,
    totalSteps: 1,
    status: ScenarioRunStatus.failed,
    startedAt: DateTime.utc(2026, 7, 1, 9, 30),
    durationMs: 1,
    steps: const <StepRunReport>[
      StepRunReport(
        index: 1,
        label: null,
        action: 'capture',
        status: StepStatus.failed,
        durationMs: 1,
        failureReason: 'failed',
      ),
    ],
    runDirectoryPath: '.runs/child',
    artifacts: const <ArtifactReport>[],
  );
}

Scenario scenarioFixture(String name) {
  return Scenario(
    name: name,
    steps: const <ScenarioStep>[
      ScenarioStep(
        index: 1,
        action: CaptureAction(
          screenshot: true,
          snapshot: true,
          widgetTree: false,
          logs: true,
        ),
      ),
    ],
  );
}

class FakeDeviceDiscovery implements TestDeviceDiscovery {
  FakeDeviceDiscovery({
    this.flutterDevices = const <FlutterDevice>[],
    this.recordingDevices = const <RecordingDeviceIdentity>[],
    this.flutterDeviceListException,
    this.recordingDeviceListException,
  });

  final List<FlutterDevice> flutterDevices;
  final List<RecordingDeviceIdentity> recordingDevices;
  final DeviceDiscoveryException? flutterDeviceListException;
  final DeviceDiscoveryException? recordingDeviceListException;
  int flutterDeviceListCount = 0;
  int recordingDeviceListCount = 0;

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    flutterDeviceListCount++;
    final DeviceDiscoveryException? exception = flutterDeviceListException;
    if (exception != null) {
      throw exception;
    }
    return flutterDevices;
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    recordingDeviceListCount++;
    final DeviceDiscoveryException? exception = recordingDeviceListException;
    if (exception != null) {
      throw exception;
    }
    return recordingDevices;
  }
}

class FakeTestExecutionSessionFactory implements TestExecutionSessionFactory {
  FakeTestExecutionSessionFactory(this.session);

  final FakeTestExecutionSession session;
  int startCount = 0;
  String? deviceSelector;
  String? flavor;
  String? target;
  bool? recordingRequired;
  bool? launchHeartbeatEnabled;

  @override
  Future<TestExecutionSession> start({
    required String? deviceSelector,
    required String? flavor,
    required String? target,
    required bool recordingRequired,
    required bool launchHeartbeatEnabled,
    void Function(TargetAppLaunchProgressEvent event)? onLaunchProgress,
  }) async {
    startCount++;
    this.deviceSelector = deviceSelector;
    this.flavor = flavor;
    this.target = target;
    this.recordingRequired = recordingRequired;
    this.launchHeartbeatEnabled = launchHeartbeatEnabled;
    return session;
  }
}

class FakeTestExecutionSession implements TestExecutionSession {
  FakeTestExecutionSession({
    required this.runtimeTarget,
    this.targetDevice,
    this.recordingDeviceSelector,
    this.recordingController,
    this.closeException,
  });

  @override
  final RuntimeTarget runtimeTarget;

  @override
  final TargetDevice? targetDevice;

  @override
  final String? recordingDeviceSelector;

  @override
  final RecordingController? recordingController;

  final TestExecutionSessionException? closeException;

  int runWithInterruptCount = 0;
  int closeCount = 0;
  int hotRestartCount = 0;

  @override
  Future<T> runWithInterrupt<T>(Future<T> operation) {
    runWithInterruptCount++;
    return operation;
  }

  @override
  Future<void> hotRestart() async {
    hotRestartCount++;
  }

  @override
  Future<void> close() async {
    closeCount++;
    final TestExecutionSessionException? exception = closeException;
    if (exception != null) {
      throw exception;
    }
  }
}

class FakeScenarioRunnerFactory implements TestScenarioRunnerFactory {
  const FakeScenarioRunnerFactory(this.runner);

  final FakeScenarioRunner runner;

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    runner.runtimeTarget = runtimeTarget;
    runner.targetDevice = targetDevice;
    runner.recordingController = recordingController;
    return runner;
  }
}

class ThrowingScenarioRunnerFactory implements TestScenarioRunnerFactory {
  const ThrowingScenarioRunnerFactory(this.exception);

  final Exception exception;

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    throw exception;
  }
}

class QueueScenarioRunnerFactory implements TestScenarioRunnerFactory {
  QueueScenarioRunnerFactory(this.runners);

  final List<FakeScenarioRunner> runners;
  int _index = 0;

  @override
  TestScenarioRunner create({
    required RuntimeTarget runtimeTarget,
    required TargetDevice? targetDevice,
    required RecordingController? recordingController,
  }) {
    final FakeScenarioRunner runner = runners[_index++];
    runner.runtimeTarget = runtimeTarget;
    runner.targetDevice = targetDevice;
    runner.recordingController = recordingController;
    return runner;
  }
}

class FakeScenarioRunner implements TestScenarioRunner {
  FakeScenarioRunner(this.report);

  final ScenarioRunReport report;
  late RuntimeTarget runtimeTarget;
  TargetDevice? targetDevice;
  RecordingController? recordingController;
  late Scenario scenario;
  void Function(StepProgressEvent event)? onProgress;
  RunArtifactWriter? runArtifactWriter;

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) async {
    this.scenario = scenario;
    this.onProgress = onProgress;
    this.runArtifactWriter = runArtifactWriter;
    onProgress?.call(
      StepStartedEvent(
        scenarioName: scenario.name,
        totalSteps: scenario.steps.length,
        step: scenario.steps.first,
        action: 'tap',
      ),
    );
    onProgress?.call(
      StepFinishedEvent(
        scenarioName: scenario.name,
        totalSteps: scenario.steps.length,
        report: StepRunReport(
          index: scenario.steps.first.index,
          label: scenario.steps.first.label,
          action: 'tap',
          status: StepStatus.passed,
          durationMs: 1,
        ),
      ),
    );
    return report;
  }
}

class FailingScenarioRunner extends FakeScenarioRunner {
  FailingScenarioRunner(super.report);

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) async {
    this.scenario = scenario;
    this.runArtifactWriter = runArtifactWriter;
    return ScenarioRunReport(
      scenarioName: scenario.name,
      scenarioDescription: null,
      totalSteps: scenario.steps.length,
      status: ScenarioRunStatus.failed,
      startedAt: DateTime.utc(2026, 7, 1, 9, 30),
      durationMs: 1,
      steps: const <StepRunReport>[],
      runDirectoryPath: '.runs/child',
      artifacts: const <ArtifactReport>[],
    );
  }
}

class HangingScenarioRunner extends FakeScenarioRunner {
  HangingScenarioRunner() : super(passedScenarioRunReport());

  final Completer<ScenarioRunReport> _completer =
      Completer<ScenarioRunReport>();

  @override
  Future<ScenarioRunReport> run(
    Scenario scenario, {
    RunStopPoint? stopPoint,
    Set<PrintDiagnostic> printDiagnostics = const <PrintDiagnostic>{},
    void Function(StepProgressEvent event)? onProgress,
    RunArtifactWriter? runArtifactWriter,
  }) {
    this.scenario = scenario;
    this.onProgress = onProgress;
    this.runArtifactWriter = runArtifactWriter;
    return _completer.future;
  }
}

class FakeTargetAppProcessStarter implements TargetAppProcessStarter {
  FakeTargetAppProcessStarter(this.process);

  final FakeTargetAppProcess process;
  List<String> startedArguments = const <String>[];
  int startCount = 0;

  @override
  Future<TargetAppProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startCount++;
    startedArguments = arguments;
    return process;
  }
}

class FakeTargetAppProcess implements TargetAppProcess {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  final List<String> stdinWrites = <String>[];
  Object? stdinException;
  bool stdinExceptionOnce = false;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void emitStdout(String line) {
    _stdoutController.add(utf8.encode('$line\n'));
  }

  void emitStderr(String line) {
    _stderrController.add(utf8.encode('$line\n'));
  }

  void exit(int exitCode) {
    _stdoutController.close();
    _stderrController.close();
    _exitCodeCompleter.complete(exitCode);
  }

  @override
  void writeStdin(String text) {
    final Object? exception = stdinException;
    if (exception != null) {
      if (stdinExceptionOnce) {
        stdinException = null;
        stdinExceptionOnce = false;
      }
      throw exception;
    }
    stdinWrites.add(text);
  }

  @override
  bool kill() {
    return true;
  }
}
