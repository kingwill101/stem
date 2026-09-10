import 'dart:async';

import 'package:flutter_stem_example/src/worker_workbench_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';

void main() {
  test(
    'publishes before wakeup and joins a mutation even if wakeup fails',
    () async {
      final backend = _Backend();
      final app = _App(backend);
      final wakeup = Completer<void>();
      final enteredWakeup = Completer<void>();
      final controller = WorkerWorkbenchController(
        app,
        requestWakeup: () async {
          expect(app.published, 2);
          enteredWakeup.complete();
          await wakeup.future;
          throw StateError('wakeup failed');
        },
      );
      final submission = controller.enqueue('mobile-routing', count: 2);
      final failure = expectLater(submission, throwsStateError);
      await enteredWakeup.future;
      var closed = false;
      final closing = controller.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      wakeup.complete();
      await failure;
      await closing;
      expect(backend.requests, hasLength(1));
      expect(controller.records, hasLength(2));
      expect(
        controller.records.every((r) => r.status.meta['worker'] == null),
        isTrue,
      );
    },
  );

  test('partial publication wakes and refreshes its saved prefix', () async {
    final backend = _Backend();
    final app = _App(backend)..failAfter = 1;
    var wakeups = 0;
    final controller = WorkerWorkbenchController(
      app,
      requestWakeup: () async => wakeups++,
    );
    addTearDown(controller.dispose);
    await expectLater(
      controller.enqueue('mobile-demo', count: 3),
      throwsStateError,
    );
    expect(wakeups, 1);
    expect(controller.records, hasLength(1));
    expect(controller.observationError, isNull);
  });

  test(
    'reads probe pages without changing persisted worker metadata',
    () async {
      final backend = _Backend();
      final controller = WorkerWorkbenchController(_App(backend));
      addTearDown(controller.dispose);
      backend.pages = {
        0: TaskStatusPage(
          items: [
            _record('probe-a', worker: 'general-b'),
            _record('photo', probe: false),
          ],
          nextOffset: 100,
        ),
        100: TaskStatusPage(items: [_record('probe-b')]),
      };
      await controller.refresh();
      expect(
        controller.records.map((r) => r.status.id),
        containsAll(['probe-a', 'probe-b']),
      );
      expect(controller.records, hasLength(2));
      expect(
        controller.records
            .singleWhere((r) => r.status.id == 'probe-a')
            .status
            .meta['worker'],
        'general-b',
      );
      expect(
        controller.records
            .singleWhere((r) => r.status.id == 'probe-b')
            .status
            .meta
            .containsKey('worker'),
        isFalse,
      );
      expect(backend.requests.map((r) => r.offset), [0, 100]);
      expect(
        backend.requests.every((r) => r.meta.containsKey('probeBatchId')),
        isTrue,
      );
      backend.error = StateError('offline');
      await controller.refresh();
      expect(controller.observationError, isStateError);
      expect(controller.records, hasLength(2));
      backend.error = null;
      await controller.refresh();
      expect(controller.observationError, isNull);
    },
  );

  test(
    'dispose joins in-flight observation and rejects later commands',
    () async {
      final backend = _Backend()..gate = Completer<void>();
      final controller = WorkerWorkbenchController(_App(backend));
      final read = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = controller.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      backend.gate!.complete();
      await read;
      await closing;
      expect(closed, isTrue);
      await expectLater(controller.enqueue('mobile-demo'), throwsStateError);
    },
  );
}

TaskStatusRecord _record(String id, {String? worker, bool probe = true}) {
  final now = DateTime.utc(2026);
  return TaskStatusRecord(
    status: TaskStatus(
      id: id,
      attempt: 0,
      state: TaskState.queued,
      meta: {if (probe) 'probeBatchId': 'batch', 'worker': ?worker},
    ),
    createdAt: now,
    updatedAt: now,
  );
}

class _App implements StemApp {
  _App(this.backend);
  @override
  final _Backend backend;
  int published = 0;
  int? failAfter;

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    if (published == failAfter) throw StateError('publish failed');
    published++;
    final id = 'saved-$published';
    backend.pages[0] = TaskStatusPage(
      items: [...?backend.pages[0]?.items, _record(id)],
    );
    return id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements ResultBackend {
  Map<int, TaskStatusPage> pages = {};
  final requests = <TaskStatusListRequest>[];
  Completer<void>? gate;
  Object? error;

  @override
  Future<TaskStatusPage> listTaskStatuses(TaskStatusListRequest request) async {
    requests.add(request);
    await gate?.future;
    if (error != null) throw error!;
    return pages[request.offset] ?? const TaskStatusPage(items: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
