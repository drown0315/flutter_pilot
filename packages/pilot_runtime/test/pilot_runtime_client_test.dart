import 'package:flutter_test/flutter_test.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Verifies runtime initialization through the public client handshake API.
void main() {
  group('PilotRuntimeClient handshake', () {
    test('accepts protocol version 1 with required capabilities', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        handshakeResponse: <String, Object?>{
          'protocolVersion': 1,
          'capabilities': <Object?>['runtime.handshake'],
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      final PilotRuntimeSession session = await client.initialize();

      expect(session.protocolVersion, 1);
      expect(session.capabilities, contains('runtime.handshake'));
      expect(vmService.calledExtensions, <String>[
        PilotRuntimeProtocol.handshakeExtension,
      ]);
    });

    test('fails clearly when the runtime hook is missing', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        missingExtension: true,
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<PilotRuntimeInitializationException>()
              .having(
                (PilotRuntimeInitializationException error) => error.failure,
                'failure',
                PilotRuntimeInitializationFailure.missingHook,
              )
              .having(
                (PilotRuntimeInitializationException error) => error.message,
                'message',
                contains('PilotRuntimeBinding.ensureInitialized()'),
              ),
        ),
      );
    });

    test('fails clearly when required capabilities are missing', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        handshakeResponse: <String, Object?>{
          'protocolVersion': 1,
          'capabilities': <Object?>[],
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<PilotRuntimeInitializationException>()
              .having(
                (PilotRuntimeInitializationException error) => error.failure,
                'failure',
                PilotRuntimeInitializationFailure.missingCapability,
              )
              .having(
                (PilotRuntimeInitializationException error) => error.message,
                'message',
                contains('runtime.handshake'),
              ),
        ),
      );
    });

    test('fails clearly when protocol versions do not match', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        handshakeResponse: <String, Object?>{
          'protocolVersion': 2,
          'capabilities': <Object?>['runtime.handshake'],
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<PilotRuntimeInitializationException>()
              .having(
                (PilotRuntimeInitializationException error) => error.failure,
                'failure',
                PilotRuntimeInitializationFailure.protocolVersionMismatch,
              )
              .having(
                (PilotRuntimeInitializationException error) => error.message,
                'message',
                allOf(contains('2'), contains('1')),
              ),
        ),
      );
    });
  });
}

class FakePilotRuntimeVmService implements PilotRuntimeVmService {
  /// Create a fake VM Service that returns one handshake or simulates no hook.
  FakePilotRuntimeVmService({
    this.handshakeResponse = const <String, Object?>{},
    this.missingExtension = false,
  });

  final Map<String, Object?> handshakeResponse;
  final bool missingExtension;
  final List<String> calledExtensions = <String>[];

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String extensionName, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    calledExtensions.add(extensionName);
    if (missingExtension) {
      throw PilotRuntimeServiceExtensionMissingException(extensionName);
    }
    return handshakeResponse;
  }
}
