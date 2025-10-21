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
    addTearDown(() => broker.close());

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
