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
}
