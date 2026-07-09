import 'package:flutter/material.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Start the tap replay demo with the real `pilot_runtime` binding installed.
///
/// This target is intended for manual Flutter Pilot acceptance runs. It keeps
/// the app UI small and exposes semantic tap, pointer fallback tap, and
/// non-tappable targets in one screen.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  runApp(const PilotRuntimeTapDemoApp());
}

/// Demo app used to verify tap replay through `PilotRuntimeAdapter`.
class PilotRuntimeTapDemoApp extends StatelessWidget {
  const PilotRuntimeTapDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pilot Runtime Tap Demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const PilotRuntimeTapDemoPage(),
    );
  }
}

/// Single-screen target for semantic, pointer fallback, and failing tap checks.
class PilotRuntimeTapDemoPage extends StatefulWidget {
  const PilotRuntimeTapDemoPage({super.key});

  @override
  State<PilotRuntimeTapDemoPage> createState() =>
      _PilotRuntimeTapDemoPageState();
}

class _PilotRuntimeTapDemoPageState extends State<PilotRuntimeTapDemoPage> {
  int _semanticTaps = 0;
  int _pointerTaps = 0;

  /// Record a tap delivered through the button's semantic tap action.
  void _recordSemanticTap() {
    setState(() {
      _semanticTaps += 1;
    });
  }

  /// Record a tap delivered by the runtime pointer-center fallback path.
  void _recordPointerTap() {
    setState(() {
      _pointerTaps += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilot Runtime Tap Demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Text('Tap replay acceptance'),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey<String>('semantic_submit_button'),
            onPressed: _recordSemanticTap,
            child: const Text('Semantic submit'),
          ),
          const SizedBox(height: 12),
          Text(
            'Semantic taps: $_semanticTaps',
            key: const ValueKey<String>('semantic_tap_count'),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            key: const ValueKey<String>('pointer_fallback_target'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _recordPointerTap,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              color: Colors.teal.shade100,
              child: const Text('Pointer fallback target'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Pointer taps: $_pointerTaps',
            key: const ValueKey<String>('pointer_tap_count'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Read only target',
            key: ValueKey<String>('read_only_target'),
          ),
          const SizedBox(height: 24),
          for (int index = 0; index < 6; index += 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Tap demo row $index'),
            ),
        ],
      ),
    );
  }
}
