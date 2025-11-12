import '../core/workflow_definition.dart';

class WorkflowRegistry {
  final Map<String, WorkflowDefinition> _definitions = {};

  void register(WorkflowDefinition definition) {
    _definitions[definition.name] = definition;
  }

  WorkflowDefinition? lookup(String name) => _definitions[name];

  List<WorkflowDefinition> get all =>
      _definitions.values.toList(growable: false);
}
