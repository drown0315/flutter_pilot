import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:pilot_runtime_client/pilot_runtime_client.dart';
import 'package:test/test.dart';

/// Verifies Flutter Pilot's Runtime Adapter backed by `pilot_runtime`.
void main() {
  test(
    'maps pilot_runtime initialization failures to run initialization failures',
    () async {
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: _FakePilotRuntimeClient(
          initializeFailure: const PilotRuntimeInitializationException(
            failure: PilotRuntimeInitializationFailure.missingHook,
            message:
                'PilotRuntimeBinding.ensureInitialized() is not registered '
                'on the debug Runtime Target.',
          ),
        ),
        projectRoot: '/target/app',
      );

      await expectLater(
        adapter.initialize(),
        throwsA(
          isA<RuntimeOperationException>()
              .having(
                (RuntimeOperationException error) => error.operation,
                'operation',
                RuntimeOperation.initialize,
              )
              .having(
                (RuntimeOperationException error) => error.message,
                'message',
                contains('PilotRuntimeBinding.ensureInitialized()'),
              ),
        ),
      );
    },
  );

  test(
    'maps pilot_runtime protocol failures to run initialization failures',
    () async {
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: _FakePilotRuntimeClient(
          initializeFailure: const PilotRuntimeInitializationException(
            failure: PilotRuntimeInitializationFailure.protocolVersionMismatch,
            message:
                'pilot_runtime protocol version 2 is incompatible with '
                'client version 1.',
          ),
        ),
        projectRoot: '/target/app',
      );

      await expectLater(
        adapter.initialize(),
        throwsA(
          isA<RuntimeOperationException>()
              .having(
                (RuntimeOperationException error) => error.operation,
                'operation',
                RuntimeOperation.initialize,
              )
              .having(
                (RuntimeOperationException error) => error.message,
                'message',
                contains('protocol version 2'),
              ),
        ),
      );
    },
  );

  test('returns Widget Tree capture data from pilot_runtime', () async {
    final _FakePilotRuntimeClient client = _FakePilotRuntimeClient(
      widgetTree: <String, Object?>{
        'schema': 'flutter_pilot.widget_tree.v1',
        'source': 'flutter_inspector.summary_tree',
        'root': <String, Object?>{'widgetType': 'MaterialApp'},
      },
    );
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: client,
      projectRoot: '/target/app',
    );

    final WidgetTreeCapture capture = await adapter.captureWidgetTree();

    expect(client.projectRoots, <String>['/target/app']);
    expect(capture.data, <String, Object?>{
      'schema': 'flutter_pilot.widget_tree.v1',
      'source': 'flutter_inspector.summary_tree',
      'root': <String, Object?>{'widgetType': 'MaterialApp'},
    });
  });
}

class _FakePilotRuntimeClient implements PilotRuntimeClient {
  _FakePilotRuntimeClient({
    this.initializeFailure,
    Map<String, Object?>? widgetTree,
  }) : widgetTree = widgetTree ?? <String, Object?>{};

  final PilotRuntimeInitializationException? initializeFailure;
  final Map<String, Object?> widgetTree;
  final List<String> projectRoots = <String>[];

  @override
  Future<PilotRuntimeSession> initialize() async {
    final PilotRuntimeInitializationException? failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
    return const PilotRuntimeSession(
      protocolVersion: 1,
      capabilities: <String>{'runtime.handshake'},
    );
  }

  @override
  Future<Map<String, Object?>> captureWidgetTree({
    required String projectRoot,
  }) async {
    projectRoots.add(projectRoot);
    return widgetTree;
  }
}
