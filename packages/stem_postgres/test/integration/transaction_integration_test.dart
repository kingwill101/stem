import 'dart:async';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/datasource.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

import '../support/postgres_test_harness.dart';

void contain(Future<void> future) {
  unawaited(
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    ),
  );
}

Future<void> main() async {
  final connectionString =
      Platform.environment['STEM_TEST_POSTGRES_URL'] ??
      Platform.environment['POSTGRES_URL'] ??
      'postgresql://postgres:postgres@127.0.0.1:65432/stem_test';

  final harness = await createStemPostgresTestHarness(
    connectionString: connectionString,
  );
  tearDownAll(harness.dispose);

  ormedGroup('postgres transaction integration', (dataSource) {
    late PostgresTransactionalOutbox outbox;
    late PostgresWorkflowStore store;
    late PostgresOutboxBroker broker;
    late String namespace;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      namespace = 'tx_gap_$suffix';
      outbox = await PostgresTransactionalOutbox.fromDataSource(
        dataSource,
        namespace: namespace,
        runMigrations: false,
      );
      store = await PostgresWorkflowStore.fromDataSource(
        dataSource,
        namespace: namespace,
        runMigrations: false,
      );
      final delegate = await PostgresBroker.fromDataSource(
        dataSource,
        namespace: namespace,
        runMigrations: false,
      );
      broker = outbox.wrap(delegate);
    });

    tearDown(() => broker.close());

    test('commits workflow run and outbox publication together', () async {
      final envelope = Envelope(
        id: 'commit-${DateTime.now().microsecondsSinceEpoch}',
        name: 'transaction.commit',
        args: const {},
        queue: 'transaction-queue',
      );

      final runId = await outbox.transaction((_) async {
        final id = await store.createRun(
          workflow: 'transaction.commit',
          params: const {},
        );
        await broker.publish(envelope);
        return id;
      });

      expect((await store.get(runId))?.id, runId);
      expect(await outbox.pendingCount(), 1);
    });

    test('rolls back workflow run and outbox publication together', () async {
      final envelope = Envelope(
        id: 'rollback-${DateTime.now().microsecondsSinceEpoch}',
        name: 'transaction.rollback',
        args: const {},
        queue: 'transaction-queue',
      );
      late String runId;

      await expectLater(
        outbox.transaction((_) async {
          runId = await store.createRun(
            workflow: 'transaction.rollback',
            params: const {},
          );
          await broker.publish(envelope);
          throw StateError('rollback');
        }),
        throwsStateError,
      );

      expect(await store.get(runId), isNull);
      expect(await outbox.pendingCount(), 0);
    });

    test(
      'serializes an unrelated transaction while the outer one is active',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final unrelated = PostgresConnections.fromDataSource(dataSource);
        var outerEntered = false;

        final first = unrelated.runInTransaction((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;

        final second = outbox.transaction((_) async {
          outerEntered = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(outerEntered, isFalse);
        release.complete();
        await Future.wait<void>([first, second]);
        expect(outerEntered, isTrue);
      },
    );

    test('same-source nested store transaction does not deadlock', () async {
      final runId = await outbox.transaction(
        (_) => store.createRun(
          workflow: 'transaction.nested',
          params: const {},
        ),
      );

      expect((await store.get(runId))?.id, runId);
    });

    test('rejects a transaction escaped after its scope ends', () async {
      final gate = Completer<void>();
      late Future<void> escaped;

      await outbox.transaction((_) async {
        escaped = (() async {
          await gate.future;
          await store.createRun(
            workflow: 'transaction.escaped',
            params: const {},
          );
        })();
      });

      gate.complete();
      await expectLater(escaped, throwsStateError);
    });

    test(
      'rejects an escaped outbox broker publication without a row',
      () async {
        final gate = Completer<void>();
        late Future<void> escaped;
        final envelope = Envelope(
          id: 'escaped-publish-${DateTime.now().microsecondsSinceEpoch}',
          name: 'transaction.escaped.publish',
          args: const {},
          queue: 'transaction-queue',
        );

        await outbox.transaction((_) async {
          escaped = (() async {
            await gate.future;
            await broker.publish(envelope);
          })();
        });

        gate.complete();
        await expectLater(escaped, throwsStateError);
        expect(await outbox.pendingCount(), 0);
      },
    );

    test('drains unawaited admitted nested work before commit', () async {
      late Future<String> nested;
      await outbox.transaction((_) async {
        nested = outbox.transaction((_) {
          return store.createRun(
            workflow: 'transaction.joined.commit',
            params: const {},
          );
        });
      });

      final runId = await nested;
      expect((await store.get(runId))?.id, runId);
    });

    test('drains a directly unawaited outbox enqueue before commit', () async {
      final envelope = Envelope(
        id: 'direct-${DateTime.now().microsecondsSinceEpoch}',
        name: 'transaction.direct',
        args: const {},
        queue: 'transaction-queue',
      );

      await outbox.transaction((transaction) async {
        unawaited(transaction.enqueueEnvelope(envelope));
      });

      expect(await outbox.pendingCount(), 1);
    });

    test(
      'rejects a retained transaction in a newer same-source transaction',
      () async {
        late PostgresOutboxTransaction oldTransaction;
        final oldEnvelope = Envelope(
          id: 'old-${DateTime.now().microsecondsSinceEpoch}',
          name: 'transaction.old',
          args: const {},
          queue: 'transaction-queue',
        );
        await outbox.transaction((transaction) async {
          oldTransaction = transaction;
        });

        await outbox.transaction((_) async {
          await expectLater(
            oldTransaction.enqueueEnvelope(oldEnvelope),
            throwsStateError,
          );
        });

        expect(await outbox.pendingCount(), 0);
      },
    );

    test('drains grandchildren admitted while draining', () async {
      final first = Envelope(
        id: 'child-${DateTime.now().microsecondsSinceEpoch}',
        name: 'transaction.child',
        args: const {},
        queue: 'transaction-queue',
      );
      final second = Envelope(
        id: 'grandchild-${DateTime.now().microsecondsSinceEpoch}',
        name: 'transaction.grandchild',
        args: const {},
        queue: 'transaction-queue',
      );

      await outbox.transaction((transaction) async {
        unawaited(
          outbox.transaction((_) async {
            await transaction.enqueueEnvelope(first);
            await transaction.enqueueEnvelope(second);
          }),
        );
      });

      expect(await outbox.pendingCount(), 2);
    });

    test('rolls back when unawaited admitted nested work fails', () async {
      late Future<void> nested;
      await expectLater(
        outbox.transaction((_) async {
          nested = outbox.transaction((_) async {
            await store.createRun(
              workflow: 'transaction.joined.failure',
              params: const {},
            );
            throw StateError('nested failure');
          });
        }),
        throwsStateError,
      );
      await expectLater(nested, throwsStateError);
      expect(await outbox.pendingCount(), 0);
    });

    test('preserves the root error when admitted work also fails', () async {
      await expectLater(
        outbox.transaction((_) async {
          unawaited(
            outbox.transaction((_) async {
              throw StateError('joined failure');
            }),
          );
          throw StateError('root failure');
        }),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('root failure'),
          ),
        ),
      );
    });

    test(
      'detached future transformations do not hide an admitted failure',
      () async {
        final transformations = <void Function(Future<void>)>[
          (future) => contain(future.then<void>((_) {})),
          (future) => contain(future.whenComplete(() {})),
          (future) => contain(future.timeout(const Duration(seconds: 1))),
          (future) => future.asStream().listen(
            null,
            onError: (Object error, StackTrace stackTrace) {},
          ),
        ];

        for (var index = 0; index < transformations.length; index++) {
          await expectLater(
            outbox.transaction((transaction) async {
              final envelope = Envelope(
                id:
                    'transformation-$index-'
                    '${DateTime.now().microsecondsSinceEpoch}',
                name: 'transaction.transformation',
                args: const {},
                queue: 'transaction-queue',
              );
              await transaction.enqueueEnvelope(envelope);
              final failed = transaction.enqueueEnvelope(envelope);
              transformations[index](failed);
            }),
            throwsA(isA<Exception>()),
          );

          expect(await outbox.pendingCount(), 0);
        }
      },
    );

    test(
      'caught awaited nested failure still rolls back outer work',
      () async {
        late String runId;
        await expectLater(
          outbox.transaction((_) async {
            try {
              await outbox.transaction((_) async {
                runId = await store.createRun(
                  workflow: 'transaction.joined.caught',
                  params: const {},
                );
                throw Exception('caught nested failure');
              });
            } on Exception {
              // The scope remembers this failure for the rollback decision.
            }
          }),
          throwsException,
        );

        expect(await store.get(runId), isNull);
      },
    );

    test('an ended scope can transact on an independent data source', () async {
      final independentDataSource = createDataSource(
        connectionString: connectionString,
      );
      final independent = await PostgresConnections.openWithDataSource(
        independentDataSource,
        runMigrations: false,
      );
      addTearDown(() async {
        await independent.close();
        await independentDataSource.dispose();
      });

      final gate = Completer<void>();
      late Future<void> escaped;
      await outbox.transaction((_) async {
        escaped = (() async {
          await gate.future;
          await independent.runInTransaction((_) async {});
        })();
      });

      gate.complete();
      await escaped;
    });
  }, config: harness.config);
}
