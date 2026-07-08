import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:pilot_runtime/pilot_runtime_client.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

/// Verifies isolate selection for the VM Service-backed pilot runtime caller.
void main() {
  test('calls extension on isolate that advertises it', () async {
    final _FakeVmService service = _FakeVmService(
      isolates: const <_HarnessIsolate>[
        _HarnessIsolate(id: 'background', extensionRPCs: <String>[]),
        _HarnessIsolate(
          id: 'app',
          extensionRPCs: <String>[PilotRuntimeProtocol.handshakeExtension],
        ),
      ],
    );
    final PilotRuntimeVmServiceConnection connection =
        PilotRuntimeVmServiceConnection(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
          connector: (_) async => service,
        );

    final Map<String, Object?> response = await connection.callServiceExtension(
      PilotRuntimeProtocol.handshakeExtension,
    );

    expect(response['isolateId'], 'app');
    expect(service.getIsolateIds, <String>['background', 'app']);

    await connection.dispose();
  });
}

class _HarnessIsolate {
  const _HarnessIsolate({required this.id, required this.extensionRPCs});

  final String id;
  final List<String> extensionRPCs;
}

class _FakeVmService extends vm_service.VmService {
  _FakeVmService({required List<_HarnessIsolate> isolates})
    : _isolates = isolates,
      super(const Stream<String>.empty(), (_) {});

  final List<_HarnessIsolate> _isolates;
  final List<String> getIsolateIds = <String>[];

  @override
  Future<vm_service.VM> getVM() async {
    return vm_service.VM(
      isolates: <vm_service.IsolateRef>[
        for (final _HarnessIsolate isolate in _isolates)
          vm_service.IsolateRef(id: isolate.id),
      ],
    );
  }

  @override
  Future<vm_service.Isolate> getIsolate(String isolateId) async {
    getIsolateIds.add(isolateId);
    final _HarnessIsolate isolate = _isolates.singleWhere(
      (_HarnessIsolate isolate) => isolate.id == isolateId,
    );
    return vm_service.Isolate(
      id: isolate.id,
      extensionRPCs: isolate.extensionRPCs,
    );
  }

  @override
  Future<vm_service.Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    return vm_service.Response.parse(<String, Object?>{
      'type': 'Response',
      'isolateId': isolateId,
    })!;
  }
}
