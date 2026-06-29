import '../runtime/fake_runtime_adapter.dart';
import '../scenario.dart';
import 'recording_contract.dart';

/// In-memory Recording Controller for runner tests.
///
/// It records start attempts without talking to a real device recorder. Tests
/// can provide the Runtime Adapter event list to verify that recording startup
/// happened before any Step requested runtime operations.
class FakeRecordingController implements RecordingController {
  FakeRecordingController({this.failure, List<FakeRuntimeEvent>? runtimeEvents})
    : runtimeEvents = runtimeEvents ?? const <FakeRuntimeEvent>[];

  final RecordingException? failure;
  final List<FakeRuntimeEvent> runtimeEvents;
  final List<FakeRecordingEvent> events = <FakeRecordingEvent>[];

  @override
  Future<void> start(Scenario scenario) async {
    if (failure != null) {
      throw failure!;
    }
    events.add(
      FakeRecordingEvent(
        operation: RecordingOperation.start,
        scenarioName: scenario.name,
        runtimeEventCountAtStart: runtimeEvents.length,
      ),
    );
  }
}

/// One call recorded by `FakeRecordingController`.
class FakeRecordingEvent {
  const FakeRecordingEvent({
    required this.operation,
    required this.scenarioName,
    required this.runtimeEventCountAtStart,
  });

  final RecordingOperation operation;
  final String scenarioName;
  final int runtimeEventCountAtStart;
}
