// Signing examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

class BillingTask extends TaskHandler<void> {
  @override
  String get name => 'billing.charge';

  @override
  TaskOptions get options => const TaskOptions(queue: 'billing');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final customerId = args['customerId'] as String? ?? 'unknown';
    print('Charging $customerId');
  }
}

// #region signing-producer-signer
PayloadSigner? buildSigningSigner() {
  final config = StemConfig.fromEnvironment();
  return PayloadSigner.maybe(config.signing);
}
// #endregion signing-producer-signer

// #region signing-producer-stem
Stem buildSignedProducer(
  Broker broker,
  ResultBackend backend,
  TaskRegistry registry,
  PayloadSigner? signer,
) {
  return Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: signer,
  );
}
// #endregion signing-producer-stem

// #region signing-worker-signer
PayloadSigner? buildWorkerSigner() {
  final config = StemConfig.fromEnvironment();
  return PayloadSigner.maybe(config.signing);
}
// #endregion signing-worker-signer

// #region signing-worker-wire
Worker buildSignedWorker(
  Broker broker,
  ResultBackend backend,
  TaskRegistry registry,
  PayloadSigner? signer,
) {
  return Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: signer,
    queue: 'billing',
    consumerName: 'billing-worker',
  );
}
// #endregion signing-worker-wire

// #region signing-beat-signer
PayloadSigner? buildSchedulerSigner() {
  final config = StemConfig.fromEnvironment();
  return PayloadSigner.maybe(config.signing);
}
// #endregion signing-beat-signer

// #region signing-beat-wire
Beat buildSignedBeat(
  Broker broker,
  ScheduleStore store,
  LockStore lockStore,
  PayloadSigner? signer,
) {
  return Beat(
    broker: broker,
    store: store,
    lockStore: lockStore,
    signer: signer,
  );
}
// #endregion signing-beat-wire

// #region signing-rotation-producer-active-key
void logActiveSigningKey() {
  final config = StemConfig.fromEnvironment();
  print('Active signing key: ${config.signing.activeKeyId}');
}
// #endregion signing-rotation-producer-active-key

// #region signing-rotation-producer-enqueue
Future<void> enqueueDuringRotation(Stem stem) async {
  await stem.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 4200},
  );
}
// #endregion signing-rotation-producer-enqueue

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()..register(BillingTask());
  final signer = buildSigningSigner();

  final stem = buildSignedProducer(broker, backend, registry, signer);
  await stem.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_demo', 'amount': 2500},
  );

  final worker = buildSignedWorker(broker, backend, registry, signer);
  unawaited(worker.start());
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await worker.shutdown();

  final beat = buildSignedBeat(
    broker,
    InMemoryScheduleStore(),
    InMemoryLockStore(),
    buildSchedulerSigner(),
  );
  await beat.start();
  await beat.stop();

  logActiveSigningKey();
  await enqueueDuringRotation(stem);

  await broker.close();
  await backend.close();
}
