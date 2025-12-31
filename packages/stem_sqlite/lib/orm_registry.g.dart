// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
import 'package:ormed/ormed.dart';
import 'src/models/stem_dead_letter.dart';
import 'src/models/stem_group.dart';
import 'src/models/stem_group_result.dart';
import 'src/models/stem_queue_job.dart';
import 'src/models/stem_task_result.dart';
import 'src/models/stem_worker_heartbeat.dart';
import 'src/models/stem_workflow_run.dart';
import 'src/models/stem_workflow_step.dart';
import 'src/models/stem_workflow_watcher.dart';

final List<ModelDefinition<OrmEntity>> _$ormModelDefinitions = [
  StemDeadLetterOrmDefinition.definition,
  StemGroupOrmDefinition.definition,
  StemGroupResultOrmDefinition.definition,
  StemQueueJobOrmDefinition.definition,
  StemTaskResultOrmDefinition.definition,
  StemWorkerHeartbeatOrmDefinition.definition,
  StemWorkflowRunOrmDefinition.definition,
  StemWorkflowStepOrmDefinition.definition,
  StemWorkflowWatcherOrmDefinition.definition,
];

ModelRegistry buildOrmRegistry() => ModelRegistry()
  ..registerAll(_$ormModelDefinitions)
  ..registerTypeAlias<StemDeadLetter>(_$ormModelDefinitions[0])
  ..registerTypeAlias<StemGroup>(_$ormModelDefinitions[1])
  ..registerTypeAlias<StemGroupResult>(_$ormModelDefinitions[2])
  ..registerTypeAlias<StemQueueJob>(_$ormModelDefinitions[3])
  ..registerTypeAlias<StemTaskResult>(_$ormModelDefinitions[4])
  ..registerTypeAlias<StemWorkerHeartbeat>(_$ormModelDefinitions[5])
  ..registerTypeAlias<StemWorkflowRun>(_$ormModelDefinitions[6])
  ..registerTypeAlias<StemWorkflowStep>(_$ormModelDefinitions[7])
  ..registerTypeAlias<StemWorkflowWatcher>(_$ormModelDefinitions[8])
  ;

List<ModelDefinition<OrmEntity>> get generatedOrmModelDefinitions =>
    List.unmodifiable(_$ormModelDefinitions);

extension GeneratedOrmModels on ModelRegistry {
  ModelRegistry registerGeneratedModels() {
    registerAll(_$ormModelDefinitions);
    registerTypeAlias<StemDeadLetter>(_$ormModelDefinitions[0]);
    registerTypeAlias<StemGroup>(_$ormModelDefinitions[1]);
    registerTypeAlias<StemGroupResult>(_$ormModelDefinitions[2]);
    registerTypeAlias<StemQueueJob>(_$ormModelDefinitions[3]);
    registerTypeAlias<StemTaskResult>(_$ormModelDefinitions[4]);
    registerTypeAlias<StemWorkerHeartbeat>(_$ormModelDefinitions[5]);
    registerTypeAlias<StemWorkflowRun>(_$ormModelDefinitions[6]);
    registerTypeAlias<StemWorkflowStep>(_$ormModelDefinitions[7]);
    registerTypeAlias<StemWorkflowWatcher>(_$ormModelDefinitions[8]);
    return this;
  }
}

/// Registers factory definitions for all models that have factory support.
/// Call this before using [Model.factory<T>()] to ensure definitions are available.
void registerOrmFactories() {
}

/// Combined setup: registers both model registry and factories.
/// Returns a ModelRegistry with all generated models registered.
ModelRegistry buildOrmRegistryWithFactories() {
  registerOrmFactories();
  return buildOrmRegistry();
}

/// Registers generated model event handlers.
void registerModelEventHandlers({EventBus? bus}) {
  // No model event handlers were generated.
}

/// Registers generated model scopes into a [ScopeRegistry].
void registerModelScopes({ScopeRegistry? scopeRegistry}) {
  // No model scopes were generated.
}

/// Bootstraps generated ORM pieces: registry, factories, event handlers, and scopes.
ModelRegistry bootstrapOrm({ModelRegistry? registry, EventBus? bus, ScopeRegistry? scopes, bool registerFactories = true, bool registerEventHandlers = true, bool registerScopes = true}) {
  final reg = registry ?? buildOrmRegistry();
  if (registry != null) {
    reg.registerGeneratedModels();
  }
  if (registerFactories) {
    registerOrmFactories();
  }
  if (registerEventHandlers) {
    registerModelEventHandlers(bus: bus);
  }
  if (registerScopes) {
    registerModelScopes(scopeRegistry: scopes);
  }
  return reg;
}
