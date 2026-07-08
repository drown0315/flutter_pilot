import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies hidden Runtime Adapter selection without launching a Flutter app.
void main() {
  test('uses mcp_flutter adapter when hidden runtime switch is omitted', () {
    final RuntimeAdapter adapter = RuntimeAdapterSelector.select(
      target: RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      ),
      environment: const <String, String>{},
    );

    expect(adapter, isA<McpFlutterRuntimeAdapter>());
  });

  test('uses PilotRuntimeAdapter when hidden runtime switch selects it', () {
    final RuntimeAdapter adapter = RuntimeAdapterSelector.select(
      target: RuntimeTarget(
        vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
      ),
      environment: const <String, String>{
        RuntimeAdapterSelector.environmentKey: 'pilot_runtime',
      },
    );

    expect(adapter, isA<PilotRuntimeAdapter>());
  });

  test('rejects invalid hidden runtime switch values clearly', () {
    expect(
      () => RuntimeAdapterSelector.select(
        target: RuntimeTarget(
          vmServiceUri: Uri.parse('ws://127.0.0.1:1234/example=/ws'),
        ),
        environment: const <String, String>{
          RuntimeAdapterSelector.environmentKey: 'other_runtime',
        },
      ),
      throwsA(
        isA<RuntimeAdapterSelectionException>().having(
          (RuntimeAdapterSelectionException error) => error.message,
          'message',
          contains('FLUTTER_PILOT_RUNTIME'),
        ),
      ),
    );
  });
}
