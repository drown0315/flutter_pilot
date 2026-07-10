import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Starts a calibration app with Flutter Pilot service extensions installed.
///
/// This target is not the production smoke app. It exists so runtime research
/// can verify a `pilot_runtime`-style app hook against a real Flutter debug
/// Runtime Target with an app-side probe binding.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeProbeHook.instance.register();
  runApp(const PilotRuntimeProbeApp());
}

/// Minimal probe UI with stable keys, widget types, and semantic roles.
class PilotRuntimeProbeApp extends StatelessWidget {
  const PilotRuntimeProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pilot Runtime Probe',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const PilotRuntimeProbeHome(),
    );
  }
}

/// Single-screen page used by the service-extension calibration probe.
class PilotRuntimeProbeHome extends StatelessWidget {
  const PilotRuntimeProbeHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilot Runtime Probe')),
      body: ListView(
        key: const ValueKey<String>('probe-scrollable'),
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Text('Probe form'),
          const SizedBox(height: 16),
          const TextField(
            key: ValueKey<String>('probe-email-field'),
            decoration: InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          const ProbeSubmitButton(key: ValueKey<String>('submit-smoke')),
          const SizedBox(height: 16),
          ValueListenableBuilder<int>(
            valueListenable: PilotRuntimeProbeHook.instance.submitTapCount,
            builder: (BuildContext context, int count, Widget? child) {
              return Text(
                'Submit taps: $count',
                key: const ValueKey<String>('tap-count-text'),
              );
            },
          ),
          for (int index = 0; index < 8; index += 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Probe row $index'),
            ),
        ],
      ),
    );
  }
}

/// App-authored widget type used to verify Dart widget runtime type matching.
class ProbeSubmitButton extends StatelessWidget {
  const ProbeSubmitButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: PilotRuntimeProbeHook.instance.recordSubmitTap,
      child: const Text('Submit smoke'),
    );
  }
}

/// Calibration-only app hook that mimics the shape of a future `pilot_runtime`.
///
/// The hook registers VM service extensions that can:
/// - return a snapshot of visible widgets
/// - resolve a Finder-like query to one or more opaque refs
/// - tap a ref by its logical center
/// - tap an explicit logical coordinate
class PilotRuntimeProbeHook {
  PilotRuntimeProbeHook._();

  static final PilotRuntimeProbeHook instance = PilotRuntimeProbeHook._();

  final ValueNotifier<int> submitTapCount = ValueNotifier<int>(0);

  bool _registered = false;
  int _snapshotSerial = 0;
  int _nextPointer = 1;
  Map<String, _ProbeNode> _nodesByRef = <String, _ProbeNode>{};

  /// Register `ext.flutter_pilot.*` service extensions for this isolate.
  void register() {
    if (_registered) {
      return;
    }
    _registered = true;

    developer.registerExtension('ext.flutter_pilot.snapshot', (
      String method,
      Map<String, String> parameters,
    ) async {
      return _jsonResponse(await _snapshotResult());
    });
    developer.registerExtension('ext.flutter_pilot.resolve', (
      String method,
      Map<String, String> parameters,
    ) async {
      return _jsonResponse(await _resolve(parameters));
    });
    developer.registerExtension('ext.flutter_pilot.tap', (
      String method,
      Map<String, String> parameters,
    ) async {
      return _jsonResponse(await _tap(parameters));
    });
    developer.registerExtension('ext.flutter_pilot.tapAt', (
      String method,
      Map<String, String> parameters,
    ) async {
      return _jsonResponse(await _tapAt(parameters));
    });
    developer.registerExtension('ext.flutter_pilot.state', (
      String method,
      Map<String, String> parameters,
    ) async {
      return _jsonResponse(_state());
    });
  }

  /// Increment the visible tap counter after a button press.
  void recordSubmitTap() {
    submitTapCount.value += 1;
  }

  Future<Map<String, Object?>> _snapshotResult() async {
    final List<_ProbeNode> nodes = _collectNodes();
    _nodesByRef = <String, _ProbeNode>{
      for (final _ProbeNode node in nodes) node.ref: node,
    };

    return <String, Object?>{
      'ok': true,
      'snapshotId': _snapshotSerial,
      'coordinateSpace': 'flutterLogicalGlobal',
      'nodeCount': nodes.length,
      'nodes': nodes.map((_ProbeNode node) => node.toJson()).toList(),
      'state': _state(),
    };
  }

  Future<Map<String, Object?>> _resolve(Map<String, String> parameters) async {
    final List<_ProbeNode> nodes = _collectNodes();
    _nodesByRef = <String, _ProbeNode>{
      for (final _ProbeNode node in nodes) node.ref: node,
    };

    final List<_ProbeNode> matches = nodes
        .where((_ProbeNode node) => _matches(node, parameters))
        .toList(growable: false);

    return <String, Object?>{
      'ok': true,
      'snapshotId': _snapshotSerial,
      'input': parameters,
      'matchCount': matches.length,
      'matches': matches.map((_ProbeNode node) => node.toJson()).toList(),
      'state': _state(),
    };
  }

  Future<Map<String, Object?>> _tap(Map<String, String> parameters) async {
    final String? ref = parameters['ref'];
    if (ref == null || ref.isEmpty) {
      return _error('missingRef', 'tap requires a ref parameter.');
    }

    final _ProbeNode? node = _nodesByRef[ref];
    if (node == null) {
      return _error('unknownRef', 'No node is cached for ref $ref.');
    }

    await _sendTap(node.center);
    return <String, Object?>{
      'ok': true,
      'input': parameters,
      'tappedRef': ref,
      'coordinateSpace': 'flutterLogicalGlobal',
      'tapPosition': _offsetJson(node.center),
      'state': _state(),
    };
  }

  Future<Map<String, Object?>> _tapAt(Map<String, String> parameters) async {
    final double? x = double.tryParse(parameters['x'] ?? '');
    final double? y = double.tryParse(parameters['y'] ?? '');
    if (x == null || y == null) {
      return _error('invalidCoordinate', 'tapAt requires numeric x and y.');
    }

    final Offset position = Offset(x, y);
    await _sendTap(position);
    return <String, Object?>{
      'ok': true,
      'input': parameters,
      'coordinateSpace': 'flutterLogicalGlobal',
      'tapPosition': _offsetJson(position),
      'state': _state(),
    };
  }

  List<_ProbeNode> _collectNodes() {
    _snapshotSerial += 1;
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return const <_ProbeNode>[];
    }

    final List<_ProbeNode> nodes = <_ProbeNode>[];
    int index = 0;

    void visit(Element element, int depth) {
      final Widget widget = element.widget;
      final RenderBox? renderBox = _findRenderBox(element);
      final Rect? bounds = _globalBounds(renderBox);
      final Map<String, Object?>? key = _keyJson(widget.key);
      final String? text = _textFor(widget);
      final String? semanticType = _semanticTypeFor(widget);

      if (bounds != null) {
        final String ref = 'p_${_snapshotSerial}_${index++}';
        nodes.add(
          _ProbeNode(
            ref: ref,
            widgetType: widget.runtimeType.toString(),
            semanticType: semanticType,
            key: key,
            text: text,
            bounds: bounds,
            depth: depth,
          ),
        );
      }

      element.visitChildElements((Element child) => visit(child, depth + 1));
    }

    visit(root, 0);
    return nodes;
  }

  bool _matches(_ProbeNode node, Map<String, String> parameters) {
    final String? byKey = parameters['byKey'];
    if (byKey != null && node.keyValue != byKey) {
      return false;
    }

    final String? byWidgetType =
        parameters['byWidgetType'] ?? parameters['byWidget'];
    if (byWidgetType != null && node.widgetType != byWidgetType) {
      return false;
    }

    final String? byType = parameters['byType'];
    if (byType != null && node.semanticType != byType) {
      return false;
    }

    final String? byText = parameters['byText'];
    if (byText != null && node.text != byText) {
      return false;
    }

    return parameters.keys.any(
      (String key) => <String>{
        'byKey',
        'byWidgetType',
        'byWidget',
        'byType',
        'byText',
      }.contains(key),
    );
  }

  Future<void> _sendTap(Offset position) async {
    final int pointer = _nextPointer++;
    final Duration timeStamp = Duration(
      microseconds: DateTime.now().microsecondsSinceEpoch,
    );

    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: position,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
        timeStamp: timeStamp,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        position: position,
        kind: PointerDeviceKind.mouse,
        timeStamp: timeStamp + const Duration(milliseconds: 20),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Map<String, Object?> _state() {
    return <String, Object?>{'submitTapCount': submitTapCount.value};
  }

  developer.ServiceExtensionResponse _jsonResponse(
    Map<String, Object?> payload,
  ) {
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  }

  Map<String, Object?> _error(String code, String message) {
    return <String, Object?>{
      'ok': false,
      'error': <String, Object?>{'code': code, 'message': message},
      'state': _state(),
    };
  }

  RenderBox? _findRenderBox(Element element) {
    final RenderObject? renderObject = element.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      return renderObject;
    }

    RenderBox? found;
    element.visitChildElements((Element child) {
      found ??= _findRenderBox(child);
    });
    return found;
  }

  Rect? _globalBounds(RenderBox? renderBox) {
    if (renderBox == null || !renderBox.hasSize) {
      return null;
    }
    final Offset topLeft = renderBox.localToGlobal(Offset.zero);
    return topLeft & renderBox.size;
  }

  Map<String, Object?>? _keyJson(Key? key) {
    if (key is ValueKey<Object?>) {
      final Object? value = key.value;
      return <String, Object?>{
        'kind': 'ValueKey',
        'value': value?.toString(),
        'valueType': value.runtimeType.toString(),
      };
    }
    return null;
  }

  String? _textFor(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is TextField) {
      return widget.decoration?.labelText;
    }
    return null;
  }

  String? _semanticTypeFor(Widget widget) {
    if (widget is ButtonStyleButton) {
      return 'button';
    }
    if (widget is TextField || widget is EditableText) {
      return 'textField';
    }
    if (widget is Text) {
      return 'text';
    }
    if (widget is Scrollable || widget is ListView) {
      return 'scrollable';
    }
    if (widget is AppBar) {
      return 'header';
    }
    return null;
  }
}

/// Snapshot node used by the calibration service extensions.
class _ProbeNode {
  const _ProbeNode({
    required this.ref,
    required this.widgetType,
    required this.bounds,
    required this.depth,
    this.semanticType,
    this.key,
    this.text,
  });

  final String ref;
  final String widgetType;
  final String? semanticType;
  final Map<String, Object?>? key;
  final String? text;
  final Rect bounds;
  final int depth;

  Offset get center => bounds.center;

  String? get keyValue => key?['value']?.toString();

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ref': ref,
      'widgetType': widgetType,
      if (semanticType != null) 'semanticType': semanticType,
      if (key != null) 'key': key,
      if (text != null) 'text': text,
      'depth': depth,
      'bounds': _rectJson(bounds),
      'center': _offsetJson(center),
    };
  }
}

Map<String, Object?> _rectJson(Rect rect) {
  return <String, Object?>{
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'right': rect.right,
    'bottom': rect.bottom,
  };
}

Map<String, Object?> _offsetJson(Offset offset) {
  return <String, Object?>{'x': offset.dx, 'y': offset.dy};
}
