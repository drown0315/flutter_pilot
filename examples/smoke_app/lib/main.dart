import 'package:flutter/material.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

/// Start the Flutter Pilot smoke app with pilot_runtime extensions enabled.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  runApp(const SmokeApp());
}

/// Minimal Flutter app used by the real `pilot_runtime` smoke Scenario.
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
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Text('Smoke form'),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Submit smoke')),
          const SizedBox(height: 24),
          if (_message != null) Text(_message!),
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
