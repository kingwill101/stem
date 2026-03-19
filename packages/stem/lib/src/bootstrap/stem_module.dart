import 'dart:collection';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/workflow/core/flow.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_script.dart';
import 'package:stem/src/workflow/runtime/workflow_manifest.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';

/// Registers task handlers while tolerating re-registration of identical
/// handler instances.
void registerModuleTaskHandlers(
  TaskRegistry registry,
  Iterable<TaskHandler<Object?>> handlers,
) {
  for (final handler in handlers) {
    final existing = registry.resolve(handler.name);
    if (identical(existing, handler)) {
      continue;
    }
    registry.register(handler);
  }
}

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

  /// Returns the default queues implied by the bundled task handlers.
  ///
  /// The [workflowQueue] is always included so workflow orchestration remains
  /// runnable when the inferred queues are used to bootstrap a worker.
  List<String> inferredWorkerQueues({
    String workflowQueue = 'workflow',
    Iterable<TaskHandler<Object?>> additionalTasks = const [],
  }) {
    final queues = SplayTreeSet<String>();
    final normalizedWorkflowQueue = workflowQueue.trim();
    if (normalizedWorkflowQueue.isNotEmpty) {
      queues.add(normalizedWorkflowQueue);
    }

    void addTaskQueue(TaskHandler<Object?> handler) {
      final queue = handler.options.queue.trim();
      if (queue.isNotEmpty) {
        queues.add(queue);
      }
    }

    tasks.forEach(addTaskQueue);
    additionalTasks.forEach(addTaskQueue);
    return queues.toList(growable: false);
  }

  /// Infers a worker subscription from the bundled task handlers.
  ///
  /// Returns `null` when only the [workflowQueue] is needed, allowing the
  /// worker's default queue configuration to remain unchanged.
  RoutingSubscription? inferWorkerSubscription({
    String workflowQueue = 'workflow',
    Iterable<TaskHandler<Object?>> additionalTasks = const [],
  }) {
    final queues = inferredWorkerQueues(
      workflowQueue: workflowQueue,
      additionalTasks: additionalTasks,
    );
    if (queues.length <= 1) {
      return null;
    }
    return RoutingSubscription(queues: queues);
  }

  /// Returns the default queues implied by the bundled task handlers only.
  List<String> inferredTaskQueues({
    Iterable<TaskHandler<Object?>> additionalTasks = const [],
  }) {
    final queues = SplayTreeSet<String>();

    void addTaskQueue(TaskHandler<Object?> handler) {
      final queue = handler.options.queue.trim();
      if (queue.isNotEmpty) {
        queues.add(queue);
      }
    }

    tasks.forEach(addTaskQueue);
    additionalTasks.forEach(addTaskQueue);
    return queues.toList(growable: false);
  }

  /// Infers a worker subscription from bundled task handlers only.
  ///
  /// Returns `null` when the bundled tasks only target [defaultQueue], allowing
  /// the worker's default queue configuration to remain unchanged.
  RoutingSubscription? inferTaskWorkerSubscription({
    String defaultQueue = 'default',
    Iterable<TaskHandler<Object?>> additionalTasks = const [],
  }) {
    final queues = inferredTaskQueues(additionalTasks: additionalTasks);
    if (queues.isEmpty) return null;
    if (queues.length == 1 && queues.first == defaultQueue.trim()) {
      return null;
    }
    return RoutingSubscription(queues: queues);
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
