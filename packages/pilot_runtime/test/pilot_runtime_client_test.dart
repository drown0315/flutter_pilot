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
            'runtime.action.clearText',
            'runtime.action.enterText',
            'runtime.action.scroll',
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
      expect(session.capabilities, contains('runtime.action.clearText'));
      expect(session.capabilities, contains('runtime.action.enterText'));
      expect(session.capabilities, contains('runtime.action.scroll'));
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
            'runtime.action.clearText',
            'runtime.action.enterText',
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
            'ok': true,
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

    test('throws typed action failure from structured tap response', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        extensionResponses: <String, Map<String, Object?>>{
          PilotRuntimeProtocol.tapExtension: <String, Object?>{
            'ok': false,
            'code': 'notTappable',
            'message': 'Runtime Handle element-1 cannot be tapped.',
          },
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await expectLater(
        client.performTap(handle: 'element-1'),
        throwsA(
          isA<PilotRuntimeActionException>()
              .having(
                (PilotRuntimeActionException error) => error.failure,
                'failure',
                PilotRuntimeActionFailure.notTappable,
              )
              .having(
                (PilotRuntimeActionException error) => error.message,
                'message',
                'Runtime Handle element-1 cannot be tapped.',
              ),
        ),
      );
    });
  });

  group('PilotRuntimeClient text entry', () {
    test('passes opaque Runtime Handle to text extensions', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        extensionResponses: <String, Map<String, Object?>>{
          PilotRuntimeProtocol.clearTextExtension: <String, Object?>{
            'ok': true,
          },
          PilotRuntimeProtocol.enterTextExtension: <String, Object?>{
            'ok': true,
          },
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await client.clearText(handle: 'runtime-match-1');
      await client.enterText(handle: 'runtime-match-1', text: 'a');

      expect(vmService.calledExtensions, <String>[
        PilotRuntimeProtocol.clearTextExtension,
        PilotRuntimeProtocol.enterTextExtension,
      ]);
      expect(vmService.calledParameters, <Map<String, Object?>>[
        <String, Object?>{'handle': 'runtime-match-1'},
        <String, Object?>{'handle': 'runtime-match-1', 'text': 'a'},
      ]);
    });

    test('throws typed action failure from structured text response', () async {
      final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
        extensionResponses: <String, Map<String, Object?>>{
          PilotRuntimeProtocol.clearTextExtension: <String, Object?>{
            'ok': false,
            'code': 'notEditableText',
            'message': 'Runtime Handle element-1 is not editable text.',
          },
        },
      );
      final PilotRuntimeClient client = PilotRuntimeClient(vmService);

      await expectLater(
        client.clearText(handle: 'element-1'),
        throwsA(
          isA<PilotRuntimeActionException>()
              .having(
                (PilotRuntimeActionException error) => error.failure,
                'failure',
                PilotRuntimeActionFailure.notEditableText,
              )
              .having(
                (PilotRuntimeActionException error) => error.message,
                'message',
                'Runtime Handle element-1 is not editable text.',
              ),
        ),
      );
    });
  });

  group('PilotRuntimeClient scroll', () {
    test(
      'passes optional handle and logical-pixel deltas to scroll extension',
      () async {
        final FakePilotRuntimeVmService vmService = FakePilotRuntimeVmService(
          extensionResponses: <String, Map<String, Object?>>{
            PilotRuntimeProtocol.scrollExtension: <String, Object?>{'ok': true},
          },
        );
        final PilotRuntimeClient client = PilotRuntimeClient(vmService);

        await client.performScroll(
          handle: 'runtime-match-1',
          deltaX: 12.5,
          deltaY: -500,
        );
        await client.performScroll(deltaX: 0, deltaY: 300);

        expect(vmService.calledExtensions, <String>[
          PilotRuntimeProtocol.scrollExtension,
          PilotRuntimeProtocol.scrollExtension,
        ]);
        expect(vmService.calledParameters, <Map<String, Object?>>[
          <String, Object?>{
            'deltaX': 12.5,
            'deltaY': -500.0,
            'handle': 'runtime-match-1',
          },
          <String, Object?>{'deltaX': 0.0, 'deltaY': 300.0},
        ]);
      },
    );
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
