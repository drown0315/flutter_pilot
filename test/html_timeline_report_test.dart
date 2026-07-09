import 'dart:io';
import 'dart:typed_data';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies HTML timeline output through public runner and report APIs.
void main() {
  test(
    'highlights failed Steps and renders artifact links or previews',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('html_output');
        final Uint8List screenshotBytes = Uint8List.fromList(<int>[
          137,
          80,
          78,
          71,
        ]);
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          screenshot: ScreenshotCapture(
            bytes: screenshotBytes,
            mimeType: 'image/png',
          ),
          snapshot: const SnapshotCapture(
            data: <String, Object?>{'route': '/login'},
          ),
          logs: const LogsCapture(
            data: <String, Object?>{'entries': <Object?>[]},
          ),
          failures: <RuntimeOperation, RuntimeOperationException>{
            RuntimeOperation.resolveFinder: const RuntimeOperationException(
              operation: RuntimeOperation.resolveFinder,
              message: 'Finder RPC failed.',
            ),
          },
        );
        const Scenario scenario = Scenario(
          name: 'failed_timeline',
          steps: <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'submit',
              action: TapAction(finder: Finder(byText: 'Submit')),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario);

        final String html = File(
          '${report.runDirectoryPath}/timeline.html',
        ).readAsStringSync();
        expect(html, contains('class="step step-failed"'));
        expect(html, contains('Finder RPC failed.'));
        expect(html, contains('captures/0001_submit_screenshot.png'));
        expect(
          html,
          contains('<img src="captures/0001_submit_screenshot.png"'),
        );
        expect(html, contains('captures/0001_submit_widget_tree.json'));
        expect(html, contains('captures/0001_submit_logs.json'));
      });
    },
  );
}
