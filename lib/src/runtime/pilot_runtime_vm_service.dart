import 'package:pilot_runtime/pilot_runtime.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

/// VM Service caller used by `PilotRuntimeClient` in the Flutter Pilot CLI.
///
/// The caller connects lazily to the Runtime Target, selects the first running
/// isolate, and forwards service extension calls with JSON-compatible
/// arguments.
class PilotRuntimeVmServiceConnection implements PilotRuntimeVmService {
  /// Create a VM Service caller for one Runtime Target URI.
  PilotRuntimeVmServiceConnection({required Uri vmServiceUri})
    : _vmServiceUri = vmServiceUri;

  final Uri _vmServiceUri;
  vm_service.VmService? _service;
  String? _isolateId;

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String extensionName, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final vm_service.VmService service = await _connectedService();
    final String isolateId = await _selectedIsolateId(service);
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
    _isolateId = null;
  }

  Future<vm_service.VmService> _connectedService() async {
    final vm_service.VmService? existingService = _service;
    if (existingService != null) {
      return existingService;
    }
    final vm_service.VmService service = await vm_service_io
        .vmServiceConnectUri(_vmServiceUri.toString());
    _service = service;
    return service;
  }

  Future<String> _selectedIsolateId(vm_service.VmService service) async {
    final String? existingIsolateId = _isolateId;
    if (existingIsolateId != null) {
      return existingIsolateId;
    }
    final vm_service.VM vm = await service.getVM();
    for (final vm_service.IsolateRef isolate in vm.isolates ?? const []) {
      final String? isolateId = isolate.id;
      if (isolateId != null) {
        _isolateId = isolateId;
        return isolateId;
      }
    }
    throw StateError('Runtime Target VM Service has no running isolates.');
  }
}
