import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Fetches and prints Flutter Inspector summary Widget Tree data.
///
/// Args:
/// `--vm-service-uri` is the WebSocket URI for a running Flutter debug app.
/// `--project-root` is the Target App Package root passed to Flutter Inspector
/// pub-root filtering before fetching the tree.
///
/// Returns:
/// Exit code `0` when the Inspector tree is fetched and printed. Missing
/// arguments, VM Service failures, or unexpected Inspector response shapes exit
/// non-zero with a short error on stderr.
Future<void> main(List<String> arguments) async {
  final ProbeArguments? probeArguments = ProbeArguments.parse(arguments);
  if (probeArguments == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  VmService? service;
  try {
    service = await vmServiceConnectUri(probeArguments.vmServiceUri);
    final String isolateId = await _findMainIsolateId(service);

    stdout.writeln('Summary Tree Probe');
    stdout.writeln('vmServiceUri: ${probeArguments.vmServiceUri}');
    stdout.writeln('projectRoot: ${probeArguments.projectRoot}');
    stdout.writeln('isolateId: $isolateId');
    stdout.writeln('');

    await _callServiceExtension(
      service,
      'ext.flutter.inspector.setPubRootDirectories',
      isolateId: isolateId,
      args: <String, Object?>{'arg0': probeArguments.projectRoot},
    );

    final Map<String, Object?> response = await _callServiceExtension(
      service,
      'ext.flutter.inspector.getRootWidgetTree',
      isolateId: isolateId,
      args: <String, Object?>{
        'groupName': 'pilot_runtime_summary_tree_probe',
        'isSummaryTree': 'true',
        'withPreviews': 'true',
        'fullDetails': probeArguments.fullDetails ? 'true' : 'false',
      },
    );

    final Object? decoded = _decodeInspectorResult(response);
    if (decoded is! Map<String, Object?>) {
      stderr.writeln(
        'Expected getRootWidgetTree to return a diagnostics object, '
        'but got ${decoded.runtimeType}.',
      );
      exitCode = 1;
      return;
    }

    final DiagnosticsInventory inventory = DiagnosticsInventory.collect(
      decoded,
    );

    final String report = _renderProbeReport(
      projectRoot: probeArguments.projectRoot,
      fullDetails: probeArguments.fullDetails,
      inventory: inventory,
      decoded: decoded,
    );
    final String? outputPath = probeArguments.outputPath;
    if (outputPath == null) {
      stdout.write(report);
    } else {
      final File outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(report);
      stdout.writeln('Summary tree probe output written to $outputPath');
    }
  } catch (error, stackTrace) {
    stderr.writeln('summary_tree_probe failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await service?.dispose();
  }
}

/// Command-line values required to fetch one Inspector summary tree.
class ProbeArguments {
  const ProbeArguments({
    required this.vmServiceUri,
    required this.projectRoot,
    this.fullDetails = false,
    this.outputPath,
  });

  final String vmServiceUri;
  final String projectRoot;
  final bool fullDetails;
  final String? outputPath;

  /// Parse `--vm-service-uri` and `--project-root` from CLI arguments.
  ///
  /// Args:
  /// `arguments` is the raw argument list passed to the Dart program. Each
  /// option may be passed as `--name value` or `--name=value`.
  ///
  /// Returns:
  /// A `ProbeArguments` value when both options are present; otherwise `null`.
  static ProbeArguments? parse(List<String> arguments) {
    final Map<String, String> options = <String, String>{};
    for (int index = 0; index < arguments.length; index += 1) {
      final String argument = arguments[index];
      if (argument.startsWith('--vm-service-uri=')) {
        options['vm-service-uri'] = argument.substring(
          '--vm-service-uri='.length,
        );
        continue;
      }
      if (argument == '--vm-service-uri' && index + 1 < arguments.length) {
        index += 1;
        options['vm-service-uri'] = arguments[index];
        continue;
      }
      if (argument.startsWith('--project-root=')) {
        options['project-root'] = argument.substring('--project-root='.length);
        continue;
      }
      if (argument == '--project-root' && index + 1 < arguments.length) {
        index += 1;
        options['project-root'] = arguments[index];
        continue;
      }
      if (argument.startsWith('--output=')) {
        options['output'] = argument.substring('--output='.length);
        continue;
      }
      if (argument == '--output' && index + 1 < arguments.length) {
        index += 1;
        options['output'] = arguments[index];
        continue;
      }
      if (argument == '--full-details') {
        options['full-details'] = 'true';
        continue;
      }
      if (argument == '--help' || argument == '-h') {
        return null;
      }
    }

    final String? vmServiceUri = options['vm-service-uri'];
    final String? projectRoot = options['project-root'];
    if (vmServiceUri == null ||
        vmServiceUri.isEmpty ||
        projectRoot == null ||
        projectRoot.isEmpty) {
      return null;
    }

    return ProbeArguments(
      vmServiceUri: vmServiceUri,
      projectRoot: projectRoot,
      fullDetails: options['full-details'] == 'true',
      outputPath: options['output'],
    );
  }
}

/// Aggregated field information from a Flutter diagnostics tree.
class DiagnosticsInventory {
  DiagnosticsInventory._({
    required this.nodeCount,
    required this.fieldCounts,
    required this.valueTypeCounts,
  });

  final int nodeCount;
  final Map<String, int> fieldCounts;
  final Map<String, Map<String, int>> valueTypeCounts;

  /// Collect field names and value runtime types across diagnostics nodes.
  ///
  /// Args:
  /// `root` is the decoded diagnostics root from
  /// `ext.flutter.inspector.getRootWidgetTree`.
  ///
  /// Returns:
  /// Counts for every field that appears in a diagnostics node. Nested
  /// `children` lists are traversed recursively; other nested objects are
  /// counted by type but not treated as child nodes.
  static DiagnosticsInventory collect(Map<String, Object?> root) {
    int nodeCount = 0;
    final Map<String, int> fieldCounts = <String, int>{};
    final Map<String, Map<String, int>> valueTypeCounts =
        <String, Map<String, int>>{};

    void visit(Map<String, Object?> node) {
      nodeCount += 1;
      for (final MapEntry<String, Object?> entry in node.entries) {
        final String key = entry.key;
        final Object? value = entry.value;
        fieldCounts[key] = (fieldCounts[key] ?? 0) + 1;
        final Map<String, int> counts = valueTypeCounts.putIfAbsent(
          key,
          () => <String, int>{},
        );
        final String typeName = _valueTypeName(value);
        counts[typeName] = (counts[typeName] ?? 0) + 1;
      }

      final Object? children = node['children'];
      if (children is List<Object?>) {
        for (final Object? child in children) {
          if (child is Map<String, Object?>) {
            visit(child);
          }
        }
      }
    }

    visit(root);

    return DiagnosticsInventory._(
      nodeCount: nodeCount,
      fieldCounts: fieldCounts,
      valueTypeCounts: valueTypeCounts,
    );
  }

  /// Render a deterministic text report for the collected diagnostics fields.
  String render() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('nodes: $nodeCount');

    final List<String> fields = fieldCounts.keys.toList()..sort();
    for (final String field in fields) {
      final Map<String, int> typeCounts = valueTypeCounts[field]!;
      final List<String> typeNames = typeCounts.keys.toList()..sort();
      final String types = typeNames
          .map((String typeName) => '$typeName=${typeCounts[typeName]}')
          .join(', ');
      buffer.writeln('- $field: ${fieldCounts[field]} node(s); $types');
    }
    return buffer.toString();
  }
}

Future<String> _findMainIsolateId(VmService service) async {
  final VM vm = await service.getVM();
  final List<IsolateRef> isolates = vm.isolates ?? const <IsolateRef>[];
  for (final IsolateRef isolate in isolates) {
    final String? isolateId = isolate.id;
    if (isolateId != null) {
      return isolateId;
    }
  }
  throw StateError('No runnable Dart isolate found.');
}

String _renderProbeReport({
  required String projectRoot,
  required bool fullDetails,
  required DiagnosticsInventory inventory,
  required Map<String, Object?> decoded,
}) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('Service Extension Calls');
  buffer.writeln(
    '- ext.flutter.inspector.setPubRootDirectories '
    'args=${jsonEncode(<String, Object?>{'arg0': projectRoot})}',
  );
  buffer.writeln(
    '- ext.flutter.inspector.getRootWidgetTree '
    'args=${jsonEncode(<String, Object?>{'groupName': 'pilot_runtime_summary_tree_probe', 'isSummaryTree': 'true', 'withPreviews': 'true', 'fullDetails': fullDetails ? 'true' : 'false'})}',
  );
  buffer.writeln('');

  buffer.writeln('Field Inventory');
  buffer.write(inventory.render());
  buffer.writeln('');

  buffer.writeln('Compact Tree');
  _writeCompactTree(decoded, buffer);
  buffer.writeln('');

  buffer.writeln('Full Summary Tree JSON');
  buffer.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
  return buffer.toString();
}

Future<Map<String, Object?>> _callServiceExtension(
  VmService service,
  String method, {
  required String isolateId,
  Map<String, Object?>? args,
}) async {
  final Response response = await service.callServiceExtension(
    method,
    isolateId: isolateId,
    args: args?.cast<String, dynamic>(),
  );
  return response.json?.cast<String, Object?>() ?? <String, Object?>{};
}

Object? _decodeInspectorResult(Map<String, Object?> response) {
  final Object? result =
      response['result'] ?? response['object'] ?? response['value'];
  if (result is String) {
    return jsonDecode(result);
  }
  return result ?? response;
}

void _writeCompactTree(
  Map<String, Object?> node,
  StringSink sink, {
  int depth = 0,
}) {
  final String indent = '  ' * depth;
  final String id = node['valueId']?.toString() ?? '';
  final String description = node['description']?.toString() ?? '';
  final String location = _formatCreationLocation(node['creationLocation']);
  final String locationSuffix = location.isEmpty ? '' : ' location=$location';
  final Object? children = node['children'];
  final int childCount = children is List<Object?> ? children.length : 0;
  sink.writeln(
    '$indent- $description id=$id children=$childCount$locationSuffix',
  );

  if (children is List<Object?>) {
    for (final Object? child in children) {
      if (child is Map<String, Object?>) {
        _writeCompactTree(child, sink, depth: depth + 1);
      }
    }
  }
}

String _formatCreationLocation(Object? value) {
  if (value is! Map<String, Object?>) {
    return '';
  }
  final String file = value['file']?.toString() ?? '';
  final Object? line = value['line'];
  final Object? column = value['column'];
  if (file.isEmpty) {
    return '';
  }
  if (line == null) {
    return file;
  }
  if (column == null) {
    return '$file:$line';
  }
  return '$file:$line:$column';
}

String _valueTypeName(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is List<Object?>) {
    return 'List';
  }
  if (value is Map<String, Object?>) {
    return 'Map';
  }
  return value.runtimeType.toString();
}

void _printUsage() {
  stderr.writeln('Usage:');
  stderr.writeln('  dart run bin/summary_tree_probe.dart \\');
  stderr.writeln('    --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \\');
  stderr.writeln('    --project-root /path/to/flutter/app \\');
  stderr.writeln('    [--full-details] \\');
  stderr.writeln('    [--output out/summary-tree.txt]');
}
