import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

import '../../support/postgres_test_harness.dart';

Future<void> main() async {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres transactional outbox requires STEM_TEST_POSTGRES_URL',
      () {},
      skip: 'Set STEM_TEST_POSTGRES_URL to run transactional outbox tests.',
    );
    return;
  }

  final harness = await createStemPostgresTestHarness(
    connectionString: connectionString,
  );
  tearDownAll(harness.dispose);

  ormedGroup('postgres transactional outbox', (dataSource) {
    late PostgresTransactionalOutbox outbox;
    late PostgresBroker broker;
    late Broker outboxBroker;
    late String namespace;
    late String queue;

    setUp(() async {
      namespace = 'outbox-${DateTime.now().microsecondsSinceEpoch}';
      queue = 'queue-${DateTime.now().microsecondsSinceEpoch}';
      outbox = await PostgresTransactionalOutbox.fromDataSource(
        dataSource,
        namespace: namespace,
        runMigrations: false,
      );
      broker = await PostgresBroker.fromDataSource(
        dataSource,
        namespace: namespace,
        pollInterval: const Duration(milliseconds: 20),
        sweeperInterval: const Duration(milliseconds: 100),
        runMigrations: false,
      );
      outboxBroker = outbox.wrap(broker);
    });

    tearDown(() => broker.close());

    test(
      'rolls back publication records with the application transaction',
      () async {
        final envelope = Envelope(
          id: 'rollback-${DateTime.now().microsecondsSinceEpoch}',
          name: 'outbox.rollback',
          args: const {'value': 1},
          queue: queue,
        );

        await expectLater(
          outbox.transaction((_) async {
            await outboxBroker.publish(envelope);
            throw StateError('application transaction failed');
          }),
          throwsStateError,
        );

        expect(await outbox.pendingCount(), 0);
        expect(await broker.pendingCount(queue), 0);
      },
    );

    test(
      'dispatches committed rows once and preserves envelope identity',
      () async {
        final envelope = Envelope(
          id: 'commit-${DateTime.now().microsecondsSinceEpoch}',
          name: 'outbox.commit',
          args: const {'value': 1},
          queue: queue,
        );

        await outbox.transaction((_) => outboxBroker.publish(envelope));

        expect(await outbox.pendingCount(), 1);
        expect(await outbox.dispatch(broker: broker), 1);
        expect(await outbox.dispatch(broker: broker), 0);
        expect(await outbox.pendingCount(), 0);
        expect(await broker.pendingCount(queue), 1);

        final delivery = await broker
            .consume(RoutingSubscription.singleQueue(queue))
            .first;
        expect(delivery.envelope.id, envelope.id);
        await broker.ack(delivery);
      },
    );

    test(
      'two relay workers claim committed rows without overlap',
      () async {
        final envelopes = [
          for (var index = 0; index < 8; index++)
            Envelope(
              id: 'concurrent-$index-${DateTime.now().microsecondsSinceEpoch}',
              name: 'outbox.concurrent',
              args: {'value': index},
              queue: queue,
            ),
        ];

        await outbox.transaction((_) async {
          for (final envelope in envelopes) {
            await outboxBroker.publish(envelope);
          }
        });

        final dispatched = await Future.wait([
          outbox.dispatch(
            broker: broker,
            limit: envelopes.length,
            workerId: 'relay-a',
          ),
          outbox.dispatch(
            broker: broker,
            limit: envelopes.length,
            workerId: 'relay-b',
          ),
        ]);

        expect(
          dispatched.reduce((left, right) => left + right),
          envelopes.length,
        );
        expect(await outbox.pendingCount(), 0);
        expect(await broker.pendingCount(queue), envelopes.length);
      },
    );

    test('rejects publication outside an outbox transaction', () async {
      final envelope = Envelope(
        name: 'outbox.invalid',
        args: const {},
        queue: queue,
      );

      await expectLater(
        outboxBroker.publish(envelope),
        throwsStateError,
      );
    });

    test('records relay failures for a later leased retry', () async {
      final envelope = Envelope(
        id: 'failure-${DateTime.now().microsecondsSinceEpoch}',
        name: 'outbox.failure',
        args: const {},
        queue: queue,
      );

      await outbox.transaction((_) => outboxBroker.publish(envelope));

      expect(
        await outbox.dispatch(
          broker: outboxBroker,
          retryDelay: const Duration(hours: 1),
        ),
        0,
      );
      expect(await outbox.pendingCount(), 1);
      expect(await broker.pendingCount(queue), 0);
    });
  }, config: harness.config);
}
