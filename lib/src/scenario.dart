/// Base type for all actions that a Scenario step can perform.
///
/// Each concrete subclass represents one YAML action key. A `ScenarioStep`
/// contains exactly one `StepAction`.
///
/// Example:
/// A YAML step with `tap:` becomes `TapAction`.
sealed class StepAction {
  const StepAction();
}

/// Typed representation of one Scenario YAML file.
///
/// It contains:
/// - a stable Scenario name
/// - an optional human description
/// - ordered steps to replay against a Flutter app
///
/// Example:
/// `Scenario(name: 'login_error', steps: [...])`
class Scenario {
  const Scenario({required this.name, this.description, required this.steps});

  final String name;
  final String? description;
  final List<ScenarioStep> steps;

  /// Return a Scenario that includes steps through `stepNumber`.
  ///
  /// Args:
  /// `stepNumber` is the 1-based stop point accepted by CLI `--until`.
  ///
  /// Returns:
  /// A Scenario with the same metadata and only the steps that should execute.
  ///
  /// Throws:
  /// `RangeError` when `stepNumber` is outside the Scenario step range.
  Scenario sliceThroughStepNumber(int stepNumber) {
    RangeError.checkValueInInterval(stepNumber, 1, steps.length, 'stepNumber');
    return Scenario(
      name: name,
      description: description,
      steps: steps.take(stepNumber).toList(growable: false),
    );
  }

  /// Return a Scenario that includes steps through the Step named `label`.
  ///
  /// Args:
  /// `label` is an already-validated Step label accepted by CLI `--until`.
  ///
  /// Returns:
  /// A Scenario with the same metadata and only the steps that should execute.
  ///
  /// Throws:
  /// `ArgumentError` when no Step has `label`.
  Scenario sliceThroughStepLabel(String label) {
    final int stepIndex = steps.indexWhere(
      (ScenarioStep step) => step.label == label,
    );
    if (stepIndex == -1) {
      throw ArgumentError.value(label, 'label', 'No Step has this label.');
    }
    return sliceThroughStepNumber(stepIndex + 1);
  }
}

/// One ordered Scenario step.
///
/// It contains:
/// - `index`: the 1-based step number used by `--until`
/// - `label`: an optional unique slug for named stopping points
/// - `action`: the single action to execute for this step
///
/// Example:
/// `ScenarioStep(index: 1, label: 'submit_login', action: TapAction(...))`
class ScenarioStep {
  const ScenarioStep({required this.index, this.label, required this.action});

  final int index;
  final String? label;
  final StepAction action;
}

/// Rule set for finding widgets before an action runs.
///
/// It can contain any combination of:
/// - `byText`: exact visible text
/// - `byType`: semantic Snapshot node type from `mcp_flutter`
///
/// Example:
/// `Finder(byText: 'Log in', byType: 'button')` means both rules must match.
class Finder {
  const Finder({this.byText, this.byType});

  final String? byText;
  final String? byType;

  bool get isEmpty => byText == null && byType == null;
}

/// Tap action targeting exactly one widget matched by its Finder.
class TapAction extends StepAction {
  const TapAction({required this.finder});

  final Finder finder;
}

/// Text-entry action that replaces the target widget's existing text.
class TypeAction extends StepAction {
  const TypeAction({required this.finder, required this.text});

  final Finder finder;
  final String text;
}

/// Drag gesture action using Flutter gesture delta semantics.
///
/// `finder` is optional. When absent, the future runner should use the primary
/// scrollable. `deltaX` and `deltaY` describe the drag movement, so
/// `deltaY: -500` means drag upward.
class ScrollAction extends StepAction {
  const ScrollAction({this.finder, required this.deltaX, required this.deltaY});

  final Finder? finder;
  final double deltaX;
  final double deltaY;
}

/// Wait action that succeeds when its Finder has one unique match.
class WaitForAction extends StepAction {
  const WaitForAction({required this.finder, required this.timeoutMs});

  final Finder finder;
  final int timeoutMs;
}

/// Diagnostic capture action.
///
/// Each boolean controls one artifact family:
/// - `screenshot`: visual image artifact
/// - `snapshot`: structured UI state for programs and agents
/// - `widgetTree`: raw Flutter widget hierarchy
/// - `logs`: structured runtime logs, including runtime errors when available
class CaptureAction extends StepAction {
  const CaptureAction({
    required this.screenshot,
    required this.snapshot,
    required this.widgetTree,
    required this.logs,
  });

  final bool screenshot;
  final bool snapshot;
  final bool widgetTree;
  final bool logs;
}
