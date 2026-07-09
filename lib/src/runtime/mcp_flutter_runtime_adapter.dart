import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../scenario.dart';
import 'runtime_contract.dart';

/// Function that executes one `flutter-mcp-toolkit` command.
///
/// Tests pass a fake runner. Production code uses
/// `McpFlutterRuntimeAdapter.defaultCommandRunner` to call the installed CLI.
typedef McpFlutterCommandRunner =
    Future<Map<String, Object?>> Function(McpFlutterCommandCall call);

/// Command request sent to `flutter-mcp-toolkit`.
///
/// It contains the command name and JSON-compatible arguments passed to
/// `flutter-mcp-toolkit exec --name <name> --args <json>`.
class McpFlutterCommandCall {
  const McpFlutterCommandCall({required this.name, required this.arguments});

  final String name;
  final Map<String, Object?> arguments;
}

/// Runtime Adapter backed by the `flutter-mcp-toolkit` CLI.
///
/// The adapter keeps `flutter-mcp-toolkit` response shapes behind the
/// Flutter Pilot Runtime Adapter contract. It always passes the configured VM
/// service URI through the command `connection` argument.
class McpFlutterRuntimeAdapter implements RuntimeAdapter {
  McpFlutterRuntimeAdapter({
    required this.target,
    this.commandRunner = defaultCommandRunner,
  });

  final RuntimeTarget target;
  final McpFlutterCommandRunner commandRunner;
  final Map<String, String> _enteredTextByHandle = <String, String>{};

  /// Execute a `flutter-mcp-toolkit` command through the installed CLI.
  ///
  /// Args:
  /// `call` contains the command name and JSON-compatible arguments.
  ///
  /// Returns:
  /// The decoded JSON response envelope.
  ///
  /// Throws:
  /// `RuntimeOperationException` when the process fails or prints invalid JSON.
  static Future<Map<String, Object?>> defaultCommandRunner(
    McpFlutterCommandCall call,
  ) async {
    final ProcessResult result = await Process.run('flutter-mcp-toolkit', [
      'exec',
      '--name',
      call.name,
      '--args',
      jsonEncode(call.arguments),
    ]);
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on FormatException catch (error) {
      if (result.exitCode != 0) {
        throw RuntimeOperationException(
          operation: _operationForCommand(call.name),
          message: 'flutter-mcp-toolkit command failed: ${call.name}.',
          cause: error,
          rawOutput: <String, Object?>{
            'stdout': result.stdout.toString(),
            'stderr': result.stderr.toString(),
            'exitCode': result.exitCode,
          },
        );
      }
      throw RuntimeOperationException(
        operation: _operationForCommand(call.name),
        message: 'flutter-mcp-toolkit returned invalid JSON.',
        cause: error,
        rawOutput: result.stdout.toString(),
      );
    }
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    throw RuntimeOperationException(
      operation: _operationForCommand(call.name),
      message: 'flutter-mcp-toolkit returned a non-object JSON response.',
      rawOutput: decoded,
    );
  }

  @override
  Future<void> initialize() async {
    await _execute(
      RuntimeOperation.initialize,
      'get_extension_rpcs',
      const <String, Object?>{},
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<List<FinderMatch>> resolveFinder(Finder finder) async {
    final Object? data = await _execute(
      RuntimeOperation.resolveFinder,
      'semantic_snapshot',
      const <String, Object?>{},
    );
    final List<Map<String, Object?>> nodes = _snapshotNodes(data);
    return <FinderMatch>[
      for (final Map<String, Object?> node in nodes)
        if (_matchesFinder(node, finder)) _matchFromNode(node),
    ];
  }

  @override
  Future<void> performTap(FinderMatch match) async {
    await _execute(RuntimeOperation.performTap, 'tap_widget', <String, Object?>{
      'ref': match.id,
    });
  }

  @override
  Future<void> clearText(FinderMatch match) async {
    _enteredTextByHandle[match.id] = '';
    await _execute(RuntimeOperation.clearText, 'enter_text', <String, Object?>{
      'ref': match.id,
      'text': '',
    });
  }

  @override
  Future<void> enterText(FinderMatch match, String text) async {
    final String nextText = (_enteredTextByHandle[match.id] ?? '') + text;
    _enteredTextByHandle[match.id] = nextText;
    await _execute(RuntimeOperation.enterText, 'enter_text', <String, Object?>{
      'ref': match.id,
      'text': nextText,
    });
  }

  @override
  Future<void> performScroll({
    FinderMatch? match,
    required double deltaX,
    required double deltaY,
  }) async {
    await _execute(RuntimeOperation.performScroll, 'scroll', <String, Object?>{
      'direction': _scrollDirection(deltaX: deltaX, deltaY: deltaY),
      'distance': _scrollDistance(deltaX: deltaX, deltaY: deltaY),
      if (match != null) 'ref': match.id,
    });
  }

  @override
  Future<ScreenshotCapture> captureScreenshot() async {
    final Object? data = await _executeFirstSuccessful(
      RuntimeOperation.captureScreenshot,
      <McpFlutterCommandCall>[
        const McpFlutterCommandCall(
          name: 'get_screenshots',
          arguments: <String, Object?>{
            'permissionPolicy': 'auto_request_once',
            'mode': 'auto',
          },
        ),
        const McpFlutterCommandCall(
          name: 'get_screenshots',
          arguments: <String, Object?>{
            'permissionPolicy': 'auto_request_once',
            'mode': 'flutter_layer',
          },
        ),
        const McpFlutterCommandCall(
          name: 'capture_ui_snapshot',
          arguments: <String, Object?>{
            'screenshotMode': 'flutter_layer',
            'permissionPolicy': 'auto_request_once',
            'includeViewDetails': false,
            'includeErrors': false,
          },
        ),
      ],
    );
    final String? base64Image = _firstScreenshotImage(data);
    if (base64Image == null) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.captureScreenshot,
        message: 'flutter-mcp-toolkit returned no screenshot images.',
        rawOutput: data,
      );
    }
    return ScreenshotCapture(
      bytes: Uint8List.fromList(base64Decode(base64Image)),
      mimeType: 'image/png',
    );
  }

  @override
  Future<SnapshotCapture> captureSnapshot() async {
    return SnapshotCapture(
      data: await _captureSemanticSnapshot(RuntimeOperation.captureSnapshot),
    );
  }

  @override
  Future<WidgetTreeCapture> captureWidgetTree() async {
    try {
      return WidgetTreeCapture(
        data: await _captureSemanticSnapshot(
          RuntimeOperation.captureWidgetTree,
        ),
      );
    } on RuntimeOperationException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.captureWidgetTree,
        message: error.message,
        cause: error.cause,
        rawOutput: error.rawOutput,
      );
    }
  }

  @override
  Future<LogsCapture> collectLogs() async {
    final Object? data = await _execute(
      RuntimeOperation.collectLogs,
      'get_app_errors',
      const <String, Object?>{},
    );
    return LogsCapture(data: data ?? const <String, Object?>{});
  }

  Future<Object?> _executeFirstSuccessful(
    RuntimeOperation operation,
    List<McpFlutterCommandCall> calls,
  ) async {
    final List<String> failures = <String>[];
    for (final McpFlutterCommandCall call in calls) {
      try {
        return await _execute(operation, call.name, call.arguments);
      } on RuntimeOperationException catch (error) {
        failures.add('${call.name}: ${error.message}');
      }
    }
    throw RuntimeOperationException(
      operation: operation,
      message: failures.join('; '),
    );
  }

  Future<Object> _captureSemanticSnapshot(RuntimeOperation operation) async {
    final Object? data = await _execute(
      operation,
      'semantic_snapshot',
      const <String, Object?>{},
    );
    return data ?? const <String, Object?>{};
  }

  Future<Object?> _execute(
    RuntimeOperation operation,
    String name,
    Map<String, Object?> arguments,
  ) async {
    final Map<String, Object?> response = await commandRunner(
      McpFlutterCommandCall(
        name: name,
        arguments: <String, Object?>{
          ...arguments,
          'connection': <String, Object?>{
            'mode': 'uri',
            'uri': target.vmServiceUri.toString(),
          },
        },
      ),
    );
    final Object? ok = response['ok'];
    if (ok != true) {
      throw RuntimeOperationException(
        operation: operation,
        message:
            _errorMessage(response) ?? 'flutter-mcp-toolkit command failed.',
        rawOutput: response,
      );
    }
    return response['data'];
  }

  static String? _errorMessage(Map<String, Object?> response) {
    final Object? error = response['error'];
    if (error is Map<String, Object?>) {
      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  static List<Map<String, Object?>> _snapshotNodes(Object? data) {
    if (data is! Map<String, Object?>) {
      return const <Map<String, Object?>>[];
    }
    final Object? nodes = data['nodes'] ?? data['widgets'] ?? data['items'];
    if (nodes is! List<Object?>) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      for (final Object? node in nodes)
        if (node is Map<String, Object?>) node,
    ];
  }

  static bool _matchesFinder(Map<String, Object?> node, Finder finder) {
    return _matchesString(_nodeText(node), finder.byText) &&
        _matchesString(_nodeType(node), finder.byType) &&
        _matchesString(_nodeKey(node), finder.byKey) &&
        _matchesString(_nodeWidgetType(node), finder.byWidget);
  }

  static bool _matchesString(Object? actual, String? expected) {
    return expected == null || actual == expected;
  }

  static FinderMatch _matchFromNode(Map<String, Object?> node) {
    return FinderMatch(
      id: _stringField(node, const <String>['ref', 'id']) ?? '',
      debugLabel: _nodeText(node) ?? _nodeType(node),
      text: _nodeText(node),
      key: _nodeKey(node),
      type: _nodeType(node),
      bounds: _boundsFromNode(node),
    );
  }

  static WidgetBounds? _boundsFromNode(Object? value) {
    if (value is Map<String, Object?>) {
      value = value['rect'] ?? value['bounds'];
    }
    if (value is! Map<String, Object?>) {
      return null;
    }
    final double? left = _numberToDouble(value['left']);
    final double? top = _numberToDouble(value['top']);
    final double? width = _numberToDouble(value['width']);
    final double? height = _numberToDouble(value['height']);
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    return WidgetBounds(left: left, top: top, width: width, height: height);
  }

  static double? _numberToDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    return null;
  }

  static String? _nodeText(Map<String, Object?> node) {
    return _stringField(node, const <String>['label', 'text', 'name']);
  }

  static String? _nodeKey(Map<String, Object?> node) {
    return _stringField(node, const <String>['key', 'valueKey']);
  }

  static String? _nodeWidgetType(Map<String, Object?> node) {
    return _stringField(node, const <String>[
      'widgetType',
      'runtimeType',
      'widget',
    ]);
  }

  static String? _nodeType(Map<String, Object?> node) {
    return _stringField(node, const <String>['type', 'widgetType']);
  }

  static String? _stringField(Map<String, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];
      if (value is String) {
        return value;
      }
    }
    return null;
  }

  static String _scrollDirection({
    required double deltaX,
    required double deltaY,
  }) {
    if (deltaY.abs() >= deltaX.abs()) {
      return deltaY < 0 ? 'down' : 'up';
    }
    return deltaX < 0 ? 'right' : 'left';
  }

  static double _scrollDistance({
    required double deltaX,
    required double deltaY,
  }) {
    return deltaY.abs() >= deltaX.abs() ? deltaY.abs() : deltaX.abs();
  }

  static String? _firstScreenshotImage(Object? data) {
    if (data is! Map<String, Object?>) {
      return null;
    }
    final String? directImage = _stringField(data, const <String>[
      'image',
      'base64',
      'png',
      'screenshot',
    ]);
    if (directImage != null) {
      return directImage;
    }
    final Object? screenshot = data['screenshot'];
    if (screenshot is Map<String, Object?>) {
      final String? screenshotImage = _firstScreenshotImage(screenshot);
      if (screenshotImage != null) {
        return screenshotImage;
      }
    }
    final String? imageFromImages = _firstImageFromList(data['images']);
    if (imageFromImages != null) {
      return imageFromImages;
    }
    return _firstImageFromList(data['screenshots']);
  }

  static String? _firstImageFromList(Object? images) {
    if (images is! List<Object?>) {
      return null;
    }
    for (final Object? image in images) {
      if (image is String) {
        return image;
      }
      if (image is Map<String, Object?>) {
        final String? nestedImage = _firstScreenshotImage(image);
        if (nestedImage != null) {
          return nestedImage;
        }
      }
    }
    return null;
  }
}

RuntimeOperation _operationForCommand(String command) {
  return switch (command) {
    'semantic_snapshot' => RuntimeOperation.captureSnapshot,
    'tap_widget' => RuntimeOperation.performTap,
    'enter_text' => RuntimeOperation.enterText,
    'scroll' => RuntimeOperation.performScroll,
    'get_screenshots' ||
    'capture_ui_snapshot' => RuntimeOperation.captureScreenshot,
    'get_app_errors' => RuntimeOperation.collectLogs,
    'get_extension_rpcs' => RuntimeOperation.initialize,
    _ => RuntimeOperation.initialize,
  };
}
