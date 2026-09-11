import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/main.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:flutter_stem_example/src/photo_batch.dart';
import 'package:flutter_stem_example/src/queue_monitor_page.dart';
import 'package:flutter_stem_example/src/widgets/job_card.dart';
import 'package:flutter_stem_example/src/widgets/metric_tile.dart';
import 'package:stem/memory.dart';
import 'package:stem/stem.dart' show Envelope, RoutingInfo;
import 'package:stem_flutter/stem_flutter.dart';

class GatedPhotoBroker extends InMemoryBroker {
  final entered = Completer<void>();
  final release = Completer<void>();
  int publications = 0;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    publications++;
    entered.complete();
    await release.future;
    await super.publish(envelope, routing: routing);
  }
}

// Frame settling does not wait for the worker's asynchronous lifecycle. Give
// real event-loop work and fake-clock task/poll timers a chance to finish, but
// always require the observable outcome rather than sleeping a fixed duration.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() complete, {
  required String reason,
}) async {
  final elapsed = Stopwatch()..start();
  while (!complete() && elapsed.elapsed < const Duration(seconds: 30)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(complete(), isTrue, reason: reason);
}

void main() {
  late Directory output;
  setUp(() async {
    output = await Directory.systemTemp.createTemp('photo_widget_');
  });
  tearDown(() async {
    await output.delete(recursive: true);
  });
  const tiny = PhotoWorkload(label: 'Test', count: 2, width: 96, height: 64);

  testWidgets('old demo results are retained but not counted as photos', (
    tester,
  ) async {
    final app = await StemApp.inMemory(
      module: demoModule,
      workerConfig: StemFlutter.defaultWorkerConfig,
    );
    await app.backend.set(
      'legacy',
      TaskState.succeeded,
      payload: 'Completed an earlier sleep task',
    );
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => app,
        outputDirectory: output.path,
        workload: tiny,
        runLocalWorker: false,
      ),
    );
    await tester.pumpAndSettle();
    final metric = tester.widget<MetricTile>(
      find.byWidgetPredicate(
        (widget) => widget is MetricTile && widget.label == 'photos tracked',
      ),
    );
    expect(metric.value, '0');
    expect(find.byType(JobCard), findsNothing);
    expect(await app.getTaskStatus('legacy'), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(app.shutdown);
  });

  testWidgets('root waits for pending commit before closing stores', (
    tester,
  ) async {
    final broker = GatedPhotoBroker();
    var closed = false;
    var wakeups = 0;
    final app = await StemApp.create(
      module: demoModule,
      broker: StemBrokerFactory(
        create: () async => broker,
        dispose: (_) async {
          await broker.close();
          closed = true;
        },
      ),
      backend: StemBackendFactory.inMemory(),
      workerConfig: StemFlutter.defaultWorkerConfig,
    );
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => app,
        runLocalWorker: false,
        outputDirectory: output.path,
        workload: tiny,
        startupWakeup: () async {
          wakeups++;
        },
        requestWakeup: () async {
          wakeups++;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare 2 photos'));
    await tester.pump();
    expect(broker.entered.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(closed, isFalse);
    broker.release.complete();
    await pumpUntil(
      tester,
      () => closed,
      reason: 'Root must join the commit before disposing its broker.',
    );
    expect(broker.publications, 1);
    expect(wakeups, 2, reason: 'Startup plus the one committed photo.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('360px phone with large text stays scrollable', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await StemApp.create(
      module: demoModule,
      broker: StemBrokerFactory.inMemory(),
      backend: StemBackendFactory.inMemory(),
      workerConfig: StemFlutter.defaultWorkerConfig,
    );
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => app,
        runLocalWorker: false,
        outputDirectory: output.path,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Prepare 6 photos'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(app.shutdown);
  });

  testWidgets('legacy and missing photo artifacts have safe details', (
    tester,
  ) async {
    final now = DateTime.now();
    for (final payload in <Object>[
      'Completed legacy job',
      {
        'thumbnailPath': '${output.path}/missing.jpg',
        'previewPath': '${output.path}/missing.jpg',
      },
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobCard(
              job: TaskStatusRecord(
                status: TaskStatus(
                  id: 'legacy',
                  state: TaskState.succeeded,
                  attempt: 1,
                  payload: payload,
                ),
                createdAt: now,
                updatedAt: now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(JobCard));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'scheduler mode never consumes and wakeup retry never republishes',
    (tester) async {
      final app = await StemApp.create(
        module: demoModule,
        broker: StemBrokerFactory.inMemory(),
        backend: StemBackendFactory.inMemory(),
        workerConfig: StemFlutter.defaultWorkerConfig,
      );
      var wakeups = 0;
      var cancellations = 0;
      var permissionRequests = 0;
      var failScheduling = true;
      await tester.pumpWidget(
        StemFlutterExampleApp(
          createApp: () async => app,
          outputDirectory: output.path,
          workload: tiny,
          runLocalWorker: false,
          startupWakeup: () async {
            wakeups++;
            if (failScheduling) throw StateError('scheduler unavailable');
          },
          requestWakeup: () async {
            wakeups++;
            if (failScheduling) throw StateError('scheduler unavailable');
          },
          cancelWakeups: () async {
            cancellations++;
          },
          requestNotificationPermission: () async {
            permissionRequests++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        wakeups,
        1,
        reason: 'Startup reconciles previously persisted work.',
      );
      expect(app.isStarted, isFalse);
      expect(permissionRequests, 0, reason: 'Startup must never prompt.');
      await tester.ensureVisible(find.text('Enable status notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable status notifications'));
      await tester.pumpAndSettle();
      expect(permissionRequests, 1);
      expect(find.textContaining('Photo work still runs'), findsOneWidget);
      await tester.ensureVisible(find.text('Prepare 2 photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare 2 photos'));
      await tester.pumpAndSettle();
      expect(wakeups, 2);
      expect(find.textContaining('is queued, but wakeup'), findsOneWidget);
      expect(await app.broker.pendingCount('mobile-demo'), 2);
      await tester.pump(const Duration(seconds: 10));
      expect(await app.broker.pendingCount('mobile-demo'), 2);
      expect(app.isStarted, isFalse);
      failScheduling = false;
      await tester.ensureVisible(find.text('Retry wakeup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry wakeup'));
      await tester.pumpAndSettle();
      expect(wakeups, 3);
      expect(await app.broker.pendingCount('mobile-demo'), 2);
      await tester.ensureVisible(find.text('Cancel native wakeups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel native wakeups'));
      await tester.pumpAndSettle();
      expect(cancellations, 1);
      expect(await app.broker.pendingCount('mobile-demo'), 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(app.shutdown);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pushes a typed job and root closes its resources', (
    tester,
  ) async {
    var brokerClosed = false;
    var backendClosed = false;
    final memoryBroker = StemBrokerFactory.inMemory();
    final memoryBackend = StemBackendFactory.inMemory();
    final app = await StemApp.create(
      module: demoModule,
      broker: StemBrokerFactory(
        create: memoryBroker.create,
        dispose: (broker) async {
          await memoryBroker.dispose(broker);
          brokerClosed = true;
        },
      ),
      backend: StemBackendFactory(
        create: memoryBackend.create,
        dispose: (backend) async {
          await memoryBackend.dispose(backend);
          backendClosed = true;
        },
      ),
      workerConfig: StemFlutter.defaultWorkerConfig,
    );
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => app,
        outputDirectory: output.path,
        workload: const PhotoWorkload(
          label: 'Test',
          count: 1,
          width: 96,
          height: 64,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Photo Lab'), findsOneWidget);
    expect(find.text('Prepare 1 photos'), findsOneWidget);
    expect(app.isStarted, isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Prepare 1 photos'));
    await pumpUntil(
      tester,
      () => tester
          .widget<QueueMonitorPage>(find.byType(QueueMonitorPage))
          .monitor!
          .jobs
          .any((job) => job.status.state == TaskState.succeeded),
      reason: 'The real worker should complete the job queued by the button.',
    );
    final job = tester
        .widget<QueueMonitorPage>(find.byType(QueueMonitorPage))
        .monitor!
        .jobs
        .single;
    expect(job.status.meta['label'], 'Test');
    final payload = job.status.payload! as Map;
    expect(
      await tester.runAsync(
        () => File(payload['previewPath'] as String).exists(),
      ),
      isTrue,
    );
    final result = await app.waitForTask<Map<String, Object?>>(job.status.id);
    expect(result?.value, job.status.payload);
    await tester.scrollUntilVisible(find.byType(JobCard), 250);
    await tester.tap(find.byType(JobCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('sha256:'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(brokerClosed, isFalse);
    expect(backendClosed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpUntil(
      tester,
      () => brokerClosed && backendClosed,
      reason: 'Root disposal must close both owned factories, not just stop.',
    );
    expect(app.isStarted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closes an app created after root disposal', (tester) async {
    final created = Completer<StemApp>();
    var brokerClosed = false;
    final memoryBroker = StemBrokerFactory.inMemory();
    final app = await StemApp.create(
      module: demoModule,
      broker: StemBrokerFactory(
        create: memoryBroker.create,
        dispose: (broker) async {
          await memoryBroker.dispose(broker);
          brokerClosed = true;
        },
      ),
      backend: StemBackendFactory.inMemory(),
      workerConfig: StemFlutter.defaultWorkerConfig,
    );
    await tester.pumpWidget(
      StemFlutterExampleApp(createApp: () => created.future),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    created.complete(app);
    await tester.pumpAndSettle();

    expect(brokerClosed, isTrue);
    expect(app.isStarted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows startup failures without opening platform stores', (
    tester,
  ) async {
    await tester.pumpWidget(
      StemFlutterExampleApp(
        createApp: () async => throw StateError('test startup failure'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('test startup failure'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
