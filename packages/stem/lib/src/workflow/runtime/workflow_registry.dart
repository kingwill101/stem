import 'package:stem/src/workflow/core/workflow_definition.dart';

/// Registry for workflow definitions keyed by name.
abstract class WorkflowRegistry {
  /// Registers a workflow [definition] in the registry.
  void register(WorkflowDefinition definition);

  /// Resolves a workflow definition by [name].
  WorkflowDefinition? lookup(String name);

  /// Returns all registered workflow definitions.
  List<WorkflowDefinition> get all;
}

/// In-memory [WorkflowRegistry] implementation for local runs and tests.
class InMemoryWorkflowRegistry implements WorkflowRegistry {
  final Map<String, WorkflowDefinition> _definitions = {};

  @override
  void register(WorkflowDefinition definition) {
    _definitions[definition.name] = definition;
  }

  @override
  WorkflowDefinition? lookup(String name) => _definitions[name];

  @override
  List<WorkflowDefinition> get all => List.unmodifiable(_definitions.values);
}
