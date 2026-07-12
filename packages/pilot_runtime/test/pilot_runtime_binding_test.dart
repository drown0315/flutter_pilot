import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Verifies app-side registration behavior without touching the real VM Service.
void main() {
  group('PilotRuntimeBinding', () {
    setUp(PilotRuntimeBinding.debugResetForTesting);

    test('registers the debug runtime handshake', () async {
      final List<String> registeredExtensions = <String>[];
      final Map<String, PilotRuntimeExtensionHandler> registeredHandlers =
          <String, PilotRuntimeExtensionHandler>{};

      PilotRuntimeBinding.ensureInitialized(
        debugMode: true,
        registerExtension:
            (String extensionName, PilotRuntimeExtensionHandler handler) {
              registeredExtensions.add(extensionName);
              registeredHandlers[extensionName] = handler;
            },
      );

      expect(registeredExtensions, <String>[
        PilotRuntimeProtocol.handshakeExtension,
        PilotRuntimeProtocol.resolveFinderExtension,
        PilotRuntimeProtocol.endOfFrameExtension,
        PilotRuntimeProtocol.tapExtension,
        PilotRuntimeProtocol.clearTextExtension,
        PilotRuntimeProtocol.enterTextExtension,
        PilotRuntimeProtocol.scrollExtension,
        PilotRuntimeProtocol.collectLogsExtension,
      ]);
      expect(
        await registeredHandlers[PilotRuntimeProtocol.handshakeExtension]!(
          const <String, Object?>{},
        ),
        <String, Object?>{
          'protocolVersion': 1,
          'capabilities': <Object?>[
            'runtime.action.clearText',
            'runtime.action.enterText',
            'runtime.action.scroll',
            'runtime.action.tap',
            'runtime.finder.resolve',
            'runtime.frame.end',
            'runtime.handshake',
            'runtime.logs.collect',
          ],
        },
      );
    });

    testWidgets('bounds end-of-frame waiting by timeoutMs', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> registeredHandlers =
          <String, PilotRuntimeExtensionHandler>{};
      PilotRuntimeBinding.ensureInitialized(
        debugMode: true,
        registerExtension:
            (String extensionName, PilotRuntimeExtensionHandler handler) {
              registeredHandlers[extensionName] = handler;
            },
      );

      final Map<String, Object?> response =
          await tester.runAsync(
            () => registeredHandlers[PilotRuntimeProtocol.endOfFrameExtension]!(
              <String, Object?>{'timeoutMs': '1'},
            ),
          ) ??
          <String, Object?>{};

      expect(response['ok'], true);
      expect(response['timedOut'], true);
    });

    test('is a no-op outside debug mode', () {
      final List<String> registeredExtensions = <String>[];

      PilotRuntimeBinding.ensureInitialized(
        debugMode: false,
        registerExtension:
            (String extensionName, PilotRuntimeExtensionHandler handler) {
              registeredExtensions.add(extensionName);
            },
      );

      expect(registeredExtensions, isEmpty);
    });

    testWidgets('parses numeric service extension parameters', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> registeredHandlers =
          <String, PilotRuntimeExtensionHandler>{};

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(child: SizedBox(height: 1000)),
        ),
      );
      addTearDown(PilotRuntimeBinding.debugResetForTesting);
      PilotRuntimeBinding.ensureInitialized(
        debugMode: true,
        registerExtension:
            (String extensionName, PilotRuntimeExtensionHandler handler) {
              registeredHandlers[extensionName] = handler;
            },
      );

      final Map<String, Object?> response =
          await registeredHandlers[PilotRuntimeProtocol.scrollExtension]!(
            <String, Object?>{'deltaX': '0.0', 'deltaY': '-120.5'},
          );
      PilotRuntimeBinding.debugResetForTesting();

      expect(response['ok'], true);
    });

    testWidgets('captures debug prints and Flutter errors as runtime logs', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> registeredHandlers =
          <String, PilotRuntimeExtensionHandler>{};
      final void Function(FlutterErrorDetails)? originalFlutterErrorHandler =
          FlutterError.onError;

      FlutterError.onError = (FlutterErrorDetails details) {};
      addTearDown(PilotRuntimeBinding.debugResetForTesting);
      PilotRuntimeBinding.ensureInitialized(
        debugMode: true,
        captureLogs: true,
        registerExtension:
            (String extensionName, PilotRuntimeExtensionHandler handler) {
              registeredHandlers[extensionName] = handler;
            },
      );

      debugPrint('Submitting checkout form');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('Checkout failed'),
          stack: StackTrace.current,
          library: 'flutter_pilot_test',
          context: ErrorDescription('while submitting checkout'),
        ),
      );

      final Map<String, Object?> response =
          await registeredHandlers[PilotRuntimeProtocol.collectLogsExtension]!(
            const <String, Object?>{},
          );
      PilotRuntimeBinding.debugResetForTesting();
      FlutterError.onError = originalFlutterErrorHandler;

      expect(response['schema'], 'pilot_runtime.logs.v1');
      final List<Object?> entries = response['entries']! as List<Object?>;
      expect(
        entries,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (Map<String, Object?> entry) => entry['level'],
                'level',
                'info',
              )
              .having(
                (Map<String, Object?> entry) => entry['message'],
                'message',
                'Submitting checkout form',
              ),
        ),
      );
      expect(
        entries,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (Map<String, Object?> entry) => entry['level'],
                'level',
                'error',
              )
              .having(
                (Map<String, Object?> entry) => entry['message'],
                'message',
                contains('Checkout failed'),
              ),
        ),
      );
    });
  });
}
