import 'dart:io';

import 'package:pilot_runtime/pilot_runtime.dart';

import 'pilot_runtime_adapter.dart';
import 'pilot_runtime_vm_service.dart';
import 'runtime_contract.dart';

/// Selects the Runtime Adapter for a launched Runtime Target.
///
/// The default path uses `pilot_runtime`. A hidden environment switch remains
/// available for explicit runtime selection without adding public CLI flags.
class RuntimeAdapterSelector {
  RuntimeAdapterSelector._();

  /// Environment variable that selects a non-default runtime adapter.
  static const String environmentKey = 'FLUTTER_PILOT_RUNTIME';

  /// Return the Runtime Adapter selected by the hidden environment switch.
  ///
  /// Args:
  /// `target` is the launched Runtime Target passed to the adapter.
  /// `environment` defaults to `Platform.environment`; tests pass explicit
  /// maps so selection can be verified without changing process state.
  static RuntimeAdapter select({
    required RuntimeTarget target,
    Map<String, String>? environment,
    String? projectRoot,
  }) {
    final Map<String, String> effectiveEnvironment =
        environment ?? Platform.environment;
    final String runtime = effectiveEnvironment[environmentKey] ?? '';
    if (runtime.isEmpty || runtime == 'pilot_runtime') {
      final PilotRuntimeVmServiceConnection vmService =
          PilotRuntimeVmServiceConnection(vmServiceUri: target.vmServiceUri);
      return PilotRuntimeAdapter(
        client: PilotRuntimeClient(vmService),
        projectRoot: projectRoot ?? Directory.current.path,
        targetDeviceId: target.deviceId,
        disposeClient: vmService.dispose,
      );
    }
    throw RuntimeAdapterSelectionException(
      'Invalid $environmentKey value "$runtime". '
      'Expected "pilot_runtime".',
    );
  }
}

/// Failure raised when the hidden Runtime Adapter switch is invalid.
class RuntimeAdapterSelectionException implements Exception {
  /// Create a selection failure with a user-facing message.
  const RuntimeAdapterSelectionException(this.message);

  /// Human-readable explanation of the invalid switch value.
  final String message;

  @override
  String toString() => message;
}
