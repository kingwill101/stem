import 'dart:async';
import 'dart:io';

import 'package:stem/src/brokers/postgres_broker.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres broker integration requires STEM_TEST_POSTGRES_URL',
      () {},
      skip:
          'Set STEM_TEST_POSTGRES_URL to run Postgres broker integration tests.',
    );
    return;
  }

  test('Postgres broker end-to-end', () async {
    final broker = await PostgresBroker.connect(
      connectionString,
      applicationName: 'stem-postgres-integration',
    );
    try {
      final queue = _uniqueQueue();
      final envelope = Envelope(
        name: 'integration.echo',
        args: const <String, Object?>{'value': 'hello'},
        queue: queue,
      );

      await broker.publish(envelope);
      expect(await broker.pendingCount(queue), 1);

      final delivery =
          await broker.consume(RoutingSubscription.singleQueue(queue)).first;
      expect(delivery.envelope.id, envelope.id);
      expect(delivery.envelope.queue, queue);

      await broker.deadLetter(delivery, reason: 'integration-test');

      final page = await broker.listDeadLetters(queue);
      expect(page.entries, hasLength(1));
      expect(page.entries.first.reason, 'integration-test');

      final dryRun = await broker.replayDeadLetters(
        queue,
        limit: 1,
        dryRun: true,
      );
      expect(dryRun.dryRun, isTrue);

      final replay = await broker.replayDeadLetters(queue, limit: 1);
      expect(replay.dryRun, isFalse);
      expect(replay.entries, hasLength(1));

      final redelivery =
          await broker.consume(RoutingSubscription.singleQueue(queue)).first;
      expect(redelivery.envelope.id, envelope.id);
      expect(redelivery.envelope.attempt, envelope.attempt + 1);

      await broker.ack(redelivery);
      expect(await broker.pendingCount(queue), 0);
      expect(await broker.purgeDeadLetters(queue), 0);
      await broker.purge(queue);
    } finally {
      await broker.close();
    }
  });

  test('Postgres broker honours priority ordering', () async {
    final broker = await PostgresBroker.connect(
      connectionString,
      applicationName: 'stem-postgres-priority-ordering',
    );
    try {
      final queue = _uniqueQueue();
      final lowPriority = Envelope(
        name: 'integration.postgres.low',
        args: const {'value': 'low'},
        queue: queue,
        priority: 1,
      );
      final highPriority = Envelope(
        name: 'integration.postgres.high',
        args: const {'value': 'high'},
        queue: queue,
        priority: 9,
      );

      await broker.publish(
        lowPriority,
        routing:
            RoutingInfo.queue(queue: queue, priority: lowPriority.priority),
      );
      await broker.publish(
        highPriority,
        routing:
            RoutingInfo.queue(queue: queue, priority: highPriority.priority),
      );

      final iterator = StreamIterator(
        broker.consume(
          RoutingSubscription.singleQueue(queue),
          prefetch: 2,
        ),
      );

      expect(await iterator.moveNext(), isTrue);
      final first = iterator.current;
      expect(first.envelope.id, highPriority.id);
      await broker.ack(first);

      expect(await iterator.moveNext(), isTrue);
      final second = iterator.current;
      expect(second.envelope.id, lowPriority.id);
      await broker.ack(second);
      await iterator.cancel();

      await broker.purge(queue);
    } finally {
      await broker.close();
    }
  });

  test('Postgres broadcast fan-out delivers to all subscribers', () async {
    final publisher = await PostgresBroker.connect(
      connectionString,
      applicationName: 'stem-postgres-broadcast-publisher',
    );
    final workerOneBroker = await PostgresBroker.connect(
      connectionString,
      applicationName: 'stem-postgres-broadcast-worker-1',
    );
    final workerTwoBroker = await PostgresBroker.connect(
      connectionString,
      applicationName: 'stem-postgres-broadcast-worker-2',
    );
    Future<void> safeClose(PostgresBroker broker) async {
      try {
        await broker.close();
      } catch (_) {}
    }

    try {
      final queue = _uniqueQueue();
      final channel = '${queue}_broadcast';
      final subscription = RoutingSubscription(
        queues: [queue],
        broadcastChannels: [channel],
      );

      final futureOne = workerOneBroker
          .consume(
            subscription,
            prefetch: 1,
            consumerGroup: 'group-$queue',
            consumerName: 'worker-one-$queue',
          )
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () {
        fail('worker-one timed out waiting for broadcast message');
      });
      final futureTwo = workerTwoBroker
          .consume(
            subscription,
            prefetch: 1,
            consumerGroup: 'group-$queue',
            consumerName: 'worker-two-$queue',
          )
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () {
        fail('worker-two timed out waiting for broadcast message');
      });

      final broadcast = Envelope(
        name: 'integration.postgres.broadcast',
        args: const {'value': 'fan-out'},
        queue: queue,
      );

      await publisher.publish(
        broadcast,
        routing: RoutingInfo.broadcast(channel: channel),
      );

      final results = await Future.wait([futureOne, futureTwo]);
      final firstDelivery = results[0];
      final secondDelivery = results[1];

      expect(firstDelivery.route.isBroadcast, isTrue);
      expect(secondDelivery.route.isBroadcast, isTrue);
      expect(firstDelivery.route.broadcastChannel, channel);
      expect(secondDelivery.route.broadcastChannel, channel);
      expect(firstDelivery.envelope.id, broadcast.id);
      expect(secondDelivery.envelope.id, broadcast.id);
      expect(firstDelivery.envelope.queue, channel);
      expect(secondDelivery.envelope.queue, channel);

      await workerOneBroker.ack(firstDelivery);
      await workerTwoBroker.ack(secondDelivery);

      await publisher.purge(queue);
    } finally {
      await safeClose(workerOneBroker);
      await safeClose(workerTwoBroker);
      await safeClose(publisher);
    }
  });

  test('CLI health succeeds against Postgres broker', () async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final exitCode = await runStemCli(
      ['health', '--skip-backend'],
      out: stdoutBuffer,
      err: stderrBuffer,
      environment: {
        'STEM_BROKER_URL': connectionString,
        'STEM_RESULT_BACKEND_URL': '',
      },
    );

    expect(exitCode, 0, reason: stderrBuffer.toString());
    expect(stdoutBuffer.toString(), contains('[ok]'));
    expect(stdoutBuffer.toString(), contains('Connected to $connectionString'));
  });
}

String _uniqueQueue() =>
    'integration-${DateTime.now().microsecondsSinceEpoch}-${_queueCounter++}';

var _queueCounter = 0;
