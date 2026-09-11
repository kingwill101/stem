import 'dart:async';
import 'dart:io';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemApp lifecycle', () {
    test('worker ID follows the heartbeat identity rule', () async {
      for (final name in ['named-worker', '', null]) {
        final app = await StemApp.inMemory(
          workerConfig: StemWorkerConfig(consumerName: name),
        );
        expect(
          app.worker.workerId,
          name == null || name.isEmpty ? 'stem-worker-$pid' : name,
        );
        await app.shutdown();
      }
    });

    test('rollback respects factories without ownership disposers', () async {
      final broker = InMemoryBroker();
      final error = StateError('open failed');
      await expectLater(
        StemApp.create(
          broker: StemBrokerFactory(create: () async => broker),
          backend: StemBackendFactory(create: () async => throw error),
        ),
        throwsA(same(error)),
      );
      // Reuse the externally owned broker in a new app.
      final app = await StemApp.create(
        broker: StemBrokerFactory(create: () async => broker),
      );
      await app.start();
      await app.shutdown();
      await broker.close();
    });

    test(
      'backend open failure rolls back broker without hiding error',
      () async {
        final broker = InMemoryBroker();
        final startupError = StateError('open failed');
        var disposed = 0;
        await expectLater(
          StemApp.create(
            broker: StemBrokerFactory(
              create: () async => broker,
              dispose: (value) async {
                disposed++;
                await value.close();
                throw StateError('cleanup failed');
              },
            ),
            backend: StemBackendFactory(create: () async => throw startupError),
          ),
          throwsA(same(startupError)),
        );
        expect(disposed, 1);
      },
    );

    test(
      'construction failure rolls back in reverse acquisition order',
      () async {
        final order = <String>[];
        final startupError = StateError('construction failed');
        await expectLater(
          StemApp.create(
            broker: StemBrokerFactory(
              create: () async => InMemoryBroker(),
              dispose: (value) async {
                order.add('broker');
                await value.close();
              },
            ),
            backend: StemBackendFactory(
              create: () async => InMemoryResultBackend(),
              dispose: (value) async {
                order.add('backend');
                await value.close();
                throw StateError('cleanup failed');
              },
            ),
            middleware: _throwingMiddleware(startupError),
          ),
          throwsA(same(startupError)),
        );
        expect(order, ['backend', 'broker']);
      },
    );

    test('shutdown shares cleanup and retains first disposal error', () async {
      final order = <String>[];
      final gate = Completer<void>();
      final entered = Completer<void>();
      final firstError = StateError('backend cleanup');
      final app = await StemApp.create(
        broker: StemBrokerFactory(
          create: () async => InMemoryBroker(),
          dispose: (value) async {
            order.add('broker');
            await value.close();
            throw StateError('broker cleanup');
          },
        ),
        backend: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
          dispose: (value) async {
            order.add('backend');
            entered.complete();
            await gate.future;
            await value.close();
            throw firstError;
          },
        ),
      );
      final closing = app.shutdown();
      final result = expectLater(closing, throwsA(same(firstError)));
      await entered.future;
      expect(app.shutdown(), same(closing));
      await expectLater(app.start(), throwsStateError);
      gate.complete();
      await result;
      await expectLater(app.shutdown(), throwsA(same(firstError)));
      expect(order, ['backend', 'broker']);
      expect(app.isStarted, isFalse);
    });

    test('shutdown waits for concurrent starts before disposing', () async {
      final store = _GatedRevokeStore();
      var brokerDisposed = false;
      final app = await StemApp.create(
        broker: StemBrokerFactory(
          create: () async => InMemoryBroker(),
          dispose: (value) async {
            brokerDisposed = true;
            await value.close();
          },
        ),
        workerConfig: StemWorkerConfig(revokeStore: store),
      );
      final starting = app.start();
      expect(app.start(), same(starting));
      await store.entered.future;
      final closing = app.shutdown();
      expect(app.shutdown(), same(closing));
      await expectLater(app.start(), throwsStateError);
      expect(brokerDisposed, isFalse);
      store.gate.complete();
      await starting;
      await closing;
      expect(app.isStarted, isFalse);
      expect(brokerDisposed, isTrue);
      await expectLater(app.start(), throwsStateError);
    });

    test('shutdown also waits for a failing start', () async {
      final store = _GatedRevokeStore();
      final error = StateError('consume failed');
      final app = await StemApp.create(
        broker: StemBrokerFactory(
          create: () async => _FailingBroker(error),
          dispose: (value) => value.close(),
        ),
        workerConfig: StemWorkerConfig(revokeStore: store),
      );
      final starting = app.start();
      final result = expectLater(starting, throwsA(same(error)));
      await store.entered.future;
      final closing = app.shutdown();
      store.gate.complete();
      await result;
      await closing;
      expect(app.isStarted, isFalse);
    });

    test('start failure is delivered once and can be shut down', () async {
      final error = StateError('consume failed');
      final app = await StemApp.create(
        broker: StemBrokerFactory(
          create: () async => _FailingBroker(error),
          dispose: (value) => value.close(),
        ),
      );
      await expectLater(app.start(), throwsA(same(error)));
      await expectLater(app.start(), throwsA(same(error)));
      expect(app.isStarted, isFalse);
      await app.shutdown();
      await app.shutdown();
      await expectLater(app.start(), throwsStateError);
    });

    test('fromClient shutdown does not dispose shared resources', () async {
      var disposed = 0;
      final client = await StemClient.create(
        broker: StemBrokerFactory(
          create: () async => InMemoryBroker(),
          dispose: (value) async {
            disposed++;
            await value.close();
          },
        ),
        backend: StemBackendFactory(
          create: () async => InMemoryResultBackend(),
          dispose: (value) async {
            disposed++;
            await value.close();
          },
        ),
      );
      final app = await StemApp.fromClient(client);
      await app.start();
      await app.shutdown();
      await app.shutdown();
      expect(disposed, 0);
      await client.close();
      expect(disposed, 2);
    });
  });
}

Iterable<Middleware> _throwingMiddleware(StateError error) sync* {
  throw error;
}

class _GatedRevokeStore extends InMemoryRevokeStore {
  final entered = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<List<RevokeEntry>> list(String namespace) async {
    if (!entered.isCompleted) {
      entered.complete();
      await gate.future;
    }
    return super.list(namespace);
  }
}

class _FailingBroker extends InMemoryBroker {
  _FailingBroker(this.error);

  final StateError error;

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => throw error;
}
