import 'dart:typed_data';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

import 'support/fake_runtime_adapter.dart';

/// Exercises the Runtime Adapter contract through the public package export.
///
/// These tests use a local fake implementation so the runner-facing contract
/// stays independent of a live Runtime Target.
void main() {
  group('RuntimeAdapter contract', () {
    test('represents the VM service URI Runtime Target', () {
      final RuntimeTarget target = RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      );

      expect(target.vmServiceUri.scheme, 'ws');
      expect(target.vmServiceUri.toString(), 'ws://127.0.0.1:1234/example=/ws');
    });
  });

  group('FakeRuntimeAdapter', () {
    test('simulates zero, one, and multiple Finder Matches', () async {
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'missing': const <FinderMatch>[],
          'unique': const <FinderMatch>[
            FinderMatch(id: 'unique-button', text: 'Log in'),
          ],
          'many': const <FinderMatch>[
            FinderMatch(id: 'first-button', text: 'Log in'),
            FinderMatch(id: 'second-button', text: 'Log in'),
          ],
        },
      );

      await adapter.initialize();

      expect(
        await adapter.resolveFinder(const Finder(byText: 'missing')),
        isEmpty,
      );
      expect(
        await adapter.resolveFinder(const Finder(byText: 'unique')),
        hasLength(1),
      );
      expect(
        await adapter.resolveFinder(const Finder(byText: 'many')),
        hasLength(2),
      );

      await adapter.dispose();

      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });

    test('records action arguments for runner assertions', () async {
      const FinderMatch match = FinderMatch(
        id: 'match-1',
        debugLabel: 'button("Log in")',
        text: 'Log in',
        key: 'login_button',
        type: 'button',
        bounds: WidgetBounds(left: 10, top: 20, width: 100, height: 48),
      );
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();

      await adapter.performTap(match);
      await adapter.clearText(match);
      await adapter.enterText(match, 'b');
      await adapter.performScroll(match: match, deltaX: 0, deltaY: -500);

      expect(adapter.events, hasLength(4));
      expect(adapter.events[0].operation, RuntimeOperation.performTap);
      expect(adapter.events[0].match, same(match));
      expect(adapter.events[1].operation, RuntimeOperation.clearText);
      expect(adapter.events[1].match, same(match));
      expect(adapter.events[2].operation, RuntimeOperation.enterText);
      expect(adapter.events[2].match, same(match));
      expect(adapter.events[2].text, 'b');
      expect(adapter.events[3].operation, RuntimeOperation.performScroll);
      expect(adapter.events[3].match, same(match));
      expect(adapter.events[3].deltaX, 0.0);
      expect(adapter.events[3].deltaY, -500.0);
    });

    test('returns configured capture artifacts', () async {
      final Uint8List screenshotBytes = Uint8List.fromList(<int>[137, 80]);
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        screenshot: ScreenshotCapture(
          bytes: screenshotBytes,
          mimeType: 'image/png',
        ),
        snapshot: const SnapshotCapture(
          data: <String, Object?>{
            'visibleText': <Object?>['Log in'],
          },
        ),
        widgetTree: const WidgetTreeCapture(
          data: <String, Object?>{'type': 'Scaffold'},
        ),
        logs: const LogsCapture(
          data: <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{'message': 'runtime error'},
            ],
          },
        ),
      );

      final ScreenshotCapture screenshot = await adapter.captureScreenshot();
      final SnapshotCapture snapshot = await adapter.captureSnapshot();
      final WidgetTreeCapture widgetTree = await adapter.captureWidgetTree();
      final LogsCapture logs = await adapter.collectLogs();

      expect(screenshot.bytes, same(screenshotBytes));
      expect(screenshot.mimeType, 'image/png');
      expect(snapshot.data, <String, Object?>{
        'visibleText': <Object?>['Log in'],
      });
      expect(widgetTree.data, <String, Object?>{'type': 'Scaffold'});
      expect(logs.data, <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{'message': 'runtime error'},
        ],
      });
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.captureScreenshot,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.captureWidgetTree,
          RuntimeOperation.collectLogs,
        ],
      );
    });

    test('simulates runtime operation failures', () async {
      final RuntimeOperationException failure = RuntimeOperationException(
        operation: RuntimeOperation.performTap,
        message: 'tap failed',
        rawOutput: const <String, Object?>{'stderr': 'boom'},
      );
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.performTap: failure,
        },
      );

      expect(
        () => adapter.performTap(const FinderMatch(id: 'button')),
        throwsA(same(failure)),
      );
    });
  });
}
