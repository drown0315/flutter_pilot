import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';

import 'fake_runtime_adapter.dart';

/// In-memory Recording Controller for runner tests.
///
/// It records start attempts without talking to a real device recorder. Tests
/// can provide the Runtime Adapter event list to verify that recording startup
/// happened before any Step requested runtime operations.
class FakeRecordingController implements RecordingController {
  FakeRecordingController({
    this.failure,
    RecordingResult? result,
    List<FakeRuntimeEvent>? runtimeEvents,
  }) : _usesDefaultResult = result == null,
       result =
           result ??
           const RecordingResult(
             path: 'recordings/scenario.mp4',
             mimeType: 'video/mp4',
           ),
       runtimeEvents = runtimeEvents ?? const <FakeRuntimeEvent>[];

  final RecordingException? failure;
  final RecordingResult result;
  final bool _usesDefaultResult;
  final List<FakeRuntimeEvent> runtimeEvents;
  final List<FakeRecordingEvent> events = <FakeRecordingEvent>[];

  @override
  Future<void> prepare() async {
    if (failure?.operation == RecordingOperation.prepare) {
      throw failure!;
    }
    events.add(
      FakeRecordingEvent(
        operation: RecordingOperation.prepare,
        runtimeEventCountAtStart: runtimeEvents.length,
      ),
    );
  }

  @override
  Future<void> start(Scenario scenario) async {
    if (failure?.operation == RecordingOperation.start) {
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

  @override
  Future<RecordingResult> stop() async {
    if (failure?.operation == RecordingOperation.stop) {
      throw failure!;
    }
    events.add(
      FakeRecordingEvent(
        operation: RecordingOperation.stop,
        runtimeEventCountAtStart: runtimeEvents.length,
      ),
    );
    if (_usesDefaultResult) {
      final File recordingFile = File(result.path);
      recordingFile.parent.createSync(recursive: true);
      recordingFile.writeAsBytesSync(<int>[0]);
    }
    return result;
  }

  @override
  Future<void> dispose() async {
    if (failure?.operation == RecordingOperation.dispose) {
      throw failure!;
    }
    events.add(
      FakeRecordingEvent(
        operation: RecordingOperation.dispose,
        runtimeEventCountAtStart: runtimeEvents.length,
      ),
    );
  }
}

/// One call recorded by `FakeRecordingController`.
class FakeRecordingEvent {
  const FakeRecordingEvent({
    required this.operation,
    this.scenarioName,
    required this.runtimeEventCountAtStart,
  });

  final RecordingOperation operation;
  final String? scenarioName;
  final int runtimeEventCountAtStart;
}
