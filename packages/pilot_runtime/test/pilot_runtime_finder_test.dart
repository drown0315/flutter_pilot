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

    testWidgets('resolves one textField match for a Material TextField', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byType: 'textField',
      );

      expect(response['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(response);
      expect(match['semanticType'], 'textField');

      final Map<String, Object?> clearResponse = await _clearText(
        extensions,
        handle: match['handle']! as String,
      );
      expect(clearResponse['ok'], isTrue);
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

    testWidgets('resolves visible ValueKey<String> matches only', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Text('Login', key: ValueKey<String>('login_label')),
                Text('Count', key: ValueKey<int>(1)),
              ],
            ),
          ),
        ),
      );

      final Map<String, Object?> stringKeyResponse = await _resolveFinder(
        extensions,
        byKey: 'login_label',
      );
      final Map<String, Object?> intKeyResponse = await _resolveFinder(
        extensions,
        byKey: '1',
      );

      expect(stringKeyResponse['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(stringKeyResponse);
      expect(match['key'], 'login_label');
      expect(match['matchedWidgetType'], 'Text');
      expect(intKeyResponse['matches'], isEmpty);
    });

    testWidgets('combines a keyed ListView with its internal scrollable role', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              key: const ValueKey<String>('target_scroll_list'),
              itemCount: 20,
              itemBuilder: (BuildContext context, int index) {
                return SizedBox(height: 48, child: Text('Item $index'));
              },
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byKey: 'target_scroll_list',
        byType: 'scrollable',
      );

      expect(response['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(response);
      expect(match['key'], 'target_scroll_list');
      expect(match['semanticType'], 'scrollable');
    });

    testWidgets('resolves exact byWidget runtime type display names', (
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
                const Text('ElevatedButton'),
              ],
            ),
          ),
        ),
      );

      final Map<String, Object?> widgetResponse = await _resolveFinder(
        extensions,
        byWidget: 'ElevatedButton',
      );
      final Map<String, Object?> semanticResponse = await _resolveFinder(
        extensions,
        byType: 'ElevatedButton',
      );

      expect(widgetResponse['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(widgetResponse);
      expect(match['matchedWidgetType'], 'ElevatedButton');
      expect(match['semanticType'], 'button');
      expect(semanticResponse['matches'], isEmpty);
    });

    testWidgets(
      'combines text key widget and semantic evidence into one match',
      (WidgetTester tester) async {
        final Map<String, PilotRuntimeExtensionHandler> extensions =
            _registerRuntimeExtensions();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  ElevatedButton(
                    key: const ValueKey<String>('submit_button'),
                    onPressed: () {},
                    child: const Text('Submit'),
                  ),
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
          byKey: 'submit_button',
          byWidget: 'ElevatedButton',
        );

        expect(response['matches'], hasLength(1));
        final Map<String, Object?> match = _singleMatch(response);
        expect(match['text'], 'Submit');
        expect(match['semanticType'], 'button');
        expect(match['key'], 'submit_button');
        expect(match['matchedWidgetType'], 'ElevatedButton');
        expect(match['actionWidgetType'], 'ElevatedButton');
      },
    );

    testWidgets('combines wrapper key and child text without byType', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              key: ValueKey<String>('message_wrapper'),
              padding: EdgeInsets.all(8),
              child: Text('Saved'),
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Saved',
        byKey: 'message_wrapper',
      );

      expect(response['matches'], hasLength(1));
      final Map<String, Object?> match = _singleMatch(response);
      expect(match['text'], 'Saved');
      expect(match['key'], 'message_wrapper');
      expect(match['matchedWidgetType'], 'Padding');
    });

    testWidgets('tap performs semantic tap action for a resolved handle', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              button: true,
              onTap: () {
                taps += 1;
              },
              child: const Text('Semantic submit'),
            ),
          ),
        ),
      );
      final SemanticsHandle semantics = tester.ensureSemantics();

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byType: 'button',
      );
      final Map<String, Object?> match = _singleMatch(response);

      await _tap(extensions, handle: match['handle']! as String);
      await tester.pump();

      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets(
      'tap falls back to pointer center tap when semantics is absent',
      (WidgetTester tester) async {
        final Map<String, PilotRuntimeExtensionHandler> extensions =
            _registerRuntimeExtensions();
        int taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureDetector(
                key: const ValueKey<String>('pointer_target'),
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  taps += 1;
                },
                child: const SizedBox(width: 80, height: 40),
              ),
            ),
          ),
        );

        final Map<String, Object?> response = await _resolveFinder(
          extensions,
          byKey: 'pointer_target',
        );
        final Map<String, Object?> match = _singleMatch(response);

        await _tap(extensions, handle: match['handle']! as String);
        await tester.pump();

        expect(taps, 1);
      },
    );

    testWidgets('tap delegates from a custom wrapper to a tappable child', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _CustomTapWrapper(
              key: const ValueKey<String>('custom_wrapper_target'),
              onTap: () {
                taps += 1;
              },
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byKey: 'custom_wrapper_target',
        byWidget: '_CustomTapWrapper',
      );
      final Map<String, Object?> match = _singleMatch(response);

      await _tap(extensions, handle: match['handle']! as String);
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('tap falls back to pointer center tap for Material buttons', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              key: const ValueKey<String>('material_button_target'),
              onPressed: () {
                taps += 1;
              },
              child: const Text('Material submit'),
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Material submit',
        byType: 'button',
      );
      final Map<String, Object?> match = _singleMatch(response);

      await _tap(extensions, handle: match['handle']! as String);
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('tap fails clearly for a non-tappable resolved handle', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Read only'))),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Read only',
      );
      final Map<String, Object?> match = _singleMatch(response);

      final Map<String, Object?> tapResponse = await _tap(
        extensions,
        handle: match['handle']! as String,
      );

      expect(tapResponse['ok'], false);
      expect(tapResponse['code'], 'notTappable');
      expect(tapResponse['message'], contains('cannot be tapped'));
    });

    testWidgets('clears and appends editable text through a resolved handle', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      final TextEditingController controller = TextEditingController(
        text: 'old',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey<String>('email_input'),
              controller: controller,
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byKey: 'email_input',
        byType: 'textField',
      );
      final Map<String, Object?> match = _singleMatch(response);

      final Map<String, Object?> clearResponse = await _clearText(
        extensions,
        handle: match['handle']! as String,
      );
      final Map<String, Object?> firstEntryResponse = await _enterText(
        extensions,
        handle: match['handle']! as String,
        text: 'a',
      );
      final Map<String, Object?> secondEntryResponse = await _enterText(
        extensions,
        handle: match['handle']! as String,
        text: 'b',
      );
      await tester.pump();

      expect(clearResponse['ok'], true);
      expect(firstEntryResponse['ok'], true);
      expect(secondEntryResponse['ok'], true);
      expect(controller.text, 'ab');
    });

    testWidgets('type fails clearly for a non-editable resolved handle', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Read only'))),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Read only',
      );
      final Map<String, Object?> match = _singleMatch(response);

      final Map<String, Object?> typeResponse = await _clearText(
        extensions,
        handle: match['handle']! as String,
      );

      expect(typeResponse['ok'], false);
      expect(typeResponse['code'], 'notEditableText');
      expect(typeResponse['message'], contains('editable text'));
    });

    testWidgets('scroll drags a targeted scrollable by logical-pixel deltas', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: ListView.builder(
                key: const ValueKey<String>('target_list'),
                controller: controller,
                itemCount: 30,
                itemBuilder: (BuildContext context, int index) {
                  return SizedBox(height: 48, child: Text('Item $index'));
                },
              ),
            ),
          ),
        ),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byKey: 'target_list',
      );
      final Map<String, Object?> match = _singleMatch(response);

      final Map<String, Object?> scrollResponse = await _scroll(
        extensions,
        handle: match['handle']! as String,
        deltaX: 0,
        deltaY: -120,
      );
      await tester.pumpAndSettle();

      expect(scrollResponse['ok'], true);
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('scroll fails clearly for a non-scrollable resolved handle', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Read only'))),
      );

      final Map<String, Object?> response = await _resolveFinder(
        extensions,
        byText: 'Read only',
      );
      final Map<String, Object?> match = _singleMatch(response);

      final Map<String, Object?> scrollResponse = await _scroll(
        extensions,
        handle: match['handle']! as String,
        deltaX: 0,
        deltaY: -120,
      );

      expect(scrollResponse['ok'], false);
      expect(scrollResponse['code'], 'notScrollable');
      expect(scrollResponse['message'], contains('scrollable'));
    });

    testWidgets('scroll drags the primary scrollable when no handle is given', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: ListView.builder(
                controller: controller,
                itemCount: 30,
                itemBuilder: (BuildContext context, int index) {
                  return SizedBox(height: 48, child: Text('Item $index'));
                },
              ),
            ),
          ),
        ),
      );

      final Map<String, Object?> scrollResponse = await _scroll(
        extensions,
        deltaX: 0,
        deltaY: -120,
      );
      await tester.pumpAndSettle();

      expect(scrollResponse['ok'], true);
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('scroll fails when primary scrollable is ambiguous', (
      WidgetTester tester,
    ) async {
      final Map<String, PilotRuntimeExtensionHandler> extensions =
          _registerRuntimeExtensions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    children: const <Widget>[Text('Left'), Text('Left 2')],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: const <Widget>[Text('Right'), Text('Right 2')],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final Map<String, Object?> scrollResponse = await _scroll(
        extensions,
        deltaX: 0,
        deltaY: -120,
      );

      expect(scrollResponse['ok'], false);
      expect(scrollResponse['code'], 'primaryScrollableUnavailable');
      expect(scrollResponse['message'], contains('ambiguous'));
    });
  });
}

class _CustomTapWrapper extends StatelessWidget {
  const _CustomTapWrapper({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(width: 80, height: 40),
    );
  }
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
  String? byKey,
  String? byWidget,
}) {
  final Map<String, Object?> parameters = <String, Object?>{};
  if (byText != null) {
    parameters['byText'] = byText;
  }
  if (byType != null) {
    parameters['byType'] = byType;
  }
  if (byKey != null) {
    parameters['byKey'] = byKey;
  }
  if (byWidget != null) {
    parameters['byWidget'] = byWidget;
  }
  return extensions[PilotRuntimeProtocol.resolveFinderExtension]!(parameters);
}

Future<Map<String, Object?>> _tap(
  Map<String, PilotRuntimeExtensionHandler> extensions, {
  required String handle,
}) {
  return extensions[PilotRuntimeProtocol.tapExtension]!(<String, Object?>{
    'handle': handle,
  });
}

Future<Map<String, Object?>> _clearText(
  Map<String, PilotRuntimeExtensionHandler> extensions, {
  required String handle,
}) {
  return extensions[PilotRuntimeProtocol.clearTextExtension]!(<String, Object?>{
    'handle': handle,
  });
}

Future<Map<String, Object?>> _enterText(
  Map<String, PilotRuntimeExtensionHandler> extensions, {
  required String handle,
  required String text,
}) {
  return extensions[PilotRuntimeProtocol.enterTextExtension]!(<String, Object?>{
    'handle': handle,
    'text': text,
  });
}

Future<Map<String, Object?>> _scroll(
  Map<String, PilotRuntimeExtensionHandler> extensions, {
  String? handle,
  required double deltaX,
  required double deltaY,
}) {
  final Map<String, Object?> parameters = <String, Object?>{
    'deltaX': deltaX,
    'deltaY': deltaY,
  };
  if (handle != null) {
    parameters['handle'] = handle;
  }
  return extensions[PilotRuntimeProtocol.scrollExtension]!(parameters);
}

Map<String, Object?> _singleMatch(Map<String, Object?> response) {
  final Object? matchValue = (response['matches']! as List<Object?>).single;
  return matchValue! as Map<String, Object?>;
}
