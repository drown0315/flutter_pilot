import 'package:flutter_test/flutter_test.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Verifies Widget Tree capture through the public `PilotRuntimeClient` API.
void main() {
  group('PilotRuntimeClient Widget Tree capture', () {
    test('sets pub roots and returns normalized summary tree JSON', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        responses: <String, Map<String, Object?>>{
          PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension:
              <String, Object?>{'result': 'ok'},
          PilotRuntimeInspectorProtocol.getRootWidgetTreeExtension:
              <String, Object?>{
                'description': '[root]',
                'widgetRuntimeType': 'RootWidget',
                'valueId': 'inspector-1',
                'children': <Object?>[
                  <String, Object?>{
                    'description': "FilledButton-[<'submit-smoke'>]",
                    'widgetRuntimeType': 'FilledButton',
                    'valueId': 'inspector-2',
                    'createdByLocalProject': true,
                    'children': <Object?>[
                      <String, Object?>{
                        'description': 'Text',
                        'widgetRuntimeType': 'Text',
                        'valueId': 'inspector-3',
                        'textPreview': 'Submit smoke',
                      },
                    ],
                  },
                ],
              },
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      final Map<String, Object?> widgetTree = await client.captureWidgetTree(
        projectRoot: '/tmp/smoke_app',
      );

      expect(vmService.calls, <FakeVmServiceCall>[
        const FakeVmServiceCall(
          extensionName:
              PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension,
          parameters: <String, Object?>{'arg0': '/tmp/smoke_app'},
        ),
        const FakeVmServiceCall(
          extensionName:
              PilotRuntimeInspectorProtocol.getRootWidgetTreeExtension,
          parameters: <String, Object?>{
            'groupName': 'pilot_runtime_widget_tree',
            'isSummaryTree': 'true',
            'withPreviews': 'true',
            'fullDetails': 'false',
          },
        ),
      ]);
      expect(widgetTree, <String, Object?>{
        'schema': 'flutter_pilot.widget_tree.v1',
        'source': 'flutter_inspector_summary_tree',
        'root': <String, Object?>{
          'description': '[root]',
          'widgetRuntimeType': 'RootWidget',
          'inspectorValueId': 'inspector-1',
          'children': <Object?>[
            <String, Object?>{
              'description': "FilledButton-[<'submit-smoke'>]",
              'widgetRuntimeType': 'FilledButton',
              'inspectorValueId': 'inspector-2',
              'createdByLocalProject': true,
              'children': <Object?>[
                <String, Object?>{
                  'description': 'Text',
                  'widgetRuntimeType': 'Text',
                  'inspectorValueId': 'inspector-3',
                  'textPreview': 'Submit smoke',
                  'children': <Object?>[],
                },
              ],
            },
          ],
        },
      });
      expect(
        (widgetTree['root']! as Map<String, Object?>).containsKey('key'),
        isFalse,
      );
    });

    test(
      'fails clearly when Inspector returns an invalid tree shape',
      () async {
        final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
          responses: <String, Map<String, Object?>>{
            PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension:
                <String, Object?>{'result': 'ok'},
            PilotRuntimeInspectorProtocol.getRootWidgetTreeExtension:
                <String, Object?>{
                  'description': 'Broken',
                  'widgetRuntimeType': 'BrokenWidget',
                },
          },
        );
        final PilotRuntimeClient client = PilotRuntimeClient(vmService);

        await expectLater(
          client.captureWidgetTree(projectRoot: '/tmp/smoke_app'),
          throwsA(
            isA<PilotRuntimeWidgetTreeCaptureException>()
                .having(
                  (PilotRuntimeWidgetTreeCaptureException error) =>
                      error.failure,
                  'failure',
                  PilotRuntimeWidgetTreeCaptureFailure.invalidResponse,
                )
                .having(
                  (PilotRuntimeWidgetTreeCaptureException error) =>
                      error.message,
                  'message',
                  contains('valueId'),
                ),
          ),
        );
      },
    );

    test(
      'normalizes optional missing fields without adding key data',
      () async {
        final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
          responses: <String, Map<String, Object?>>{
            PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension:
                <String, Object?>{'result': 'ok'},
            PilotRuntimeInspectorProtocol.getRootWidgetTreeExtension:
                <String, Object?>{
                  'description': "FilledButton-[<'submit-smoke'>]",
                  'widgetRuntimeType': 'FilledButton',
                  'valueId': 'inspector-2',
                },
          },
        );
        final PilotRuntimeClient client = PilotRuntimeClient(vmService);

        final Map<String, Object?> widgetTree = await client.captureWidgetTree(
          projectRoot: '/tmp/smoke_app',
        );
        final Map<String, Object?> root =
            widgetTree['root']! as Map<String, Object?>;

        expect(root, <String, Object?>{
          'description': "FilledButton-[<'submit-smoke'>]",
          'widgetRuntimeType': 'FilledButton',
          'inspectorValueId': 'inspector-2',
          'children': <Object?>[],
        });
        expect(root.containsKey('key'), isFalse);
        expect(root.containsKey('createdByLocalProject'), isFalse);
        expect(root.containsKey('textPreview'), isFalse);
      },
    );

    test(
      'fails clearly when Inspector cannot set pub root directories',
      () async {
        final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
          responses: <String, Map<String, Object?>>{},
          failures: <String, Object>{
            PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension:
                StateError('pub root rejected'),
          },
        );
        final PilotRuntimeClient client = PilotRuntimeClient(vmService);

        await expectLater(
          client.captureWidgetTree(projectRoot: '/tmp/smoke_app'),
          throwsA(
            isA<PilotRuntimeWidgetTreeCaptureException>()
                .having(
                  (PilotRuntimeWidgetTreeCaptureException error) =>
                      error.failure,
                  'failure',
                  PilotRuntimeWidgetTreeCaptureFailure
                      .setPubRootDirectoriesFailed,
                )
                .having(
                  (PilotRuntimeWidgetTreeCaptureException error) =>
                      error.message,
                  'message',
                  contains('pub root'),
                ),
          ),
        );
      },
    );

    test(
      'fails clearly when Inspector cannot return the summary tree',
      () async {
        final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
          responses: <String, Map<String, Object?>>{
            PilotRuntimeInspectorProtocol.setPubRootDirectoriesExtension:
                <String, Object?>{'result': 'ok'},
          },
          failures: <String, Object>{
            PilotRuntimeInspectorProtocol.getRootWidgetTreeExtension:
                StateError('tree unavailable'),
          },
        );
        final PilotRuntimeClient client = PilotRuntimeClient(vmService);

        await expectLater(
          client.captureWidgetTree(projectRoot: '/tmp/smoke_app'),
          throwsA(
            isA<PilotRuntimeWidgetTreeCaptureException>()
                .having(
                  (PilotRuntimeWidgetTreeCaptureException error) =>
                      error.failure,
                  'failure',
                  PilotRuntimeWidgetTreeCaptureFailure.getRootWidgetTreeFailed,
                )
                .having(
                  (PilotRuntimeWidgetTreeCaptureException error) =>
                      error.message,
                  'message',
                  contains('root summary Widget Tree'),
                ),
          ),
        );
      },
    );
  });
}

class FakePilotRuntimeVmService implements PilotRuntimeVmService {
  /// Create a fake VM Service that returns responses by extension name.
  FakePilotRuntimeVmService({
    required this.responses,
    this.failures = const <String, Object>{},
  });

  final Map<String, Map<String, Object?>> responses;
  final Map<String, Object> failures;
  final List<FakeVmServiceCall> calls = <FakeVmServiceCall>[];

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String extensionName, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    calls.add(
      FakeVmServiceCall(extensionName: extensionName, parameters: parameters),
    );
    final Object? failure = failures[extensionName];
    if (failure != null) {
      throw failure;
    }
    return responses[extensionName] ?? <String, Object?>{};
  }
}

class FakeVmServiceCall {
  /// Create a recorded VM Service extension call for assertions.
  const FakeVmServiceCall({
    required this.extensionName,
    required this.parameters,
  });

  final String extensionName;
  final Map<String, Object?> parameters;

  @override
  bool operator ==(Object other) {
    return other is FakeVmServiceCall &&
        other.extensionName == extensionName &&
        _mapsEqual(other.parameters, parameters);
  }

  @override
  int get hashCode {
    return Object.hash(extensionName, _mapHash(parameters));
  }
}

int _mapHash(Map<String, Object?> map) {
  final List<String> keys = map.keys.toList()..sort();
  return Object.hashAll(keys.map((String key) => Object.hash(key, map[key])));
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final MapEntry<String, Object?> entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
