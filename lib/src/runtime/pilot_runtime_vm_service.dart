import 'package:pilot_runtime_client/pilot_runtime_client.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

/// Opens a VM Service client for one Runtime Target URI.
typedef PilotRuntimeVmServiceConnector =
    Future<vm_service.VmService> Function(Uri vmServiceUri);

/// VM Service caller used by `PilotRuntimeClient` in the Flutter Pilot CLI.
///
/// The caller connects lazily to the Runtime Target, selects the isolate that
/// advertises the requested service extension, and forwards service extension
/// calls with JSON-compatible arguments.
class PilotRuntimeVmServiceConnection implements PilotRuntimeVmService {
  /// Create a VM Service caller for one Runtime Target URI.
  PilotRuntimeVmServiceConnection({
    required Uri vmServiceUri,
    PilotRuntimeVmServiceConnector? connector,
  }) : _vmServiceUri = vmServiceUri,
       _connector =
           connector ??
           ((Uri uri) => vm_service_io.vmServiceConnectUri(uri.toString()));

  final Uri _vmServiceUri;
  final PilotRuntimeVmServiceConnector _connector;
  vm_service.VmService? _service;
  final Map<String, String> _isolateIdsByExtension = <String, String>{};

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String extensionName, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final vm_service.VmService service = await _connectedService();
    final String isolateId = await _selectedIsolateId(service, extensionName);
    try {
      final vm_service.Response response = await service.callServiceExtension(
        extensionName,
        isolateId: isolateId,
        args: <String, dynamic>{...parameters},
      );
      return response.toJson();
    } on vm_service.RPCError catch (error) {
      if (error.code == vm_service.RPCErrorKind.kMethodNotFound.code ||
          error.code == vm_service.RPCErrorKind.kServiceDisappeared.code) {
        throw PilotRuntimeServiceExtensionMissingException(extensionName);
      }
      rethrow;
    }
  }

  /// Close the underlying VM Service connection when one was opened.
  Future<void> dispose() async {
    await _service?.dispose();
    _service = null;
    _isolateIdsByExtension.clear();
  }

  Future<vm_service.VmService> _connectedService() async {
    final vm_service.VmService? existingService = _service;
    if (existingService != null) {
      return existingService;
    }
    final vm_service.VmService service = await _connector(_vmServiceUri);
    _service = service;
    return service;
  }

  Future<String> _selectedIsolateId(
    vm_service.VmService service,
    String extensionName,
  ) async {
    final String? existingIsolateId = _isolateIdsByExtension[extensionName];
    if (existingIsolateId != null) {
      return existingIsolateId;
    }
    final vm_service.VM vm = await service.getVM();
    bool hasRunningIsolate = false;
    for (final vm_service.IsolateRef isolate in vm.isolates ?? const []) {
      final String? isolateId = isolate.id;
      if (isolateId != null) {
        hasRunningIsolate = true;
        final vm_service.Isolate isolateDetails = await service.getIsolate(
          isolateId,
        );
        final List<String> extensionRPCs =
            isolateDetails.extensionRPCs ?? const <String>[];
        if (extensionRPCs.contains(extensionName)) {
          _isolateIdsByExtension[extensionName] = isolateId;
          return isolateId;
        }
      }
    }
    if (!hasRunningIsolate) {
      throw StateError('Runtime Target VM Service has no running isolates.');
    }
    throw PilotRuntimeServiceExtensionMissingException(extensionName);
  }
}
