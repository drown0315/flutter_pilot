import 'dart:io';
import 'dart:typed_data';

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

  test('returns Logs capture data from pilot_runtime', () async {
    final _FakePilotRuntimeClient client = _FakePilotRuntimeClient(
      logs: <String, Object?>{
        'schema': 'pilot_runtime.logs.v1',
        'entries': <Object?>[
          <String, Object?>{
            'level': 'info',
            'message': 'Submitting checkout form',
          },
        ],
      },
    );
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: client,
      projectRoot: '/target/app',
    );

    final LogsCapture capture = await adapter.collectLogs();

    expect(client.collectedLogs, isTrue);
    expect(capture.data, <String, Object?>{
      'schema': 'pilot_runtime.logs.v1',
      'entries': <Object?>[
        <String, Object?>{
          'level': 'info',
          'message': 'Submitting checkout form',
        },
      ],
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

  test(
    'passes opaque Runtime Handle to pilot_runtime text capabilities',
    () async {
      final _FakePilotRuntimeClient client = _FakePilotRuntimeClient();
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: client,
        projectRoot: '/target/app',
      );

      await adapter.clearText(const FinderMatch(id: 'runtime-match-1'));
      await adapter.enterText(const FinderMatch(id: 'runtime-match-1'), 'a');

      expect(client.clearTextHandles, <String>['runtime-match-1']);
      expect(client.enterTextRequests, <({String handle, String text})>[
        (handle: 'runtime-match-1', text: 'a'),
      ]);
    },
  );

  test('maps pilot_runtime text failures to action failures', () async {
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: _FakePilotRuntimeClient(
        clearTextFailure: const PilotRuntimeActionException(
          failure: PilotRuntimeActionFailure.notEditableText,
          message: 'Runtime Handle element-1 is not editable text.',
        ),
      ),
      projectRoot: '/target/app',
    );

    await expectLater(
      adapter.clearText(const FinderMatch(id: 'runtime-match-1')),
      throwsA(
        isA<RuntimeOperationException>()
            .having(
              (RuntimeOperationException error) => error.operation,
              'operation',
              RuntimeOperation.clearText,
            )
            .having(
              (RuntimeOperationException error) => error.message,
              'message',
              'Runtime Handle element-1 is not editable text.',
            ),
      ),
    );
  });

  test(
    'passes scroll handle and logical-pixel deltas to pilot_runtime',
    () async {
      final _FakePilotRuntimeClient client = _FakePilotRuntimeClient();
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: client,
        projectRoot: '/target/app',
      );

      await adapter.performScroll(
        match: const FinderMatch(id: 'runtime-match-1'),
        deltaX: 12.5,
        deltaY: -500,
      );

      expect(client.scrollRequests, <({String? handle, double dx, double dy})>[
        (handle: 'runtime-match-1', dx: 12.5, dy: -500),
      ]);
    },
  );

  test('maps pilot_runtime scroll failures to action failures', () async {
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: _FakePilotRuntimeClient(
        scrollFailure: const PilotRuntimeActionException(
          failure: PilotRuntimeActionFailure.notScrollable,
          message: 'Runtime Handle element-1 does not identify a scrollable.',
        ),
      ),
      projectRoot: '/target/app',
    );

    await expectLater(
      adapter.performScroll(
        match: const FinderMatch(id: 'runtime-match-1'),
        deltaX: 0,
        deltaY: -120,
      ),
      throwsA(
        isA<RuntimeOperationException>()
            .having(
              (RuntimeOperationException error) => error.operation,
              'operation',
              RuntimeOperation.performScroll,
            )
            .having(
              (RuntimeOperationException error) => error.message,
              'message',
              'Runtime Handle element-1 does not identify a scrollable.',
            ),
      ),
    );
  });

  test(
    'captures Flutter device screenshot bytes for the selected device',
    () async {
      final _FakeFlutterScreenshotCapturer screenshotCapturer =
          _FakeFlutterScreenshotCapturer(
            bytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
          );
      final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
        client: _FakePilotRuntimeClient(),
        projectRoot: '/target/app',
        targetDeviceId: 'pixel-8',
        screenshotCapturer: screenshotCapturer,
      );

      final ScreenshotCapture capture = await adapter.captureScreenshot();

      expect(screenshotCapturer.deviceIds, <String>['pixel-8']);
      expect(capture.mimeType, 'image/png');
      expect(capture.bytes, <int>[137, 80, 78, 71]);
    },
  );

  test('maps Flutter screenshot failures to capture failures', () async {
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: _FakePilotRuntimeClient(),
      projectRoot: '/target/app',
      targetDeviceId: 'pixel-8',
      screenshotCapturer: _FakeFlutterScreenshotCapturer(
        failure: const FlutterScreenshotException(
          message: 'Flutter screenshot failed.',
          exitCode: 1,
          stderr: 'No device found.',
        ),
      ),
    );

    await expectLater(
      adapter.captureScreenshot(),
      throwsA(
        isA<RuntimeOperationException>()
            .having(
              (RuntimeOperationException error) => error.operation,
              'operation',
              RuntimeOperation.captureScreenshot,
            )
            .having(
              (RuntimeOperationException error) => error.message,
              'message',
              contains('Flutter screenshot failed.'),
            )
            .having(
              (RuntimeOperationException error) => error.rawOutput,
              'rawOutput',
              contains('No device found.'),
            ),
      ),
    );
  });

  test('requires a selected Target Device for Flutter screenshots', () async {
    final PilotRuntimeAdapter adapter = PilotRuntimeAdapter(
      client: _FakePilotRuntimeClient(),
      projectRoot: '/target/app',
    );

    await expectLater(
      adapter.captureScreenshot(),
      throwsA(
        isA<RuntimeOperationException>()
            .having(
              (RuntimeOperationException error) => error.operation,
              'operation',
              RuntimeOperation.captureScreenshot,
            )
            .having(
              (RuntimeOperationException error) => error.message,
              'message',
              contains('Pass --device'),
            ),
      ),
    );
  });

  test('runs flutter screenshot for the selected device', () async {
    final _FakeFlutterScreenshotProcessRunner processRunner =
        _FakeFlutterScreenshotProcessRunner();
    final FlutterCliScreenshotCapturer capturer = FlutterCliScreenshotCapturer(
      processRunner: processRunner,
    );

    final Uint8List bytes = await capturer.captureDeviceScreenshot(
      deviceId: 'pixel-8',
    );

    expect(processRunner.executable, 'flutter');
    expect(processRunner.arguments.take(3), <String>[
      'screenshot',
      '-d',
      'pixel-8',
    ]);
    expect(processRunner.arguments, contains('--out'));
    expect(bytes, <int>[137, 80, 78, 71]);
  });
}

class _FakeFlutterScreenshotCapturer implements FlutterScreenshotCapturer {
  _FakeFlutterScreenshotCapturer({Uint8List? bytes, this.failure})
    : bytes = bytes ?? Uint8List(0);

  final Uint8List bytes;
  final FlutterScreenshotException? failure;
  final List<String> deviceIds = <String>[];

  @override
  Future<Uint8List> captureDeviceScreenshot({required String deviceId}) async {
    deviceIds.add(deviceId);
    final FlutterScreenshotException? currentFailure = failure;
    if (currentFailure != null) {
      throw currentFailure;
    }
    return bytes;
  }
}

class _FakeFlutterScreenshotProcessRunner
    implements FlutterScreenshotProcessRunner {
  String? executable;
  List<String> arguments = <String>[];

  @override
  Future<FlutterScreenshotProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    this.executable = executable;
    this.arguments = arguments;
    final int outputIndex = arguments.indexOf('--out') + 1;
    final String outputPath = arguments[outputIndex];
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(<int>[137, 80, 78, 71]);
    return const FlutterScreenshotProcessResult(exitCode: 0);
  }
}

class _FakePilotRuntimeClient implements PilotRuntimeClient {
  _FakePilotRuntimeClient({
    this.initializeFailure,
    this.tapFailure,
    this.clearTextFailure,
    this.scrollFailure,
    Map<String, Object?>? widgetTree,
    Map<String, Object?>? logs,
    List<PilotRuntimeFinderMatch>? finderMatches,
  }) : widgetTree = widgetTree ?? <String, Object?>{},
       logs = logs ?? <String, Object?>{},
       finderMatches = finderMatches ?? const <PilotRuntimeFinderMatch>[];

  final PilotRuntimeInitializationException? initializeFailure;
  final Object? tapFailure;
  final Object? clearTextFailure;
  final Object? scrollFailure;
  final Map<String, Object?> widgetTree;
  final Map<String, Object?> logs;
  final List<PilotRuntimeFinderMatch> finderMatches;
  final List<String> projectRoots = <String>[];
  bool collectedLogs = false;
  final List<
    ({String? byText, String? byType, String? byKey, String? byWidget})
  >
  finderRequests =
      <({String? byText, String? byType, String? byKey, String? byWidget})>[];
  final List<String> tapHandles = <String>[];
  final List<String> clearTextHandles = <String>[];
  final List<({String handle, String text})> enterTextRequests =
      <({String handle, String text})>[];
  final List<({String? handle, double dx, double dy})> scrollRequests =
      <({String? handle, double dx, double dy})>[];

  @override
  Future<PilotRuntimeSession> initialize() async {
    final PilotRuntimeInitializationException? failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
    return const PilotRuntimeSession(
      protocolVersion: 1,
      capabilities: <String>{
        'runtime.action.clearText',
        'runtime.action.enterText',
        'runtime.action.scroll',
        'runtime.action.tap',
        'runtime.finder.resolve',
        'runtime.handshake',
        'runtime.logs.collect',
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
  Future<Map<String, Object?>> collectLogs() async {
    collectedLogs = true;
    return logs;
  }

  @override
  Future<PilotRuntimeReloadResult> hotReload() async {
    return const PilotRuntimeReloadResult(
      operation: PilotRuntimeReloadOperation.hotReload,
      success: true,
      response: <String, Object?>{'type': 'ReloadReport', 'success': true},
    );
  }

  @override
  Future<PilotRuntimeReloadResult> hotRestart() async {
    return const PilotRuntimeReloadResult(
      operation: PilotRuntimeReloadOperation.hotRestart,
      success: true,
      response: <String, Object?>{'type': 'ReloadReport', 'success': true},
    );
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

  @override
  Future<void> clearText({required String handle}) async {
    final Object? failure = clearTextFailure;
    if (failure != null) {
      throw failure;
    }
    clearTextHandles.add(handle);
  }

  @override
  Future<void> enterText({required String handle, required String text}) async {
    enterTextRequests.add((handle: handle, text: text));
  }

  @override
  Future<void> performScroll({
    String? handle,
    required double deltaX,
    required double deltaY,
  }) async {
    final Object? failure = scrollFailure;
    if (failure != null) {
      throw failure;
    }
    scrollRequests.add((handle: handle, dx: deltaX, dy: deltaY));
  }
}
