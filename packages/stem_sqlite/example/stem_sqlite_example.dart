import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final databaseFile = File(
    '${Directory.systemTemp.path}/stem_sqlite_example.db',
  );

  final broker = await SqliteBroker.open(databaseFile);
  final backend = await SqliteResultBackend.open(databaseFile);

  final envelope = Envelope(name: 'example.task', args: const {});
  await broker.publish(envelope);

  final delivery = await broker
      .consume(RoutingSubscription.singleQueue(envelope.queue))
      .first;
  await broker.ack(delivery);

  await backend.set(
    envelope.id,
    TaskState.succeeded,
    meta: const {'example': true},
    attempt: envelope.attempt,
  );

  final status = await backend.get(envelope.id);
  print('Stored ${status?.id} with state ${status?.state}');

  await backend.close();
  await broker.close();
  if (await databaseFile.exists()) {
    await databaseFile.delete();
  }
}
