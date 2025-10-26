import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('stem_sqlite_broker_test');
    dbFile = File('${tempDir.path}/broker.db');
  });

  tearDown(() async {
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  Future<SqliteBroker> createBroker() {
    return SqliteBroker.open(
      dbFile,
      defaultVisibilityTimeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 25),
      sweeperInterval: const Duration(milliseconds: 50),
    );
  }

  test('publishes, consumes, and acknowledges jobs', () async {
    final broker = await createBroker();
    addTearDown(broker.close);

    final envelope = Envelope(
      name: 'test.task',
      args: const {},
      queue: 'default',
    );
    await broker.publish(envelope);

    final delivery = await broker
        .consume(RoutingSubscription.singleQueue('default'))
        .first;
    expect(delivery.envelope.id, envelope.id);
    await broker.ack(delivery);

    final pending = await broker.pendingCount('default');
    expect(pending, 0);
  });

  test('nack without requeue moves job to dead letters', () async {
    final broker = await createBroker();
    addTearDown(broker.close);

    final envelope = Envelope(
      name: 'test.task',
      args: const {},
      queue: 'critical',
    );
    await broker.publish(envelope);

    final delivery = await broker
        .consume(RoutingSubscription.singleQueue('critical'))
        .first;
    await broker.nack(delivery, requeue: false);

    final page = await broker.listDeadLetters('critical', limit: 10);
    expect(page.entries, hasLength(1));
    expect(page.entries.first.envelope.id, envelope.id);
  });

  test('replays dead letters back onto the queue', () async {
    final broker = await createBroker();
    addTearDown(broker.close);

    final envelope = Envelope(name: 'test.task', args: const {}, queue: 'dlq');
    await broker.publish(envelope);

    final delivery = await broker
        .consume(RoutingSubscription.singleQueue('dlq'))
        .first;
    await broker.deadLetter(delivery, reason: 'failure');

    final result = await broker.replayDeadLetters('dlq', limit: 10);
    expect(result.entries, hasLength(1));
    expect(result.entries.first.envelope.id, envelope.id);

    final replayed = await broker
        .consume(RoutingSubscription.singleQueue('dlq'))
        .first;
    expect(replayed.envelope.id, envelope.id);
    await broker.ack(replayed);
  });

  test('sweeper releases expired leases', () async {
    final broker = await createBroker();
    addTearDown(broker.close);

    final envelope = Envelope(
      name: 'test.task',
      args: const {},
      queue: 'sweeper',
    );
    await broker.publish(envelope);

    final subscription = broker.consume(
      RoutingSubscription.singleQueue('sweeper'),
    );
    await subscription.first;

    // Allow lease to expire and trigger maintenance.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await broker.runMaintenance();

    final pendingAfter = await broker.pendingCount('sweeper');
    expect(pendingAfter, 1);

    final replay = await broker
        .consume(RoutingSubscription.singleQueue('sweeper'))
        .first;
    expect(replay.envelope.id, envelope.id);
  });
}
