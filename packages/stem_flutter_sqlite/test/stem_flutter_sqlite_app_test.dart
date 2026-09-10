import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late StemFlutterStorageLayout layout;
  final task = TaskDefinition<int, int>(
    name: 'increment',
    encodeArgs: (value) => {'value': value},
    decodeArgs: (args) => args['value']! as int,
    defaultOptions: const TaskOptions(queue: 'mobile'),
  );
  final module = StemModule(
    tasks: [task.handler(entrypoint: (context, value) async => value + 1)],
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('stem_flutter_app_');
    layout = await StemFlutterStorageLayout.forRoot(sandbox);
  });
  tearDown(() => sandbox.delete(recursive: true));

  test('core factories support a caller-owned Ormed data source', () async {
    await StemFlutterSqlite.initialize();
    final dataSource = buildOrmRegistry().sqliteFileDataSource(
      path: '${sandbox.path}/application.sqlite',
    );
    addTearDown(dataSource.dispose);
    final app = await StemFlutter.createApp(
      module: module,
      broker: StemBrokerFactory(
        create: () => SqliteBroker.fromDataSource(dataSource),
        dispose: (broker) => broker.close(),
      ),
      backend: StemBackendFactory(
        create: () => SqliteResultBackend.fromDataSource(dataSource),
        dispose: (backend) => backend.close(),
      ),
    );
    addTearDown(app.shutdown);
    await app.start();
    final id = await task.enqueue(app, 3);
    expect(
      (await task.waitFor(
        app,
        id,
        timeout: const Duration(seconds: 10),
      ))?.value,
      4,
    );

    await app.shutdown();
    expect(dataSource.isInitialized, isTrue);
    final observer = await SqliteResultBackend.fromDataSource(dataSource);
    addTearDown(observer.close);
    expect((await observer.get(id))?.state, TaskState.succeeded);
  });

  test(
    'default setup resolves app storage and returns a normal StemApp',
    () async {
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(sandbox.path);
      addTearDown(() => PathProviderPlatform.instance = previous);

      final app = await StemFlutterSqlite.createApp(module: module);
      addTearDown(app.shutdown);
      expect(app, isA<StemApp>());
      expect(app.isStarted, isFalse);
      expect(
        File('${sandbox.path}/stem_flutter/broker.sqlite').existsSync(),
        isTrue,
      );
      expect(
        File('${sandbox.path}/stem_flutter/backend.sqlite').existsSync(),
        isTrue,
      );
      final id = await task.enqueue(app, 41);
      expect(await app.broker.pendingCount('mobile'), 1);
      await app.start();
      expect(
        (await app.waitForTask<int>(
          id,
          timeout: const Duration(seconds: 10),
        ))?.value,
        42,
      );
      expect((await app.getTaskStatus(id))?.state, TaskState.succeeded);
    },
  );

  test(
    'queued tasks and completed results survive closing and reopening',
    () async {
      final producer = await StemFlutterSqlite.createApp(
        layout: layout,
        module: module,
      );
      addTearDown(producer.shutdown);
      final id = await producer.enqueueCall(task.buildCall(9));
      await producer.shutdown();

      final consumer = await StemFlutterSqlite.createApp(
        layout: layout,
        module: module,
      );
      addTearDown(consumer.shutdown);
      expect(await consumer.broker.pendingCount('mobile'), 1);
      await consumer.start();
      expect(
        (await consumer.waitForTask<int>(
          id,
          timeout: const Duration(seconds: 10),
        ))?.value,
        10,
      );
      await consumer.shutdown();

      final observer = await StemFlutterSqlite.createApp(
        layout: layout,
        module: module,
      );
      addTearDown(observer.shutdown);
      expect(observer.isStarted, isFalse);
      expect((await observer.getTaskStatus(id))?.state, TaskState.succeeded);
      expect(
        (await observer.waitForTask<int>(
          id,
          timeout: const Duration(seconds: 2),
        ))?.value,
        10,
      );
    },
  );

  test(
    'one namespace config applies to both producer and worker stores',
    () async {
      final first = await StemFlutterSqlite.createApp(
        layout: layout,
        module: module,
        storage: const StemFlutterSqliteConfig(namespace: 'first'),
      );
      addTearDown(first.shutdown);
      final id = await task.enqueue(first, 2);
      await first.shutdown();

      final second = await StemFlutterSqlite.createApp(
        layout: layout,
        module: module,
        storage: const StemFlutterSqliteConfig(namespace: 'second'),
      );
      addTearDown(second.shutdown);
      expect(await second.broker.pendingCount('mobile'), 0);
      expect(await second.getTaskStatus(id), isNull);
      await second.shutdown();

      final reopened = await StemFlutterSqlite.createApp(
        layout: layout,
        module: module,
        storage: const StemFlutterSqliteConfig(namespace: 'first'),
      );
      addTearDown(reopened.shutdown);
      await reopened.start();
      expect(
        (await reopened.waitForTask<int>(
          id,
          timeout: const Duration(seconds: 10),
        ))?.value,
        3,
      );
    },
  );
}
