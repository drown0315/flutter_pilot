import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises the `flutter-mcp-toolkit` Runtime Adapter through a fake command
/// runner.
///
/// The tests verify Flutter Pilot's public Runtime Adapter contract without
/// requiring a live Flutter app or a real `flutter-mcp-toolkit` process.
void main() {
  test('resolves Finder Matches from semantic snapshot refs', () async {
    final List<McpFlutterCommandCall> calls = <McpFlutterCommandCall>[];
    final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
      target: RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      ),
      commandRunner: (McpFlutterCommandCall call) async {
        calls.add(call);
        return <String, Object?>{
          'ok': true,
          'data': <String, Object?>{
            'snapshotId': 7,
            'nodes': <Object?>[
              <String, Object?>{
                'ref': 's_0',
                'label': 'Log in',
                'key': 'login_button',
                'type': 'button',
                'rect': <String, Object?>{
                  'left': 10,
                  'top': 20,
                  'width': 100,
                  'height': 48,
                },
              },
              <String, Object?>{
                'ref': 's_1',
                'label': 'Cancel',
                'key': 'cancel_button',
                'type': 'button',
              },
            ],
          },
          'error': null,
        };
      },
    );

    final List<FinderMatch> matches = await adapter.resolveFinder(
      const Finder(byText: 'Log in', byType: 'button'),
    );

    expect(matches, hasLength(1));
    expect(matches.single.id, 's_0');
    expect(matches.single.debugLabel, 'Log in');
    expect(matches.single.text, 'Log in');
    expect(matches.single.key, 'login_button');
    expect(matches.single.type, 'button');
    expect(matches.single.bounds!.width, 100);
    expect(calls.single.name, 'semantic_snapshot');
    expect(calls.single.arguments, <String, Object?>{
      'connection': <String, Object?>{
        'mode': 'uri',
        'uri': 'ws://127.0.0.1:1234/example=/ws',
      },
    });
  });

  test('executes actions with Finder Match refs', () async {
    final List<McpFlutterCommandCall> calls = <McpFlutterCommandCall>[];
    final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
      target: RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      ),
      commandRunner: (McpFlutterCommandCall call) async {
        calls.add(call);
        return <String, Object?>{'ok': true, 'data': <String, Object?>{}};
      },
    );
    const FinderMatch match = FinderMatch(id: 's_0');

    await adapter.performTap(match);
    await adapter.replaceText(match, 'bad@example.com');
    await adapter.performScroll(match: match, deltaX: 0, deltaY: -500);

    expect(calls.map((McpFlutterCommandCall call) => call.name), <String>[
      'tap_widget',
      'enter_text',
      'scroll',
    ]);
    expect(calls[0].arguments['ref'], 's_0');
    expect(calls[1].arguments['ref'], 's_0');
    expect(calls[1].arguments['text'], 'bad@example.com');
    expect(calls[2].arguments['ref'], 's_0');
    expect(calls[2].arguments['direction'], 'down');
    expect(calls[2].arguments['distance'], 500);
  });

  test(
    'captures screenshots, Snapshots, and Logs from toolkit responses',
    () async {
      final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
        target: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
        ),
        commandRunner: (McpFlutterCommandCall call) async {
          return switch (call.name) {
            'get_screenshots' => <String, Object?>{
              'ok': true,
              'data': <String, Object?>{
                'images': <Object?>['iVBORw=='],
              },
            },
            'semantic_snapshot' => <String, Object?>{
              'ok': true,
              'data': <String, Object?>{
                'nodes': <Object?>[
                  <String, Object?>{'label': 'Log in'},
                ],
              },
            },
            'get_app_errors' => <String, Object?>{
              'ok': true,
              'data': <String, Object?>{
                'errors': <Object?>[
                  <String, Object?>{'message': 'No errors'},
                ],
              },
            },
            _ => <String, Object?>{'ok': true, 'data': <String, Object?>{}},
          };
        },
      );

      final ScreenshotCapture screenshot = await adapter.captureScreenshot();
      final SnapshotCapture snapshot = await adapter.captureSnapshot();
      final LogsCapture logs = await adapter.collectLogs();

      expect(screenshot.mimeType, 'image/png');
      expect(screenshot.bytes, <int>[137, 80, 78, 71]);
      expect(snapshot.data, isA<Map<String, Object?>>());
      expect(logs.data, isA<Map<String, Object?>>());
    },
  );

  test(
    'falls back to flutter layer screenshots when auto capture fails',
    () async {
      final List<McpFlutterCommandCall> calls = <McpFlutterCommandCall>[];
      final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
        target: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
        ),
        commandRunner: (McpFlutterCommandCall call) async {
          calls.add(call);
          if (call.name == 'get_screenshots' &&
              call.arguments['mode'] == 'auto') {
            return <String, Object?>{
              'ok': false,
              'data': null,
              'error': <String, Object?>{'message': 'desktop capture failed'},
            };
          }
          if (call.name == 'get_screenshots' &&
              call.arguments['mode'] == 'flutter_layer') {
            return <String, Object?>{
              'ok': true,
              'data': <String, Object?>{
                'images': <Object?>['iVBORw=='],
              },
            };
          }
          return <String, Object?>{'ok': true, 'data': <String, Object?>{}};
        },
      );

      final ScreenshotCapture screenshot = await adapter.captureScreenshot();

      expect(screenshot.bytes, <int>[137, 80, 78, 71]);
      expect(calls.map((McpFlutterCommandCall call) => call.name), <String>[
        'get_screenshots',
        'get_screenshots',
      ]);
      expect(calls[1].arguments['mode'], 'flutter_layer');
    },
  );

  test('captures Widget Tree from semantic snapshot data', () async {
    final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
      target: RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      ),
      commandRunner: (McpFlutterCommandCall call) async {
        expect(call.name, 'semantic_snapshot');
        return <String, Object?>{
          'ok': true,
          'data': <String, Object?>{
            'nodes': <Object?>[
              <String, Object?>{'type': 'text', 'label': 'Smoke App'},
            ],
          },
        };
      },
    );

    final WidgetTreeCapture widgetTree = await adapter.captureWidgetTree();

    expect(widgetTree.data, <String, Object?>{
      'nodes': <Object?>[
        <String, Object?>{'type': 'text', 'label': 'Smoke App'},
      ],
    });
  });

  test(
    'reports semantic snapshot widget tree failures as widget tree failures',
    () async {
      final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
        target: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
        ),
        commandRunner: (McpFlutterCommandCall call) async {
          expect(call.name, 'semantic_snapshot');
          throw const RuntimeOperationException(
            operation: RuntimeOperation.captureSnapshot,
            message: 'semantic snapshot failed',
          );
        },
      );

      await expectLater(
        adapter.captureWidgetTree(),
        throwsA(
          isA<RuntimeOperationException>().having(
            (RuntimeOperationException error) => error.operation,
            'operation',
            RuntimeOperation.captureWidgetTree,
          ),
        ),
      );
    },
  );
}
