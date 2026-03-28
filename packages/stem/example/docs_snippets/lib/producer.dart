// Producer API examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region producer-in-memory
Future<void> enqueueInMemory() async {
  final client = await StemClient.inMemory(
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
  final app = await client.createApp();

  final taskId = await app.enqueue(
    'hello.print',
    args: {'name': 'Stem'},
  );
  await app.waitForTask<void>(taskId);

  print('Enqueued $taskId');
  await app.close();
  await client.close();
}
// #endregion producer-in-memory

// #region producer-redis
Future<void> enqueueWithRedis() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';

  final tasks = [
    FunctionTaskHandler<void>(
      name: 'reports.generate',
      entrypoint: (context, args) async {
        final id = args['reportId'] as String? ?? 'unknown';
        print('Queued report $id');
        return null;
      },
    ),
  ];

  final client = await StemClient.fromUrl(
    brokerUrl,
    adapters: const [StemRedisAdapter()],
    overrides: StemStoreOverrides(backend: '$brokerUrl/1'),
    tasks: tasks,
  );

  await client.enqueue(
    'reports.generate',
    args: {'reportId': 'monthly-2025-10'},
    options: const TaskOptions(queue: 'reports', maxRetries: 3),
    meta: {'requestedBy': 'finance'},
  );
  await client.close();
}
// #endregion producer-redis

// #region producer-signed
Future<void> enqueueWithSigning() async {
  final config = StemConfig.fromEnvironment();
  final tasks = [
    FunctionTaskHandler<void>(
      name: 'billing.charge',
      entrypoint: (context, args) async {
        final customerId = args['customerId'] as String? ?? 'unknown';
        print('Queued charge for $customerId');
        return null;
      },
    ),
  ];
  final client = await StemClient.fromUrl(
    config.brokerUrl,
    adapters: const [StemRedisAdapter()],
    overrides: const StemStoreOverrides(backend: 'memory://'),
    tasks: tasks,
    signer: PayloadSigner.maybe(config.signing),
  );

  await client.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 4200},
    notBefore: DateTime.now().add(const Duration(minutes: 5)),
  );
  await client.close();
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
    final id = args['reportId'] as String?;
    return generateReport(id!);
  }
}

Future<void> enqueueTyped() async {
  final client = await StemClient.inMemory(tasks: [GenerateReportTask()]);
  final app = await client.createApp();

  final result = await GenerateReportTask.definition.enqueueAndWait(
    app,
    const ReportPayload(reportId: 'monthly-2025-10'),
    options: const TaskOptions(priority: 5),
    headers: const {'x-requested-by': 'analytics'},
  );
  print(result?.value);
  await app.close();
  await client.close();
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
  final client = await StemClient.inMemory(
    tasks: const [],
    argsEncoder: const AesPayloadEncoder(),
    resultEncoder: const JsonTaskPayloadEncoder(),
    additionalEncoders: const [CustomBinaryEncoder()],
  );
  final app = await client.createApp();

  await app.close();
  await client.close();
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
