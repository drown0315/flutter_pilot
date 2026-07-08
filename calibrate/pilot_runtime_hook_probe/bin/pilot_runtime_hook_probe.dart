import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Verifies a `pilot_runtime`-style app hook through VM Service.
///
/// Args:
/// `--vm-service-uri` is the WebSocket URI for a running Flutter debug app
/// started with `examples/smoke_app/lib/pilot_runtime_probe_app.dart`.
/// `--output` optionally writes the probe report to a file.
///
/// Returns:
/// Exit code `0` when all calibrated interactions succeed. Missing arguments,
/// VM Service failures, missing extensions, or failed interactions exit
/// non-zero and print a short error to stderr.
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
    final Isolate isolate = await _findMainIsolate(service);
    final String isolateId = isolate.id!;
    final List<String> extensionRpcs = await _waitForPilotExtensions(
      service,
      isolateId,
    );

    final List<ProbeStep> steps = <ProbeStep>[];
    final Map<String, Object?> snapshot = await _callPilotExtension(
      service,
      isolateId: isolateId,
      method: 'ext.flutter_pilot.snapshot',
    );
    steps.add(
      ProbeStep(
        name: 'snapshot',
        method: 'ext.flutter_pilot.snapshot',
        input: const <String, Object?>{},
        output: snapshot,
      ),
    );

    final Map<String, Object?> byKeyResolve = await _callPilotExtension(
      service,
      isolateId: isolateId,
      method: 'ext.flutter_pilot.resolve',
      args: <String, Object?>{'byKey': 'submit-smoke'},
    );
    steps.add(
      ProbeStep(
        name: 'resolve byKey',
        method: 'ext.flutter_pilot.resolve',
        input: const <String, Object?>{'byKey': 'submit-smoke'},
        output: byKeyResolve,
      ),
    );
    final Map<String, Object?> byKeyMatch = _singleMatch(byKeyResolve, 'byKey');

    final Map<String, Object?> byKeyTap = await _tapRef(
      service,
      isolateId: isolateId,
      ref: byKeyMatch['ref'].toString(),
    );
    steps.add(
      ProbeStep(
        name: 'tap byKey ref',
        method: 'ext.flutter_pilot.tap',
        input: <String, Object?>{'ref': byKeyMatch['ref']},
        output: byKeyTap,
      ),
    );

    final Map<String, Object?> byWidgetTypeResolve = await _callPilotExtension(
      service,
      isolateId: isolateId,
      method: 'ext.flutter_pilot.resolve',
      args: <String, Object?>{'byWidgetType': 'ProbeSubmitButton'},
    );
    steps.add(
      ProbeStep(
        name: 'resolve byWidgetType',
        method: 'ext.flutter_pilot.resolve',
        input: const <String, Object?>{'byWidgetType': 'ProbeSubmitButton'},
        output: byWidgetTypeResolve,
      ),
    );
    final Map<String, Object?> byWidgetTypeMatch = _singleMatch(
      byWidgetTypeResolve,
      'byWidgetType',
    );

    final Map<String, Object?> byWidgetTypeTap = await _tapRef(
      service,
      isolateId: isolateId,
      ref: byWidgetTypeMatch['ref'].toString(),
    );
    steps.add(
      ProbeStep(
        name: 'tap byWidgetType ref',
        method: 'ext.flutter_pilot.tap',
        input: <String, Object?>{'ref': byWidgetTypeMatch['ref']},
        output: byWidgetTypeTap,
      ),
    );

    final Map<String, Object?> byTypeResolve = await _callPilotExtension(
      service,
      isolateId: isolateId,
      method: 'ext.flutter_pilot.resolve',
      args: <String, Object?>{'byType': 'button'},
    );
    steps.add(
      ProbeStep(
        name: 'resolve semantic byType',
        method: 'ext.flutter_pilot.resolve',
        input: const <String, Object?>{'byType': 'button'},
        output: byTypeResolve,
      ),
    );
    final Map<String, Object?> byTypeMatch = _singleMatch(
      byTypeResolve,
      'byType',
    );

    final Map<String, Object?> byTypeTap = await _tapRef(
      service,
      isolateId: isolateId,
      ref: byTypeMatch['ref'].toString(),
    );
    steps.add(
      ProbeStep(
        name: 'tap semantic byType ref',
        method: 'ext.flutter_pilot.tap',
        input: <String, Object?>{'ref': byTypeMatch['ref']},
        output: byTypeTap,
      ),
    );

    final Map<String, Object?> center =
        (byKeyMatch['center'] as Map<Object?, Object?>).cast<String, Object?>();
    final Map<String, Object?> tapAtInput = <String, Object?>{
      'x': center['x'],
      'y': center['y'],
    };
    final Map<String, Object?> tapAt = await _callPilotExtension(
      service,
      isolateId: isolateId,
      method: 'ext.flutter_pilot.tapAt',
      args: tapAtInput,
    );
    steps.add(
      ProbeStep(
        name: 'tapAt logical coordinate',
        method: 'ext.flutter_pilot.tapAt',
        input: tapAtInput,
        output: tapAt,
      ),
    );

    final int finalTapCount = _stateTapCount(tapAt);
    if (finalTapCount < 4) {
      throw StateError(
        'Expected at least 4 submit taps after byKey, byWidgetType, byType, '
        'and tapAt checks, got $finalTapCount.',
      );
    }

    final String report = _renderReport(
      vmServiceUri: probeArguments.vmServiceUri,
      isolateId: isolateId,
      extensionRpcs: extensionRpcs,
      steps: steps,
    );

    final String? outputPath = probeArguments.outputPath;
    if (outputPath == null) {
      stdout.write(report);
    } else {
      final File outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(report);
      stdout.writeln('Pilot runtime hook probe output written to $outputPath');
    }
  } catch (error, stackTrace) {
    stderr.writeln('pilot_runtime_hook_probe failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await service?.dispose();
  }
}

/// Parsed command-line values for one hook probe run.
class ProbeArguments {
  const ProbeArguments({required this.vmServiceUri, this.outputPath});

  final String vmServiceUri;
  final String? outputPath;

  /// Parse `--vm-service-uri` and optional `--output`.
  ///
  /// Args:
  /// `arguments` is the raw command-line argument list. Each option can be
  /// passed as `--name value` or `--name=value`.
  ///
  /// Returns:
  /// A `ProbeArguments` value when the required VM Service URI is present;
  /// otherwise `null`.
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

    return ProbeArguments(
      vmServiceUri: vmServiceUri,
      outputPath: options['output'],
    );
  }
}

/// One VM Service extension call captured in the calibration report.
class ProbeStep {
  const ProbeStep({
    required this.name,
    required this.method,
    required this.input,
    required this.output,
  });

  final String name;
  final String method;
  final Map<String, Object?> input;
  final Map<String, Object?> output;
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

Future<List<String>> _waitForPilotExtensions(
  VmService service,
  String isolateId,
) async {
  const Set<String> requiredExtensions = <String>{
    'ext.flutter_pilot.snapshot',
    'ext.flutter_pilot.resolve',
    'ext.flutter_pilot.tap',
    'ext.flutter_pilot.tapAt',
    'ext.flutter_pilot.state',
  };

  for (int attempt = 0; attempt < 40; attempt += 1) {
    final Isolate isolate = await service.getIsolate(isolateId);
    final List<String> extensionRpcs =
        isolate.extensionRPCs ?? const <String>[];
    if (requiredExtensions.every(extensionRpcs.contains)) {
      return extensionRpcs;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  final Isolate isolate = await service.getIsolate(isolateId);
  final List<String> extensionRpcs = isolate.extensionRPCs ?? const <String>[];
  throw StateError(
    'Missing required ext.flutter_pilot service extensions. Available: '
    '${extensionRpcs.join(', ')}',
  );
}

Future<Map<String, Object?>> _callPilotExtension(
  VmService service, {
  required String isolateId,
  required String method,
  Map<String, Object?> args = const <String, Object?>{},
}) async {
  final Response response = await service.callServiceExtension(
    method,
    isolateId: isolateId,
    args: args.map(
      (String key, Object? value) =>
          MapEntry<String, dynamic>(key, value?.toString()),
    ),
  );
  final Map<String, Object?> decoded = _decodeResponse(response);
  if (decoded['ok'] == false) {
    throw StateError('$method returned failure: ${jsonEncode(decoded)}');
  }
  return decoded;
}

Future<Map<String, Object?>> _tapRef(
  VmService service, {
  required String isolateId,
  required String ref,
}) {
  return _callPilotExtension(
    service,
    isolateId: isolateId,
    method: 'ext.flutter_pilot.tap',
    args: <String, Object?>{'ref': ref},
  );
}

Map<String, Object?> _decodeResponse(Response response) {
  final Map<String, Object?> json =
      response.json?.cast<String, Object?>() ?? <String, Object?>{};
  final Object? result = json['result'] ?? json['object'] ?? json['value'];
  if (result is String) {
    return (jsonDecode(result) as Map<Object?, Object?>)
        .cast<String, Object?>();
  }
  if (result is Map<Object?, Object?>) {
    return result.cast<String, Object?>();
  }
  return json;
}

Map<String, Object?> _singleMatch(
  Map<String, Object?> response,
  String capability,
) {
  final Object? matchesValue = response['matches'];
  if (matchesValue is! List<Object?> || matchesValue.length != 1) {
    throw StateError(
      'Expected exactly one $capability match, got ${response['matchCount']}: '
      '${jsonEncode(response)}',
    );
  }
  final Object? match = matchesValue.single;
  if (match is! Map<Object?, Object?>) {
    throw StateError('Expected $capability match to be a JSON object.');
  }
  return match.cast<String, Object?>();
}

int _stateTapCount(Map<String, Object?> response) {
  final Object? state = response['state'];
  if (state is Map<Object?, Object?>) {
    final Object? count = state['submitTapCount'];
    if (count is int) {
      return count;
    }
  }
  return -1;
}

String _renderReport({
  required String vmServiceUri,
  required String isolateId,
  required List<String> extensionRpcs,
  required List<ProbeStep> steps,
}) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('Pilot Runtime Hook Probe');
  buffer.writeln('vmServiceUri: $vmServiceUri');
  buffer.writeln('isolateId: $isolateId');
  buffer.writeln('');
  buffer.writeln('Available pilot extensions');
  for (final String extension
      in extensionRpcs
          .where(
            (String extension) => extension.startsWith('ext.flutter_pilot.'),
          )
          .toList()
        ..sort()) {
    buffer.writeln('- $extension');
  }
  buffer.writeln('');

  for (final ProbeStep step in steps) {
    buffer.writeln('Step: ${step.name}');
    buffer.writeln('method: ${step.method}');
    buffer.writeln('input: ${jsonEncode(step.input)}');
    buffer.writeln('output:');
    buffer.writeln(_compactJson(step.output));
    buffer.writeln('');
  }

  return buffer.toString();
}

String _compactJson(Map<String, Object?> value) {
  final Map<String, Object?> copy = Map<String, Object?>.from(value);
  final Object? nodes = copy['nodes'];
  if (nodes is List<Object?> && nodes.length > 8) {
    copy['nodes'] = nodes.take(8).toList();
    copy['nodesTruncated'] = nodes.length - 8;
  }
  return const JsonEncoder.withIndent('  ').convert(copy);
}

void _printUsage() {
  stderr.writeln('Usage:');
  stderr.writeln('  dart run bin/pilot_runtime_hook_probe.dart \\');
  stderr.writeln('    --vm-service-uri ws://127.0.0.1:<port>/<token>/ws \\');
  stderr.writeln('    [--output out/hook-probe-macos.txt]');
}
