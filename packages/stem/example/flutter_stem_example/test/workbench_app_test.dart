import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/app.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:flutter_stem_example/src/workflow_workbench_page.dart';
import 'package:flutter_stem_example/src/worker_workbench_page.dart';
import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

void main() {
  testWidgets('background Workers tab does not start UI consumers', (
    tester,
  ) async {
    var brokerClosed = false;
    final app = (await tester.runAsync(
      () => StemApp.create(
        module: demoModule,
        workerConfig: const StemWorkerConfig(
          queue: queueName,
          consumerName: 'general-a',
          lifecycle: WorkerLifecycleConfig(installSignalHandlers: false),
        ),
        broker: StemBrokerFactory(
          create: () async => InMemoryBroker(),
          dispose: (broker) async {
            await broker.close();
            brokerClosed = true;
          },
        ),
        backend: StemBackendFactory.inMemory(),
      ),
    ))!;
    var closed = false;
    addTearDown(() async {
      if (!closed) {
        await tester.runAsync(
          () => app.close().timeout(const Duration(seconds: 2)),
        );
      }
    });
    var factoriesCalled = 0;
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => app,
        runLocalWorker: false,
        outputDirectory: '/unused-workbench-test-photos',
        createAdditionalWorkers: () async {
          factoriesCalled++;
          throw StateError('UI must not create headless consumers');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workers').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkerWorkbenchPage), findsOneWidget);
    expect(factoriesCalled, 0);
    expect(app.isStarted, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 100 && !brokerClosed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(brokerClosed, isTrue);
    await tester.runAsync(app.close);
    closed = true;
  });

  testWidgets('tab switches preserve publishers and root-owned stores', (
    tester,
  ) async {
    final app = (await tester.runAsync(
      () => StemApp.inMemory(
        module: demoModule,
        workerConfig: const StemWorkerConfig(
          queue: queueName,
          concurrency: 1,
          lifecycle: WorkerLifecycleConfig(installSignalHandlers: false),
        ),
      ),
    ))!;
    var closed = false;
    addTearDown(() async {
      if (!closed) {
        await tester.runAsync(
          () => app.close().timeout(const Duration(seconds: 2)),
        );
      }
    });
    var workflowStoreClosed = 0;
    var startupWakeups = 0;
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => app,
        runLocalWorker: false,
        outputDirectory: '/unused-workbench-test-photos',
        startupWakeup: () async => startupWakeups++,
        attachWorkflows: (core) => StemWorkflowApp.create(
          stemApp: core,
          workerConfig: const StemWorkerConfig(queue: queueName),
          storeFactory: WorkflowStoreFactory(
            create: () async => InMemoryWorkflowStore(),
            dispose: (store) async {
              workflowStoreClosed++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> enqueueSingle() async {
      final button = find.byKey(const ValueKey('push-single-photo'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await enqueueSingle();
    expect(await app.broker.pendingCount(queueName), 1);
    await tester.tap(find.text('Workflows').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkflowWorkbenchPage), findsOneWidget);
    expect(workflowStoreClosed, 0);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await enqueueSingle();
    expect(await app.broker.pendingCount(queueName), 2);
    expect(startupWakeups, 1);
    expect(workflowStoreClosed, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 100 && workflowStoreClosed == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(workflowStoreClosed, 1);
    await tester.runAsync(app.close);
    closed = true;
  });
}
