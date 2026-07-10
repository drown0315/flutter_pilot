import 'package:flutter/material.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Start the scroll replay demo with the real `pilot_runtime` binding installed.
///
/// This target is intended for manual Flutter Pilot acceptance runs. It exposes
/// one targeted scrollable, one read-only non-scrollable target, and enough list
/// content for a Scenario to prove that pointer drag replay moved the list.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  runApp(const PilotRuntimeScrollDemoApp());
}

/// Demo app used to verify scroll replay through `PilotRuntimeAdapter`.
class PilotRuntimeScrollDemoApp extends StatelessWidget {
  const PilotRuntimeScrollDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pilot Runtime Scroll Demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const PilotRuntimeScrollDemoPage(),
    );
  }
}

/// Single-screen target for targeted scroll and failing scroll checks.
class PilotRuntimeScrollDemoPage extends StatelessWidget {
  const PilotRuntimeScrollDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilot Runtime Scroll Demo')),
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scroll replay acceptance',
              key: ValueKey<String>('scroll_demo_header'),
            ),
          ),
          const Text(
            'Read only scroll target',
            key: ValueKey<String>('read_only_scroll_target'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              key: const ValueKey<String>('target_scroll_list'),
              padding: const EdgeInsets.all(16),
              itemCount: 40,
              itemBuilder: (BuildContext context, int index) {
                return SizedBox(
                  height: 56,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Scroll demo row $index',
                      key: ValueKey<String>('scroll_demo_row_$index'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
