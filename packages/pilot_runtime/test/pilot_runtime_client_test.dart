import 'package:flutter_test/flutter_test.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Verifies runtime initialization through the public client handshake API.
void main() {
  group('PilotRuntimeClient handshake', () {
    test('accepts protocol version 1 with required capabilities', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        handshakeResponse: <String, Object?>{
          'protocolVersion': 1,
          'capabilities': <Object?>[
            'runtime.action.tap',
            'runtime.finder.resolve',
            'runtime.handshake',
          ],
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      final PilotRuntimeSession session = await client.initialize();

      expect(session.protocolVersion, 1);
      expect(session.capabilities, contains('runtime.handshake'));
      expect(session.capabilities, contains('runtime.finder.resolve'));
      expect(session.capabilities, contains('runtime.action.tap'));
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
          'capabilities': <Object?>[
            'runtime.action.tap',
            'runtime.finder.resolve',
            'runtime.handshake',
          ],
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

  group('PilotRuntimeClient Finder resolution', () {
    test('decodes Finder Matches from the runtime extension', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        extensionResponses: <String, Map<String, Object?>>{
          PilotRuntimeProtocol.resolveFinderExtension: <String, Object?>{
            'matches': <Object?>[
              <String, Object?>{
                'handle': 'runtime-match-1',
                'text': 'Log in',
                'semanticType': 'button',
                'key': 'login_button',
                'matchedWidgetType': 'Text',
                'actionWidgetType': 'ElevatedButton',
                'bounds': <String, Object?>{
                  'left': 10.0,
                  'top': 20.0,
                  'width': 80.0,
                  'height': 40.0,
                },
              },
            ],
          },
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      final List<PilotRuntimeFinderMatch> matches = await client.resolveFinder(
        byText: 'Log in',
        byType: 'button',
        byKey: 'login_button',
        byWidget: 'Text',
      );

      expect(vmService.calledExtensions, <String>[
        PilotRuntimeProtocol.resolveFinderExtension,
      ]);
      expect(vmService.calledParameters.single, <String, Object?>{
        'byText': 'Log in',
        'byType': 'button',
        'byKey': 'login_button',
        'byWidget': 'Text',
      });
      expect(matches, hasLength(1));
      expect(matches.single.handle, 'runtime-match-1');
      expect(matches.single.text, 'Log in');
      expect(matches.single.semanticType, 'button');
      expect(matches.single.key, 'login_button');
      expect(matches.single.matchedWidgetType, 'Text');
      expect(matches.single.actionWidgetType, 'ElevatedButton');
      expect(matches.single.bounds?.left, 10.0);
      expect(matches.single.bounds?.top, 20.0);
      expect(matches.single.bounds?.width, 80.0);
      expect(matches.single.bounds?.height, 40.0);
    });
  });

  group('PilotRuntimeClient tap', () {
    test('passes opaque Runtime Handle to the tap extension', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        extensionResponses: <String, Map<String, Object?>>{
          PilotRuntimeProtocol.tapExtension: <String, Object?>{
            'status': 'ok',
            'method': 'semantic',
          },
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await client.performTap(handle: 'runtime-match-1');

      expect(vmService.calledExtensions, <String>[
        PilotRuntimeProtocol.tapExtension,
      ]);
      expect(vmService.calledParameters.single, <String, Object?>{
        'handle': 'runtime-match-1',
      });
    });
  });
}

class FakePilotRuntimeVmService implements PilotRuntimeVmService {
  /// Create a fake VM Service that returns one handshake or simulates no hook.
  FakePilotRuntimeVmService({
    this.handshakeResponse = const <String, Object?>{},
    this.missingExtension = false,
    Map<String, Map<String, Object?>>? extensionResponses,
  }) : extensionResponses =
           extensionResponses ?? const <String, Map<String, Object?>>{};

  final Map<String, Object?> handshakeResponse;
  final bool missingExtension;
  final Map<String, Map<String, Object?>> extensionResponses;
  final List<String> calledExtensions = <String>[];
  final List<Map<String, Object?>> calledParameters = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String extensionName, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    calledExtensions.add(extensionName);
    calledParameters.add(parameters);
    if (missingExtension) {
      throw PilotRuntimeServiceExtensionMissingException(extensionName);
    }
    final Map<String, Object?>? extensionResponse =
        extensionResponses[extensionName];
    if (extensionResponse != null) {
      return extensionResponse;
    }
    return handshakeResponse;
  }
}
