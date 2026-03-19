import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/workflow/core/flow.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_script.dart';
import 'package:stem/src/workflow/runtime/workflow_manifest.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';

/// Generated or hand-authored bundle of tasks and workflow definitions.
///
/// The intended use is to pass one module into bootstrap helpers rather than
/// threading separate task, flow, and script lists through every call site.
class StemModule {
  /// Creates a bundled module of tasks and workflows.
  StemModule({
    Iterable<WorkflowDefinition> workflows = const [],
    Iterable<Flow> flows = const [],
    Iterable<WorkflowScript> scripts = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    Iterable<WorkflowManifestEntry>? workflowManifest,
  }) : workflows = List.unmodifiable(workflows),
       flows = List.unmodifiable(flows),
       scripts = List.unmodifiable(scripts),
       tasks = List.unmodifiable(tasks),
       workflowManifest = List.unmodifiable(
         workflowManifest ??
             _defaultManifest(
               workflows: workflows,
               flows: flows,
               scripts: scripts,
             ),
       );

  /// Raw workflow definitions that are not represented as [Flow] or
  /// [WorkflowScript] instances.
  final List<WorkflowDefinition> workflows;

  /// Flow workflows in this module.
  final List<Flow> flows;

  /// Script workflows in this module.
  final List<WorkflowScript> scripts;

  /// Task handlers in this module.
  final List<TaskHandler<Object?>> tasks;

  /// Workflow manifest entries exported by this module.
  final List<WorkflowManifestEntry> workflowManifest;

  /// All workflow definitions contained in the module.
  Iterable<WorkflowDefinition> get workflowDefinitions sync* {
    yield* workflows;
    for (final flow in flows) {
      yield flow.definition;
    }
    for (final script in scripts) {
      yield script.definition;
    }
  }

  /// Registers bundled definitions into the supplied registries.
  void registerInto({
    WorkflowRegistry? workflows,
    TaskRegistry? tasks,
  }) {
    if (workflows != null) {
      workflowDefinitions.forEach(workflows.register);
    }
    if (tasks != null) {
      this.tasks.forEach(tasks.register);
    }
  }

  static Iterable<WorkflowManifestEntry> _defaultManifest({
    required Iterable<WorkflowDefinition> workflows,
    required Iterable<Flow> flows,
    required Iterable<WorkflowScript> scripts,
  }) sync* {
    for (final workflow in workflows) {
      yield workflow.toManifestEntry();
    }
    for (final flow in flows) {
      yield flow.definition.toManifestEntry();
    }
    for (final script in scripts) {
      yield script.definition.toManifestEntry();
    }
  }
}
