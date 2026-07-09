import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises the `flutter-mcp-toolkit` Runtime Adapter through a fake command
/// runner.
///
/// The tests verify Flutter Pilot's public Runtime Adapter contract without
/// requiring a live Flutter app or a real `flutter-mcp-toolkit` process.
void main() {
  test(
    'captures screenshots, Widget Tree, and Logs from toolkit responses',
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
      final WidgetTreeCapture widgetTree = await adapter.captureWidgetTree();
      final LogsCapture logs = await adapter.collectLogs();

      expect(screenshot.mimeType, 'image/png');
      expect(screenshot.bytes, <int>[137, 80, 78, 71]);
      expect(widgetTree.data, isA<Map<String, Object?>>());
      expect(logs.data, isA<Map<String, Object?>>());
    },
  );

  test('captures screenshots from tolerant toolkit response shapes', () async {
    final List<Object?> screenshotData = <Object?>[
      <String, Object?>{'base64': 'iVBORw=='},
      <String, Object?>{'png': 'iVBORw=='},
      <String, Object?>{
        'screenshot': <String, Object?>{'image': 'iVBORw=='},
      },
      <String, Object?>{
        'images': <Object?>[
          <String, Object?>{'ignored': true},
          <String, Object?>{'base64': 'iVBORw=='},
        ],
      },
      <String, Object?>{
        'screenshots': <Object?>[
          <String, Object?>{'png': 'iVBORw=='},
        ],
      },
    ];

    for (final Object? data in screenshotData) {
      final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
        target: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
        ),
        commandRunner: (McpFlutterCommandCall call) async {
          return <String, Object?>{'ok': true, 'data': data};
        },
      );

      final ScreenshotCapture screenshot = await adapter.captureScreenshot();

      expect(screenshot.bytes, <int>[137, 80, 78, 71]);
    }
  });

  test(
    'enters cumulative text for character-by-character runner calls',
    () async {
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

      await adapter.clearText(const FinderMatch(id: 'field-1'));
      await adapter.enterText(const FinderMatch(id: 'field-1'), 'a');
      await adapter.enterText(const FinderMatch(id: 'field-1'), 'b');

      expect(calls.map((McpFlutterCommandCall call) => call.name), <String>[
        'enter_text',
        'enter_text',
        'enter_text',
      ]);
      expect(calls[0].arguments['text'], '');
      expect(calls[1].arguments['text'], 'a');
      expect(calls[2].arguments['text'], 'ab');
    },
  );

  test('matches alternate semantic snapshot response shapes', () async {
    final McpFlutterRuntimeAdapter adapter = McpFlutterRuntimeAdapter(
      target: RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      ),
      commandRunner: (McpFlutterCommandCall call) async {
        return <String, Object?>{
          'ok': true,
          'data': <String, Object?>{
            'widgets': <Object?>[
              <String, Object?>{
                'id': 'submit-1',
                'text': 'Submit',
                'valueKey': 'submit_button',
                'widgetType': 'button',
                'bounds': <String, Object?>{
                  'left': 10,
                  'top': 20,
                  'width': 80,
                  'height': 40,
                },
              },
            ],
          },
        };
      },
    );

    final List<FinderMatch> matches = await adapter.resolveFinder(
      const Finder(byText: 'Submit', byType: 'button', byKey: 'submit_button'),
    );

    expect(matches, hasLength(1));
    expect(matches.single.id, 'submit-1');
    expect(matches.single.text, 'Submit');
    expect(matches.single.key, 'submit_button');
    expect(matches.single.type, 'button');
    expect(matches.single.bounds?.left, 10);
  });
}
