import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Verifies app-side visible Finder resolution through the runtime extension.
void main() {
  group('PilotRuntimeBinding Finder resolution', () {
    setUp(PilotRuntimeBinding.debugResetForTesting);

    testWidgets('resolves exact visible byText matches', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Log in'))),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Log in',
      );

      expect(response['matches'], hasLength(1));
      final Object? matchValue = (response['matches']! as List<Object?>).single;
      expect(matchValue, isA<Map<String, Object?>>());
      final Map<String, Object?> match = matchValue! as Map<String, Object?>;
      expect(match['handle'], isA<String>());
      expect(match['text'], 'Log in');
      expect(match['semanticType'], 'text');
      expect(match['actionWidgetType'], 'Text');
      expect(match['bounds'], isA<Map<String, Object?>>());
    });

    testWidgets('resolves semantic byType without Dart widget type matching', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                ElevatedButton(onPressed: () {}, child: const Text('Submit')),
                const Text('button'),
              ],
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byType: 'button',
      );

      expect(response['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(response);
      expect(match['semanticType'], 'button');
      expect(match['actionWidgetType'], 'ElevatedButton');
      expect(match['text'], 'Submit');
    });

    testWidgets('combines byText and byType with AND semantics', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                ElevatedButton(onPressed: () {}, child: const Text('Submit')),
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                const Text('Submit'),
              ],
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Submit',
        byType: 'button',
      );

      expect(response['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(response);
      expect(match['semanticType'], 'button');
      expect(match['actionWidgetType'], 'ElevatedButton');
      expect(match['text'], 'Submit');
    });

    testWidgets('excludes offstage hidden zero-size and transparent targets', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Text('Visible'),
                Offstage(child: Text('Hidden')),
                Visibility(visible: false, child: Text('Hidden')),
                SizedBox.shrink(child: Text('Hidden')),
                Opacity(opacity: 0, child: Text('Hidden')),
              ],
            ),
          ),
        ),
      );

      final Map<String, Object?> hiddenResponse = await _resolveFinder(
        extensions,
        byText: 'Hidden',
      );
      final Map<String, Object?> visibleResponse = await _resolveFinder(
        extensions,
        byText: 'Visible',
      );

      expect(hiddenResponse['matches'], isEmpty);
      expect(visibleResponse['matches'], hasLength(1));
    });

    testWidgets('returns all visible matches for runner cardinality checks', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[Text('Duplicate'), Text('Duplicate')],
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Duplicate',
      );

      expect(response['matches'], hasLength(2));
    });
  });
}

Map<String, PilotRuntimeExtensionHandler> _registerRuntimeExtensions() {
  final Map<String, PilotRuntimeExtensionHandler> extensions =
      <String, PilotRuntimeExtensionHandler>{};
  PilotRuntimeBinding.ensureInitialized(
    debugMode: true,
    registerExtension:
        (String extensionName, PilotRuntimeExtensionHandler handler) {
          extensions[extensionName] = handler;
        },
  );
  return extensions;
}

Future<Map<String, Object?>> _resolveFinder(
  Map<String, PilotRuntimeExtensionHandler> extensions, {
  String? byText,
  String? byType,
}) {
  final Map<String, Object?> parameters = <String, Object?>{};
  if (byText != null) {
    parameters['byText'] = byText;
  }
  if (byType != null) {
    parameters['byType'] = byType;
  }
  return extensions[PilotRuntimeProtocol.resolveFinderExtension]!(parameters);
}

Map<String, Object?> _singleMatch(Map<String, Object?> response) {
  final Object? matchValue = (response['matches']! as List<Object?>).single;
  return matchValue! as Map<String, Object?>;
}
