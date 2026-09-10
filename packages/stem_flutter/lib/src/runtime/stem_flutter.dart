import 'package:flutter/widgets.dart';
import 'package:stem/stem.dart';

/// Flutter bootstrap for the ordinary [StemApp] API.
///
/// Task registration, typed calls, results, Canvas, and worker execution remain
/// owned by Stem. No app-defined isolate entrypoint or message protocol is
/// required. Like [StemApp.create], [createApp] does not start consumption.
abstract final class StemFlutter {
  /// Conservative local-worker defaults without desktop process signal hooks.
  static const defaultWorkerConfig = StemWorkerConfig(
    concurrency: 1,
    prefetchMultiplier: 1,
    lifecycle: WorkerLifecycleConfig(installSignalHandlers: false),
  );

  /// Creates a real [StemApp], using the same configuration as Stem.
  ///
  /// Factories define storage ownership exactly as in [StemApp.create]. The
  /// returned app owns their configured disposers; call `app.shutdown()` once
  /// the application is finished with it.
  ///
  /// The worker is hosted in the calling isolate. Tasks retain Stem's normal
  /// inline/isolate execution choices. Inline asynchronous work can use Flutter
  /// plugins; CPU-heavy work should use an isolate-capable task handler.
  /// Neither execution mode grants OS-managed background execution.
  static Future<StemApp> createApp({
    StemModule? module,
    Iterable<StemModule> modules = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? registry,
    StemBrokerFactory? broker,
    StemBackendFactory? backend,
    StemWorkerConfig workerConfig = defaultWorkerConfig,
    RevokeStore? revokeStore,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    RetryStrategy? retryStrategy,
    Iterable<Middleware> middleware = const [],
    PayloadSigner? signer,
    RoutingRegistry? routing,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    return StemApp.create(
      module: module,
      modules: modules,
      tasks: tasks,
      registry: registry,
      broker: broker,
      backend: backend,
      workerConfig: workerConfig.copyWith(
        concurrency: workerConfig.concurrency ?? 1,
        lifecycle: workerConfig.lifecycle ?? defaultWorkerConfig.lifecycle,
      ),
      revokeStore: revokeStore,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      retryStrategy: retryStrategy,
      middleware: middleware,
      signer: signer,
      routing: routing,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }
}
