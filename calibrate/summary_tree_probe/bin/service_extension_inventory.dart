import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Prints service extensions registered by a running Flutter debug app.
///
/// Args:
/// `--vm-service-uri` is the WebSocket URI for a running Flutter debug app.
/// `--output` optionally writes the extension list to a file.
///
/// Returns:
/// Exit code `0` when the isolate and extension list can be read. Missing
/// arguments or VM Service failures exit non-zero and print an error to stderr.
Future<void> main(List<String> arguments) async {
  final InventoryArguments? inventoryArguments = InventoryArguments.parse(
    arguments,
  );
  if (inventoryArguments == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  VmService? service;
  try {
    service = await vmServiceConnectUri(inventoryArguments.vmServiceUri);
    final Isolate isolate = await _findMainIsolate(service);
    final String isolateId = isolate.id!;
    final Isolate refreshed = await service.getIsolate(isolateId);
    final List<String> extensions = refreshed.extensionRPCs ?? const <String>[];
    final String report = _renderReport(
      vmServiceUri: inventoryArguments.vmServiceUri,
      isolateId: isolateId,
      extensions: extensions,
    );

    final String? outputPath = inventoryArguments.outputPath;
    if (outputPath == null) {
      stdout.write(report);
    } else {
      final File outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(report);
      stdout.writeln('Service extension inventory written to $outputPath');
    }
  } catch (error, stackTrace) {
    stderr.writeln('service_extension_inventory failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await service?.dispose();
  }
}

/// Parsed command-line values for one service extension inventory run.
class InventoryArguments {
  const InventoryArguments({required this.vmServiceUri, this.outputPath});

  final String vmServiceUri;
  final String? outputPath;

  /// Parse `--vm-service-uri` and optional `--output`.
  ///
  /// Args:
  /// `arguments` is the raw command-line argument list. Each option can be
  /// passed as `--name value` or `--name=value`.
  ///
  /// Returns:
  /// An `InventoryArguments` value when the required URI is present; otherwise
  /// `null`.
  static InventoryArguments? parse(List<String> arguments) {
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
      if (argument.startsWith('--output=')) {
        options['output'] = argument.substring('--output='.length);
        continue;
      }
      if (argument == '--output' && index + 1 < arguments.length) {
        index += 1;
        options['output'] = arguments[index];
        continue;
      }
      if (argument == '--help' || argument == '-h') {
        return null;
      }
    }

    final String? vmServiceUri = options['vm-service-uri'];
    if (vmServiceUri == null || vmServiceUri.isEmpty) {
      return null;
    }

    return InventoryArguments(
      vmServiceUri: vmServiceUri,
      outputPath: options['output'],
    );
  }
}

Future<Isolate> _findMainIsolate(VmService service) async {
  final VM vm = await service.getVM();
  final List<IsolateRef> isolates = vm.isolates ?? const <IsolateRef>[];
  for (final IsolateRef isolateRef in isolates) {
    final String? isolateId = isolateRef.id;
    if (isolateId != null) {
      return service.getIsolate(isolateId);
    }
  }
  throw StateError('No runnable Dart isolate found.');
}

String _renderReport({
  required String vmServiceUri,
  required String isolateId,
  required List<String> extensions,
}) {
  final List<String> sortedExtensions = List<String>.from(extensions)..sort();
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('Service Extension Inventory');
  buffer.writeln('vmServiceUri: $vmServiceUri');
  buffer.writeln('isolateId: $isolateId');
  buffer.writeln('extensionCount: ${sortedExtensions.length}');
  buffer.writeln('');
  for (final String extension in sortedExtensions) {
    buffer.writeln('- $extension');
  }
  return buffer.toString();
}

void _printUsage() {
  stderr.writeln('Usage:');
  stderr.writeln('  dart run bin/service_extension_inventory.dart \\');
  stderr.writeln('    --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \\');
  stderr.writeln('    [--output out/service-extensions.txt]');
}
