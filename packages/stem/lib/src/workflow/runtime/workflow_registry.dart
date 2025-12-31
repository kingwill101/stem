import 'package:stem/src/workflow/core/workflow_definition.dart';

/// Registry for workflow definitions keyed by name.
class WorkflowRegistry {
  final Map<String, WorkflowDefinition> _definitions = {};

  /// Registers a workflow [definition] in the registry.
  void register(WorkflowDefinition definition) {
    _definitions[definition.name] = definition;
  }

  /// Resolves a workflow definition by [name].
  WorkflowDefinition? lookup(String name) => _definitions[name];

  /// Returns all registered workflow definitions.
  List<WorkflowDefinition> get all =>
      _definitions.values.toList(growable: false);
}
