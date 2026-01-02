// Producer API examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region producer-in-memory
Future<void> enqueueInMemory() async {
  final app = await StemApp.inMemory(
    tasks: [
      FunctionTaskHandler<void>(
        name: 'hello.print',
        entrypoint: (context, args) async {
          final name = args['name'] as String? ?? 'friend';
          print('Hello $name');
          return null;
        },
      ),
    ],
  );

  final taskId = await app.stem.enqueue(
    'hello.print',
    args: {'name': 'Stem'},
  );

  print('Enqueued $taskId');
  await app.shutdown();
}
// #endregion producer-in-memory

// #region producer-redis
Future<void> enqueueWithRedis() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'reports.generate',
        entrypoint: (context, args) async {
          final id = args['reportId'] as String? ?? 'unknown';
          print('Queued report $id');
          return null;
        },
      ),
    );

  final stem = Stem(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    registry: registry,
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
  );

  await stem.enqueue(
    'reports.generate',
    args: {'reportId': 'monthly-2025-10'},
    options: const TaskOptions(queue: 'reports', maxRetries: 3),
    meta: {'requestedBy': 'finance'},
  );
}
// #endregion producer-redis

// #region producer-signed
Future<void> enqueueWithSigning() async {
  final config = StemConfig.fromEnvironment();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'billing.charge',
        entrypoint: (context, args) async {
          final customerId = args['customerId'] as String? ?? 'unknown';
          print('Queued charge for $customerId');
          return null;
        },
      ),
    );
  final stem = Stem(
    broker: await RedisStreamsBroker.connect(config.brokerUrl, tls: config.tls),
    registry: registry,
    backend: InMemoryResultBackend(),
    signer: PayloadSigner.maybe(config.signing),
  );

  await stem.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 4200},
    notBefore: DateTime.now().add(const Duration(minutes: 5)),
  );
}
// #endregion producer-signed

// #region producer-typed
class ReportPayload {
  const ReportPayload({required this.reportId});
  final String reportId;
}

class GenerateReportTask extends TaskHandler<String> {
  static final definition = TaskDefinition<ReportPayload, String>(
    name: 'reports.generate',
    encodeArgs: (payload) => {'reportId': payload.reportId},
    metadata: const TaskMetadata(description: 'Generate PDF reports'),
  );

  @override
  String get name => definition.name;

  @override
  TaskOptions get options => const TaskOptions(queue: 'reports');

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final id = args['reportId'] as String;
    return await generateReport(id);
  }
}

Future<void> enqueueTyped() async {
  final app = await StemApp.inMemory(tasks: [GenerateReportTask()]);
  await app.start();

  final call = GenerateReportTask.definition.call(
    const ReportPayload(reportId: 'monthly-2025-10'),
    options: const TaskOptions(priority: 5),
    headers: const {'x-requested-by': 'analytics'},
  );

  final taskId = await app.stem.enqueueCall(call);
  final result = await app.stem.waitForTask<String>(taskId);
  print(result?.value);
  await app.shutdown();
}
// #endregion producer-typed

// #region producer-encoders
class AesPayloadEncoder extends TaskPayloadEncoder {
  const AesPayloadEncoder();
  @override
  Object? encode(Object? value) => encrypt(value);
  @override
  Object? decode(Object? stored) => decrypt(stored);
}

Future<void> configureProducerEncoders() async {
  final app = await StemApp.inMemory(
    tasks: const [],
    argsEncoder: const AesPayloadEncoder(),
    resultEncoder: const JsonTaskPayloadEncoder(),
    additionalEncoders: const [CustomBinaryEncoder()],
  );

  await app.worker.shutdown();
}
// #endregion producer-encoders

Future<String> generateReport(String id) async => 'report-$id';

Object? encrypt(Object? value) => value;

Object? decrypt(Object? value) => value;

class CustomBinaryEncoder extends TaskPayloadEncoder {
  const CustomBinaryEncoder();

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}

Future<void> main() async {
  await enqueueInMemory();
}
