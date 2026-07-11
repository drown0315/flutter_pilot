import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

final Logger _log = Logger('pilot_runtime_calibration');

/// Start the replacement-calibration app with `pilot_runtime` installed.
///
/// This target is intentionally broader than the focused tap and scroll demos:
/// it exercises Finder constraints, replay actions, capture artifacts, and
/// Project Run hot restart behavior against one real debug Runtime Target.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  _configureLogging();
  _log.info('Pilot Runtime calibration app started.');
  runApp(const PilotRuntimeCalibrationApp());
}

/// Route package logging records through Flutter debug output.
///
/// Flutter Pilot captures `debugPrint` through `PilotRuntimeBinding`, so this
/// keeps the target on the public `logging` API while producing a non-empty
/// runtime Logs artifact during calibration capture.
void _configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    debugPrint('${record.level.name} ${record.loggerName}: ${record.message}');
  });
}

/// Smoke app used by the live `pilot_runtime` replacement calibration.
class PilotRuntimeCalibrationApp extends StatelessWidget {
  const PilotRuntimeCalibrationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pilot Runtime Calibration',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const PilotRuntimeCalibrationPage(),
    );
  }
}

/// Single target page that exposes stable Finder and action evidence.
class PilotRuntimeCalibrationPage extends StatefulWidget {
  const PilotRuntimeCalibrationPage({super.key});

  @override
  State<PilotRuntimeCalibrationPage> createState() =>
      _PilotRuntimeCalibrationPageState();
}

class _PilotRuntimeCalibrationPageState
    extends State<PilotRuntimeCalibrationPage> {
  final TextEditingController _emailController = TextEditingController();
  int _tapCount = 0;
  int _chipTapCount = 0;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Record a semantic button tap for the calibration Scenario.
  void _recordTap() {
    setState(() {
      _tapCount += 1;
    });
    _log.info('Calibration button tapped $_tapCount time(s).');
  }

  /// Record a custom-widget tap for the byKey plus byWidget calibration path.
  void _recordChipTap() {
    setState(() {
      _chipTapCount += 1;
    });
    _log.info('Calibration chip tapped $_chipTapCount time(s).');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilot Runtime Calibration')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Text(
            'Pilot Runtime Calibration Ready',
            key: ValueKey<String>('calibration_ready_text'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('calibration_email_field'),
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Calibration email'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey<String>('calibration_button'),
            onPressed: _recordTap,
            child: const Text('Calibration tap'),
          ),
          const SizedBox(height: 12),
          Text(
            'Calibration taps: $_tapCount',
            key: const ValueKey<String>('calibration_tap_count'),
          ),
          const SizedBox(height: 16),
          CalibrationChip(
            key: const ValueKey<String>('calibration_chip'),
            taps: _chipTapCount,
            onTap: _recordChipTap,
          ),
          const SizedBox(height: 12),
          Text(
            'Calibration chip taps: $_chipTapCount',
            key: const ValueKey<String>('calibration_chip_count'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: ListView(
              key: ValueKey<String>('calibration_target_scrollable'),
              padding: EdgeInsets.all(12),
              children: <Widget>[
                Text('Calibration nested row 0'),
                SizedBox(height: 56),
                Text('Calibration nested row 1'),
                SizedBox(height: 56),
                Text('Calibration nested row 2'),
                SizedBox(height: 56),
                Text('Calibration nested row 3'),
                SizedBox(height: 56),
                Text('Calibration nested row 4'),
                SizedBox(height: 56),
                Text('Calibration nested row 5'),
                SizedBox(height: 56),
                Text('Calibration nested row 6'),
                SizedBox(height: 56),
                Text('Calibration nested row 7'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (int index = 0; index < 28; index += 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('Calibration page row $index'),
            ),
        ],
      ),
    );
  }
}

/// Custom tap target used to calibrate exact Dart widget type matching.
class CalibrationChip extends StatelessWidget {
  const CalibrationChip({required this.taps, required this.onTap, super.key});

  /// Number of taps recorded by the parent page.
  final int taps;

  /// Callback invoked when this custom widget is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        color: Colors.teal.shade100,
        child: Text('Calibration chip target ($taps)'),
      ),
    );
  }
}
