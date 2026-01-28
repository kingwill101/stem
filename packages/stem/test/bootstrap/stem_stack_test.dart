import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemStack', () {
    test('resolves factories via adapters', () {
      final brokerFactory = StemBrokerFactory(
        create: () async => InMemoryBroker(),
      );
      final backendFactory = StemBackendFactory(
        create: () async => InMemoryResultBackend(),
      );
      final workflowFactory = WorkflowStoreFactory(
        create: () async => InMemoryWorkflowStore(),
      );

      final adapter = _TestAdapter(
        scheme: 'test',
        brokerFactory: brokerFactory,
        backendFactory: backendFactory,
        workflowStoreFactory: workflowFactory,
      );

      final stack = StemStack.fromUrl(
        'test://localhost',
        adapters: [adapter],
        workflows: true,
      );

      expect(stack.broker, same(brokerFactory));
      expect(stack.backend, same(backendFactory));
      expect(stack.workflowStore, same(workflowFactory));
      expect(stack.scheduleStore, isNull);
    });

    test('falls back to in-memory when using memory://', () async {
      final stack = StemStack.fromUrl('memory://');

      final broker = await stack.broker.create();
      final backend = await stack.backend.create();
      final workflowStore = await stack.workflowStore.create();

      expect(broker, isA<InMemoryBroker>());
      expect(backend, isA<InMemoryResultBackend>());
      expect(workflowStore, isA<InMemoryWorkflowStore>());
    });

    test('honors overrides for specific stores', () {
      final fooBroker = StemBrokerFactory(
        create: () async => InMemoryBroker(),
      );
      final fooBackend = StemBackendFactory(
        create: () async => InMemoryResultBackend(),
      );
      final fooWorkflow = WorkflowStoreFactory(
        create: () async => InMemoryWorkflowStore(),
      );

      final barBackend = StemBackendFactory(
        create: () async => InMemoryResultBackend(),
      );

      final foo = _TestAdapter(
        scheme: 'foo',
        brokerFactory: fooBroker,
        backendFactory: fooBackend,
        workflowStoreFactory: fooWorkflow,
      );
      final bar = _TestAdapter(
        scheme: 'bar',
        backendFactory: barBackend,
      );

      final stack = StemStack.fromUrl(
        'foo://localhost',
        adapters: [foo, bar],
        workflows: true,
        overrides: const StemStoreOverrides(backend: 'bar://override'),
      );

      expect(stack.broker, same(fooBroker));
      expect(stack.backend, same(barBackend));
      expect(stack.workflowStore, same(fooWorkflow));
    });

    test('requires lock store when unique tasks are enabled', () {
      final adapter = _TestAdapter(
        scheme: 'test',
        brokerFactory: StemBrokerFactory(create: () async => InMemoryBroker()),
        backendFactory: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
        workflowStoreFactory: WorkflowStoreFactory(
          create: () async => InMemoryWorkflowStore(),
        ),
      );

      expect(
        () => StemStack.fromUrl(
          'test://localhost',
          adapters: [adapter],
          uniqueTasks: true,
        ),
        throwsA(isA<StateError>()),
      );

      final stack = StemStack.fromUrl(
        'test://localhost',
        adapters: [adapter],
      );

      expect(stack.lockStore, isNull);
    });

    test('enforces revoke store when required', () {
      final adapter = _TestAdapter(
        scheme: 'test',
        brokerFactory: StemBrokerFactory(create: () async => InMemoryBroker()),
        backendFactory: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
      );

      expect(
        () => StemStack.fromUrl(
          'test://localhost',
          adapters: [adapter],
          requireRevokeStore: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('prefers custom adapter over memory adapter', () {
      final customBroker = StemBrokerFactory(
        create: () async => InMemoryBroker(),
      );

      final adapter = _TestAdapter(
        scheme: 'memory',
        brokerFactory: customBroker,
        backendFactory: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
        ),
      );

      final stack = StemStack.fromUrl(
        'memory://',
        adapters: [adapter],
      );

      expect(stack.broker, same(customBroker));
    });
  });
}

class _TestAdapter implements StemStoreAdapter {
  _TestAdapter({
    required this.scheme,
    StemBrokerFactory? brokerFactory,
    StemBackendFactory? backendFactory,
    WorkflowStoreFactory? workflowStoreFactory,
    ScheduleStoreFactory? scheduleStoreFactory,
    LockStoreFactory? lockStoreFactory,
    RevokeStoreFactory? revokeStoreFactory,
  }) : _brokerFactory = brokerFactory,
       _backendFactory = backendFactory,
       _workflowStoreFactory = workflowStoreFactory,
       _scheduleStoreFactory = scheduleStoreFactory,
       _lockStoreFactory = lockStoreFactory,
       _revokeStoreFactory = revokeStoreFactory;

  final String scheme;
  final StemBrokerFactory? _brokerFactory;
  final StemBackendFactory? _backendFactory;
  final WorkflowStoreFactory? _workflowStoreFactory;
  final ScheduleStoreFactory? _scheduleStoreFactory;
  final LockStoreFactory? _lockStoreFactory;
  final RevokeStoreFactory? _revokeStoreFactory;

  @override
  String get name => 'test';

  @override
  bool supports(Uri uri, StemStoreKind kind) => uri.scheme == scheme;

  @override
  StemBrokerFactory? brokerFactory(Uri uri) => _brokerFactory;

  @override
  StemBackendFactory? backendFactory(Uri uri) => _backendFactory;

  @override
  WorkflowStoreFactory? workflowStoreFactory(Uri uri) => _workflowStoreFactory;

  @override
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri) => _scheduleStoreFactory;

  @override
  LockStoreFactory? lockStoreFactory(Uri uri) => _lockStoreFactory;

  @override
  RevokeStoreFactory? revokeStoreFactory(Uri uri) => _revokeStoreFactory;
}
