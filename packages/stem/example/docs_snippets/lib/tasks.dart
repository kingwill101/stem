// Task examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:convert';

import 'package:stem/stem.dart';

// #region tasks-register-in-memory
class EmailTask extends TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'anonymous';
    print('Emailing $to (attempt ${context.attempt})');
  }
}

final registry = SimpleTaskRegistry()..register(EmailTask());
// #endregion tasks-register-in-memory

// #region tasks-register-redis
class RedisEmailTask extends TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'email',
        maxRetries: 4,
        visibilityTimeout: Duration(seconds: 30),
        unique: true,
        uniqueFor: Duration(minutes: 5),
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    await sendEmailRemote(args);
  }
}

final redisRegistry = SimpleTaskRegistry()..register(RedisEmailTask());
// #endregion tasks-register-redis

// #region tasks-typed-definition
class InvoicePayload {
  const InvoicePayload({required this.invoiceId});
  final String invoiceId;
}

class PublishInvoiceTask extends TaskHandler<void> {
  static final definition = TaskDefinition<InvoicePayload, bool>(
    name: 'invoice.publish',
    encodeArgs: (payload) => {'invoiceId': payload.invoiceId},
    metadata: const TaskMetadata(description: 'Publishes invoices downstream'),
    defaultOptions: const TaskOptions(queue: 'billing'),
  );

  @override
  String get name => definition.name;

  @override
  TaskOptions get options => definition.defaultOptions;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final invoiceId = args['invoiceId'] as String;
    await publishInvoice(invoiceId);
  }
}

Future<void> runTypedDefinitionExample() async {
  final stem = Stem(
    broker: InMemoryBroker(),
    registry: SimpleTaskRegistry()..register(PublishInvoiceTask()),
    backend: InMemoryResultBackend(),
  );

  final taskId = await stem.enqueueCall(
    PublishInvoiceTask.definition(const InvoicePayload(invoiceId: 'inv_42')),
  );
  final result = await stem.waitForTask<bool>(taskId);
  if (result?.isSucceeded == true) {
    print('Invoice published');
  }
}
// #endregion tasks-typed-definition

// #region tasks-timeouts
const emailTimeoutOptions = TaskOptions(
  softTimeLimit: Duration(seconds: 15),
  hardTimeLimit: Duration(seconds: 30),
  acksLate: true,
);
// #endregion tasks-timeouts

// #region tasks-encoders-global
class Base64PayloadEncoder extends TaskPayloadEncoder {
  const Base64PayloadEncoder();

  @override
  Object? encode(Object? value) =>
      value is String ? base64Encode(utf8.encode(value)) : value;

  @override
  Object? decode(Object? stored) =>
      stored is String ? utf8.decode(base64Decode(stored)) : stored;
}

Future<void> configureEncoders() async {
  final app = await StemApp.inMemory(
    tasks: [EmailTask()],
    argsEncoder: const Base64PayloadEncoder(),
    resultEncoder: const Base64PayloadEncoder(),
    additionalEncoders: const [MyOtherEncoder()],
  );
  await app.worker.shutdown();
}
// #endregion tasks-encoders-global

// #region tasks-encoders-metadata
class EncodedTask extends TaskHandler<void> {
  @override
  String get name => 'encoded.task';

  @override
  TaskMetadata get metadata => const TaskMetadata(
        argsEncoder: Base64PayloadEncoder(),
        resultEncoder: Base64PayloadEncoder(),
      );

  @override
  TaskOptions get options => const TaskOptions();

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
// #endregion tasks-encoders-metadata

Future<void> sendEmailRemote(Map<String, Object?> args) async {}

Future<void> publishInvoice(String invoiceId) async {}

Future<void> sendEmailIsolate(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {}

class MyOtherEncoder extends TaskPayloadEncoder {
  const MyOtherEncoder();

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}

Future<void> main() async {
  final app = await StemApp.inMemory(tasks: [EmailTask()]);
  await app.start();

  final taskId = await app.stem.enqueue(
    'email.send',
    args: {'to': 'demo@example.com'},
  );
  final result = await app.stem.waitForTask<void>(
    taskId,
    timeout: const Duration(seconds: 5),
  );
  print('Email task state: ${result?.status.state}');

  await app.shutdown();
}
