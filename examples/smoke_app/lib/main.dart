import 'package:flutter/material.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

/// Start the Flutter Pilot smoke app with MCP Toolkit extensions enabled.
Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () => runApp(const SmokeApp()),
  );
}

/// Minimal Flutter app used by the real `mcp_flutter` smoke Scenario.
class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Pilot Smoke',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const SmokeHomePage(),
    );
  }
}

/// Single-screen form with stable keys and text for Runtime Adapter smoke runs.
class SmokeHomePage extends StatefulWidget {
  const SmokeHomePage({super.key});

  @override
  State<SmokeHomePage> createState() => _SmokeHomePageState();
}

class _SmokeHomePageState extends State<SmokeHomePage> {
  final TextEditingController _emailController = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Show the deterministic validation message used by the smoke Scenario.
  void _submit() {
    setState(() {
      _message = 'Smoke validation failed';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Pilot Smoke')),
      body: ListView(
        key: const ValueKey<String>('smoke_scroll'),
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Text('Smoke form'),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('email_input'),
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey<String>('submit_button'),
            onPressed: _submit,
            child: const Text('Submit smoke'),
          ),
          const SizedBox(height: 24),
          if (_message != null)
            Text(_message!, key: const ValueKey<String>('smoke_error')),
          for (int index = 0; index < 12; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Smoke row $index'),
            ),
        ],
      ),
    );
  }
}
