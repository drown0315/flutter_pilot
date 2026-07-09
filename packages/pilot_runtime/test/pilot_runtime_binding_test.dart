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
        PilotRuntimeProtocol.tapExtension,
        PilotRuntimeProtocol.clearTextExtension,
        PilotRuntimeProtocol.enterTextExtension,
        PilotRuntimeProtocol.scrollExtension,
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
            'runtime.handshake',
          ],
        },
      );
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
  });
}
