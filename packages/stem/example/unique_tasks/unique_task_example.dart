import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

class SendDigestTask implements TaskHandler<void> {
  @override
  String get name => 'email.sendDigest';

  // #region unique-task-options
  @override
  TaskOptions get options => const TaskOptions(
    queue: 'email',
    unique: true,
    uniqueFor: Duration(minutes: 15),
    maxRetries: 2,
  );
  // #endregion unique-task-options

  @override
  TaskMetadata get metadata => const TaskMetadata(
    description: 'Send a user digest email once per interval',
    idempotent: true,
  );

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final userId = args['userId'];
    print(
      '[worker] sending digest for user $userId (attempt ${context.attempt})',
    );
  }
}

Future<void> main() async {
  // #region unique-task-coordinator
  final dbFile = File('unique_tasks.sqlite');
  if (!dbFile.existsSync()) {
    dbFile.createSync(recursive: true);
  }

  final broker = InMemoryBroker();
  final backend = await SqliteResultBackend.open(
    dbFile,
    defaultTtl: const Duration(hours: 1),
    groupDefaultTtl: const Duration(hours: 1),
  );
  final lockStore = InMemoryLockStore();
  final coordinator = UniqueTaskCoordinator(
    lockStore: lockStore,
    defaultTtl: const Duration(minutes: 5),
  );
  // #endregion unique-task-coordinator

  final registry = SimpleTaskRegistry()..register(SendDigestTask());

  // #region unique-task-stem-worker
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    uniqueTaskCoordinator: coordinator,
  );
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    uniqueTaskCoordinator: coordinator,
    queue: 'email',
    consumerName: 'unique-worker',
  );
  // #endregion unique-task-stem-worker

  unawaited(worker.start());

  // #region unique-task-enqueue
  final firstId = await stem.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
    options: const TaskOptions(
      queue: 'email',
      unique: true,
      uniqueFor: Duration(minutes: 15),
    ),
  );
  // #endregion unique-task-enqueue
  final secondId = await stem.enqueue(
    'email.sendDigest',
    args: const {'userId': 42},
    options: const TaskOptions(
      queue: 'email',
      unique: true,
      uniqueFor: Duration(minutes: 15),
    ),
  );

  print('first enqueue id:  $firstId');
  print('second enqueue id: $secondId (dup is re-used)');

  await Future<void>.delayed(const Duration(seconds: 2));

  await worker.shutdown();
  broker.dispose();
  await backend.close();
}
