import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:pilot_runtime/pilot_runtime.dart';
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

  test(
    'maps pilot_runtime Finder Matches to Runtime Adapter matches',
    () async {
      final _FakePilotRuntimeClient client = _FakePilotRuntimeClient(
        finderMatches: const <PilotRuntimeFinderMatch>[
          PilotRuntimeFinderMatch(
            handle: 'runtime-match-1',
            text: 'Submit',
            semanticType: 'button',
            key: 'submit_label',
            matchedWidgetType: 'Text',
            actionWidgetType: 'ElevatedButton',
            bounds: PilotRuntimeBounds(
              left: 10,
              top: 20,
              width: 100,
              height: 40,
            ),
          ),
        ],
      );
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: client,
        projectRoot: '/target/app',
      );

      final List<FinderMatch> matches = await adapter.resolveFinder(
        const Finder(
          byText: 'Submit',
          byType: 'button',
          byKey: 'submit_label',
          byWidget: 'Text',
        ),
      );

      expect(client.finderRequests.single.byText, 'Submit');
      expect(client.finderRequests.single.byType, 'button');
      expect(client.finderRequests.single.byKey, 'submit_label');
      expect(client.finderRequests.single.byWidget, 'Text');
      expect(matches, hasLength(1));
      expect(matches.single.id, 'runtime-match-1');
      expect(matches.single.text, 'Submit');
      expect(matches.single.key, 'submit_label');
      expect(matches.single.type, 'button');
      expect(matches.single.debugLabel, contains('matchedWidgetType=Text'));
      expect(matches.single.debugLabel, contains('ElevatedButton'));
      expect(matches.single.bounds?.left, 10);
      expect(matches.single.bounds?.top, 20);
      expect(matches.single.bounds?.width, 100);
      expect(matches.single.bounds?.height, 40);
    },
  );

  test(
    'passes opaque Runtime Handle to pilot_runtime tap capability',
    () async {
      final _FakePilotRuntimeClient client = _FakePilotRuntimeClient();
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: client,
        projectRoot: '/target/app',
      );

      await adapter.performTap(const FinderMatch(id: 'runtime-match-1'));

      expect(client.tapHandles, <String>['runtime-match-1']);
    },
  );

  test('maps pilot_runtime tap failures to action failures', () async {
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: _FakePilotRuntimeClient(
        tapFailure: const PilotRuntimeActionException(
          failure: PilotRuntimeActionFailure.notTappable,
          message: 'Runtime Handle element-1 cannot be tapped.',
        ),
      ),
      projectRoot: '/target/app',
    );

    await expectLater(
      adapter.performTap(const FinderMatch(id: 'runtime-match-1')),
      throwsA(
        isA<RuntimeOperationException>()
            .having(
              (RuntimeOperationException error) => error.operation,
              'operation',
              RuntimeOperation.performTap,
            )
            .having(
              (RuntimeOperationException error) => error.message,
              'message',
              'Runtime Handle element-1 cannot be tapped.',
            ),
      ),
    );
  });
}

class _FakePilotRuntimeClient implements PilotRuntimeClient {
  _FakePilotRuntimeClient({
    this.initializeFailure,
    this.tapFailure,
    Map<String, Object?>? widgetTree,
    List<PilotRuntimeFinderMatch>? finderMatches,
  }) : widgetTree = widgetTree ?? <String, Object?>{},
       finderMatches = finderMatches ?? const <PilotRuntimeFinderMatch>[];

  final PilotRuntimeInitializationException? initializeFailure;
  final Object? tapFailure;
  final Map<String, Object?> widgetTree;
  final List<PilotRuntimeFinderMatch> finderMatches;
  final List<String> projectRoots = <String>[];
  final List<
    ({String? byText, String? byType, String? byKey, String? byWidget})
  >
  finderRequests =
      <({String? byText, String? byType, String? byKey, String? byWidget})>[];
  final List<String> tapHandles = <String>[];

  @override
  Future<PilotRuntimeSession> initialize() async {
    final PilotRuntimeInitializationException? failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
    return const PilotRuntimeSession(
      protocolVersion: 1,
      capabilities: <String>{
        'runtime.action.tap',
        'runtime.finder.resolve',
        'runtime.handshake',
      },
    );
  }

  @override
  Future<Map<String, Object?>> captureWidgetTree({
    required String projectRoot,
  }) async {
    projectRoots.add(projectRoot);
    return widgetTree;
  }

  @override
  Future<List<PilotRuntimeFinderMatch>> resolveFinder({
    String? byText,
    String? byType,
    String? byKey,
    String? byWidget,
  }) async {
    finderRequests.add((
      byText: byText,
      byType: byType,
      byKey: byKey,
      byWidget: byWidget,
    ));
    return finderMatches;
  }

  @override
  Future<void> performTap({required String handle}) async {
    final Object? failure = tapFailure;
    if (failure != null) {
      throw failure;
    }
    tapHandles.add(handle);
  }
}
