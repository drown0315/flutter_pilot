import 'package:flutter_test/flutter_test.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Verifies app-side registration behavior without touching the real VM Service.
void main() {
  group('PilotRuntimeBinding', () {
    setUp(PilotRuntimeBinding.debugResetForTesting);

    test('registers the debug runtime handshake', () async {
      final List<String> registeredExtensions = <String>[];
      PilotRuntimeExtensionHandler? registeredHandler;

      PilotRuntimeBinding.ensureInitialized(
        debugMode: true,
        registerExtension:
            (String extensionName, PilotRuntimeExtensionHandler handler) {
              registeredExtensions.add(extensionName);
              registeredHandler = handler;
            },
      );

      expect(registeredExtensions, <String>[
        PilotRuntimeProtocol.handshakeExtension,
      ]);
      expect(await registeredHandler!(), <String, Object?>{
        'protocolVersion': 1,
        'capabilities': <Object?>['runtime.handshake'],
      });
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
