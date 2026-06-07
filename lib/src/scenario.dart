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
/// - `byKey`: logical key string
/// - `byType`: simple Flutter widget class name
///
/// Example:
/// `Finder(byText: '登录', byType: 'TextButton')` means both rules must match.
class Finder {
  const Finder({this.byText, this.byKey, this.byType});

  final String? byText;
  final String? byKey;
  final String? byType;

  bool get isEmpty => byText == null && byKey == null && byType == null;
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
  final num deltaX;
  final num deltaY;
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
/// - `errors`: current Flutter errors
/// - `logs`: recent Flutter logs
class CaptureAction extends StepAction {
  const CaptureAction({
    required this.screenshot,
    required this.snapshot,
    required this.widgetTree,
    required this.errors,
    required this.logs,
  });

  final bool screenshot;
  final bool snapshot;
  final bool widgetTree;
  final bool errors;
  final bool logs;
}
