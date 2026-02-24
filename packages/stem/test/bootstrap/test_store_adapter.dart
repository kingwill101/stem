import 'package:stem/stem.dart';

class TestStoreAdapter implements StemStoreAdapter {
  const TestStoreAdapter({
    required this.scheme,
    this.adapterName = 'test-store-adapter',
    this.broker,
    this.backend,
    this.workflow,
    this.schedule,
    this.lock,
    this.revoke,
  });

  final String scheme;
  final String adapterName;
  final StemBrokerFactory? broker;
  final StemBackendFactory? backend;
  final WorkflowStoreFactory? workflow;
  final ScheduleStoreFactory? schedule;
  final LockStoreFactory? lock;
  final RevokeStoreFactory? revoke;

  @override
  String get name => adapterName;

  @override
  bool supports(Uri uri, StemStoreKind kind) => uri.scheme == scheme;

  @override
  StemBrokerFactory? brokerFactory(Uri uri) => broker;

  @override
  StemBackendFactory? backendFactory(Uri uri) => backend;

  @override
  WorkflowStoreFactory? workflowStoreFactory(Uri uri) => workflow;

  @override
  ScheduleStoreFactory? scheduleStoreFactory(Uri uri) => schedule;

  @override
  LockStoreFactory? lockStoreFactory(Uri uri) => lock;

  @override
  RevokeStoreFactory? revokeStoreFactory(Uri uri) => revoke;
}
