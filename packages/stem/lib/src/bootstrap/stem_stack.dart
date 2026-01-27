/// Autowiring helpers for mapping URLs to Stem store factories.
library;

import 'package:stem/src/bootstrap/factories.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:stem/src/core/contracts.dart';

/// Store categories that can be resolved by adapters.
enum StemStoreKind {
  /// Broker transport used for task delivery.
  broker,

  /// Result backend used for task state and results.
  backend,

  /// Workflow store used for durable workflow state.
  workflow,

  /// Schedule store used by the scheduler/beat.
  schedule,

  /// Lock store used for unique tasks or schedule coordination.
  lock,

  /// Revoke store used for worker control persistence.
  revoke,
}

/// Optional URL overrides for specific store kinds.
class StemStoreOverrides {
  /// Creates an overrides object for specific store URLs.
  const StemStoreOverrides({
    this.broker,
    this.backend,
    this.workflow,
    this.schedule,
    this.lock,
    this.revoke,
  });

  /// Override URL for the broker.
  final String? broker;

  /// Override URL for the result backend.
  final String? backend;

  /// Override URL for the workflow store.
  final String? workflow;

  /// Override URL for the schedule store.
  final String? schedule;

  /// Override URL for the lock store.
  final String? lock;

  /// Override URL for the revoke store.
  final String? revoke;
}

/// Adapter that can resolve Stem store factories from a URL.
abstract class StemStoreAdapter {
  /// Adapter identifier used in error messages.
  String get name;

  /// Returns true when the adapter can provide [kind] for [uri].
  bool supports(Uri uri, StemStoreKind kind);

  /// Resolves a broker factory for [uri].
  StemBrokerFactory? brokerFactory(Uri uri);

  /// Resolves a result backend factory for [uri].
  StemBackendFactory? backendFactory(Uri uri);

  /// Resolves a workflow store factory for [uri].
  WorkflowStoreFactory? workflowStoreFactory(Uri uri);

  /// Resolves a schedule store factory for [uri].
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri);

  /// Resolves a lock store factory for [uri].
  LockStoreFactory? lockStoreFactory(Uri uri);

  /// Resolves a revoke store factory for [uri].
  RevokeStoreFactory? revokeStoreFactory(Uri uri);
}

/// Built-in adapter for in-memory stores using the `memory://` scheme.
class StemMemoryAdapter implements StemStoreAdapter {
  /// Creates a memory adapter.
  const StemMemoryAdapter();

  @override
  String get name => 'stem:memory';

  @override
  bool supports(Uri uri, StemStoreKind kind) {
    return uri.scheme == 'memory' || uri.scheme == 'mem';
  }

  @override
  StemBrokerFactory? brokerFactory(Uri uri) => StemBrokerFactory.inMemory();

  @override
  StemBackendFactory? backendFactory(Uri uri) => StemBackendFactory.inMemory();

  @override
  WorkflowStoreFactory? workflowStoreFactory(Uri uri) =>
      WorkflowStoreFactory.inMemory();

  @override
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri) =>
      ScheduleStoreFactory.inMemory();

  @override
  LockStoreFactory? lockStoreFactory(Uri uri) => LockStoreFactory.inMemory();

  @override
  RevokeStoreFactory? revokeStoreFactory(Uri uri) =>
      RevokeStoreFactory.inMemory();
}

/// Resolved factories for a Stem deployment stack.
class StemStack {
  StemStack._({
    required this.broker,
    required this.backend,
    required this.workflowStore,
    required this.adapters,
    this.scheduleStore,
    this.lockStore,
    this.revokeStore,
  });

  /// Resolves factories from a base URL and adapter list.
  factory StemStack.fromUrl(
    String url, {
    Iterable<StemStoreAdapter> adapters = const [],
    StemStoreOverrides overrides = const StemStoreOverrides(),
    bool workflows = false,
    bool scheduling = false,
    bool uniqueTasks = false,
    bool requireRevokeStore = false,
  }) {
    final baseUri = Uri.parse(url);
    final registered = <StemStoreAdapter>[
      ...adapters,
      const StemMemoryAdapter(),
    ];

    final brokerUri = _resolveUri(overrides.broker, baseUri);
    final backendUri = _resolveUri(overrides.backend, baseUri);
    final workflowUri = _resolveUri(overrides.workflow, baseUri);
    final scheduleUri = _resolveUri(overrides.schedule, baseUri);
    final lockUri = _resolveUri(overrides.lock, baseUri);
    final revokeUri = _resolveUri(overrides.revoke, backendUri);

    final broker = _requireFactory<StemBrokerFactory>(
      registered,
      StemStoreKind.broker,
      brokerUri,
      (adapter) => adapter.brokerFactory(brokerUri),
    );

    final backend = _requireFactory<StemBackendFactory>(
      registered,
      StemStoreKind.backend,
      backendUri,
      (adapter) => adapter.backendFactory(backendUri),
    );

    final workflowStore = workflows
        ? _requireFactory<WorkflowStoreFactory>(
            registered,
            StemStoreKind.workflow,
            workflowUri,
            (adapter) => adapter.workflowStoreFactory(workflowUri),
          )
        : WorkflowStoreFactory.inMemory();

    final scheduleStore = scheduling
        ? _requireFactory<ScheduleStoreFactory>(
            registered,
            StemStoreKind.schedule,
            scheduleUri,
            (adapter) => adapter.scheduleStoreFactory(scheduleUri),
          )
        : null;

    final lockStore = uniqueTasks
        ? _requireFactory<LockStoreFactory>(
            registered,
            StemStoreKind.lock,
            lockUri,
            (adapter) => adapter.lockStoreFactory(lockUri),
          )
        : _optionalFactory<LockStoreFactory>(
            registered,
            StemStoreKind.lock,
            lockUri,
            (adapter) => adapter.lockStoreFactory(lockUri),
          );

    final revokeStore = requireRevokeStore
        ? _requireFactory<RevokeStoreFactory>(
            registered,
            StemStoreKind.revoke,
            revokeUri,
            (adapter) => adapter.revokeStoreFactory(revokeUri),
          )
        : _optionalFactory<RevokeStoreFactory>(
            registered,
            StemStoreKind.revoke,
            revokeUri,
            (adapter) => adapter.revokeStoreFactory(revokeUri),
          );

    return StemStack._(
      broker: broker,
      backend: backend,
      workflowStore: workflowStore,
      scheduleStore: scheduleStore,
      lockStore: lockStore,
      revokeStore: revokeStore,
      adapters: List.unmodifiable(registered),
    );
  }

  /// Broker factory.
  final StemBrokerFactory broker;

  /// Result backend factory.
  final StemBackendFactory backend;

  /// Workflow store factory.
  final WorkflowStoreFactory workflowStore;

  /// Optional schedule store factory.
  final ScheduleStoreFactory? scheduleStore;

  /// Optional lock store factory.
  final LockStoreFactory? lockStore;

  /// Optional revoke store factory.
  final RevokeStoreFactory? revokeStore;

  /// Adapters used to resolve this stack.
  final List<StemStoreAdapter> adapters;

  /// Creates a schedule store using the resolved factory.
  Future<ScheduleStore> createScheduleStore() {
    final factory = scheduleStore;
    if (factory == null) {
      throw StateError('No schedule store factory configured.');
    }
    return factory.create();
  }

  /// Creates a lock store using the resolved factory.
  Future<LockStore> createLockStore() {
    final factory = lockStore;
    if (factory == null) {
      throw StateError('No lock store factory configured.');
    }
    return factory.create();
  }

  /// Creates a revoke store using the resolved factory.
  Future<RevokeStore> createRevokeStore() {
    final factory = revokeStore;
    if (factory == null) {
      throw StateError('No revoke store factory configured.');
    }
    return factory.create();
  }
}

Uri _resolveUri(String? override, Uri fallback) {
  if (override == null || override.trim().isEmpty) {
    return fallback;
  }
  return Uri.parse(override);
}

T _requireFactory<T>(
  Iterable<StemStoreAdapter> adapters,
  StemStoreKind kind,
  Uri uri,
  T? Function(StemStoreAdapter adapter) resolver,
) {
  for (final adapter in adapters) {
    if (!adapter.supports(uri, kind)) continue;
    final factory = resolver(adapter);
    if (factory != null) return factory;
  }
  throw StateError(
    'No adapter registered for ${kind.name} at ${uri.scheme} ($uri).',
  );
}

T? _optionalFactory<T>(
  Iterable<StemStoreAdapter> adapters,
  StemStoreKind kind,
  Uri uri,
  T? Function(StemStoreAdapter adapter) resolver,
) {
  for (final adapter in adapters) {
    if (!adapter.supports(uri, kind)) continue;
    final factory = resolver(adapter);
    if (factory != null) return factory;
  }
  return null;
}
