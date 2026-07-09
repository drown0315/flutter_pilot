import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../scenario.dart';
import 'runtime_contract.dart';

/// Function that executes one `flutter-mcp-toolkit` command.
///
/// Tests can pass a fake runner. Production code uses
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
  const McpFlutterRuntimeAdapter({
    required this.target,
    this.commandRunner = defaultCommandRunner,
  });

  final RuntimeTarget target;
  final McpFlutterCommandRunner commandRunner;

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
  Future<void> replaceText(FinderMatch match, String text) async {
    await _execute(
      RuntimeOperation.replaceText,
      'enter_text',
      <String, Object?>{'ref': match.id, 'text': text},
    );
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

  /// Execute commands in order and return the first successful `data`.
  ///
  /// Args:
  /// `operation` is used for the final failure if every command fails.
  /// `calls` are tried sequentially. Each call receives the adapter connection
  /// argument before it is sent to `flutter-mcp-toolkit`.
  ///
  /// Returns:
  /// The `data` field from the first successful command response.
  ///
  /// Throws:
  /// `RuntimeOperationException` containing all command failure messages when
  /// no command succeeds.
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

  @override
  Future<SnapshotCapture> captureSnapshot() async {
    return SnapshotCapture(
      data: await _captureSemanticSnapshot(RuntimeOperation.captureSnapshot),
    );
  }

  @override
  Future<WidgetTreeCapture> captureWidgetTree() async {
    return WidgetTreeCapture(
      data: await _captureSemanticSnapshot(RuntimeOperation.captureWidgetTree),
    );
  }

  /// Capture `semantic_snapshot` data for Snapshot and widget-tree outputs.
  ///
  /// Flutter Pilot keeps separate public capture types because Scenario output
  /// still distinguishes Snapshot from widget-tree diagnostics. The current
  /// `mcp_flutter` integration uses the semantic snapshot command for both
  /// paths because `get_view_details` is not reliable enough as widget context.
  Future<Object> _captureSemanticSnapshot(RuntimeOperation operation) async {
    final Object? data = await _execute(
      operation,
      'semantic_snapshot',
      const <String, Object?>{},
    );
    return data ?? const <String, Object?>{};
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

  /// Execute one toolkit command and return its `data` field.
  Future<Object?> _execute(
    RuntimeOperation operation,
    String name,
    Map<String, Object?> arguments,
  ) async {
    final Map<String, Object?> envelope;
    try {
      envelope = await commandRunner(
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
    } on RuntimeOperationException catch (error) {
      throw RuntimeOperationException(
        operation: operation,
        message: error.message,
        cause: error.cause,
        rawOutput: error.rawOutput,
      );
    }
    if (envelope['ok'] == true) {
      return envelope['data'];
    }
    throw RuntimeOperationException(
      operation: operation,
      message: _errorMessage(envelope['error']) ?? '$name failed.',
      rawOutput: envelope,
    );
  }

  /// Return semantic snapshot nodes from known toolkit response shapes.
  List<Map<String, Object?>> _snapshotNodes(Object? data) {
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

  /// Return whether one semantic snapshot node satisfies a Finder.
  bool _matchesFinder(Map<String, Object?> node, Finder finder) {
    return _matchesOptional(finder.byText, _nodeText(node)) &&
        _matchesOptional(finder.byType, _nodeType(node)) &&
        _matchesOptional(finder.byKey, _nodeKey(node)) &&
        _matchesOptional(finder.byWidget, _nodeWidgetType(node));
  }

  /// Convert one semantic snapshot node to a Flutter Pilot Finder Match.
  FinderMatch _matchFromNode(Map<String, Object?> node) {
    return FinderMatch(
      id: _stringField(node, const <String>['ref', 'id']) ?? '',
      debugLabel: _nodeText(node) ?? _nodeType(node),
      text: _nodeText(node),
      key: _nodeKey(node),
      type: _nodeType(node),
      bounds: _boundsFromNode(node),
    );
  }

  /// Return optional bounds from a semantic snapshot node.
  WidgetBounds? _boundsFromNode(Map<String, Object?> node) {
    final Object? rect = node['rect'] ?? node['bounds'];
    if (rect is! Map<String, Object?>) {
      return null;
    }
    final num? left = _numberField(rect, 'left');
    final num? top = _numberField(rect, 'top');
    final num? width = _numberField(rect, 'width');
    final num? height = _numberField(rect, 'height');
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    return WidgetBounds(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
    );
  }

  String? _nodeText(Map<String, Object?> node) {
    return _stringField(node, const <String>['label', 'text', 'name']);
  }

  String? _nodeKey(Map<String, Object?> node) {
    return _stringField(node, const <String>['key', 'valueKey']);
  }

  /// Return the Dart widget runtime type display name when exposed by snapshot.
  String? _nodeWidgetType(Map<String, Object?> node) {
    return _stringField(node, const <String>[
      'widgetType',
      'runtimeType',
      'widget',
    ]);
  }

  /// Return the `mcp_flutter` semantic node type used by Finder `byType`.
  ///
  /// Real `semantic_snapshot` responses expose semantic types such as
  /// `textField`, `button`, `text`, and `scrollable`, not Dart widget class
  /// names such as `TextField` or `FilledButton`.
  String? _nodeType(Map<String, Object?> node) {
    return _stringField(node, const <String>['type', 'widgetType']);
  }

  bool _matchesOptional(String? expected, String? actual) {
    return expected == null || actual == expected;
  }

  String? _stringField(Map<String, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];
      if (value is String) {
        return value;
      }
    }
    return null;
  }

  num? _numberField(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    return value is num ? value : null;
  }

  String? _errorMessage(Object? error) {
    if (error is Map<String, Object?>) {
      final Object? message = error['message'];
      if (message is String) {
        return message;
      }
    }
    return null;
  }

  /// Return the first screenshot image from toolkit screenshot output.
  String? _firstScreenshotImage(Object? data) {
    if (data is! Map<String, Object?>) {
      return null;
    }
    final String? directImage = _stringField(data, const <String>[
      'image',
      'base64',
      'png',
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
    final Object? images = data['images'];
    final String? imageFromImages = _firstImageFromList(images);
    if (imageFromImages != null) {
      return imageFromImages;
    }
    return _firstImageFromList(data['screenshots']);
  }

  /// Return the first base64 image string from a toolkit image list.
  String? _firstImageFromList(Object? images) {
    if (images is! List<Object?> || images.isEmpty) {
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

  String _scrollDirection({required double deltaX, required double deltaY}) {
    if (deltaY.abs() >= deltaX.abs()) {
      return deltaY < 0 ? 'down' : 'up';
    }
    return deltaX < 0 ? 'right' : 'left';
  }

  int _scrollDistance({required double deltaX, required double deltaY}) {
    final double distance = deltaY.abs() >= deltaX.abs()
        ? deltaY.abs()
        : deltaX.abs();
    return distance.round();
  }

  /// Return the Runtime Operation that best describes a toolkit command.
  static RuntimeOperation _operationForCommand(String name) {
    return switch (name) {
      'tap_widget' => RuntimeOperation.performTap,
      'enter_text' => RuntimeOperation.replaceText,
      'scroll' => RuntimeOperation.performScroll,
      'get_screenshots' => RuntimeOperation.captureScreenshot,
      'capture_ui_snapshot' => RuntimeOperation.captureScreenshot,
      'semantic_snapshot' => RuntimeOperation.captureSnapshot,
      'get_app_errors' => RuntimeOperation.collectLogs,
      'get_extension_rpcs' => RuntimeOperation.initialize,
      _ => RuntimeOperation.initialize,
    };
  }
}
