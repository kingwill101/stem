import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/stem.dart'
    show TaskCall, TaskEnqueueOptions, TaskEnqueuer, TaskOptions;
import 'package:test/test.dart';

void main() {
  test('FlowContext sleep returns continueRun when resume elapsed', () {
    final clock = FakeWorkflowClock(DateTime.parse('2025-01-01T00:00:10Z'));
    final context = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'step',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      clock: clock,
      resumeData: {
        'type': 'sleep',
        'resumeAt': '2025-01-01T00:00:05Z',
      },
    );

    final control = context.sleep(const Duration(seconds: 5));
    expect(control.type, FlowControlType.continueRun);
  });

  test('FlowContext awaitEvent and takeControl consume directive', () {
    final context = FlowContext(
      workflow: 'demo',
      runId: 'run-2',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 1,
    );

    // Cascades aren't ideal here because we need the await semantics later.
    // ignore: cascade_invocations
    context.awaitEvent(
      'topic',
      deadline: DateTime.parse('2025-01-01T00:00:00Z'),
    );

    final first = context.takeControl();
    final second = context.takeControl();

    expect(first?.type, FlowControlType.waitForEvent);
    expect(second, isNull);
  });

  test(
    'FlowContext resume data is consumed and idempotency key derives scope',
    () {
      final context = FlowContext(
        workflow: 'demo',
        runId: 'run-3',
        stepName: 'step',
        params: const {},
        previousResult: null,
        stepIndex: 2,
        iteration: 1,
        resumeData: {'resume': true},
      );

      expect(context.takeResumeData(), isNotNull);
      expect(context.takeResumeData(), isNull);

      expect(
        context.idempotencyKey(),
        'demo/run-3/step#1',
      );
      expect(context.idempotencyKey('custom'), 'demo/run-3/custom');
    },
  );

  test(
    'startWithContext throws when child workflow support is unavailable',
    () {
      final context = FlowContext(
        workflow: 'demo',
        runId: 'run-4',
        stepName: 'spawn',
        params: const {},
        previousResult: null,
        stepIndex: 0,
      );
      final childRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'child.flow',
        encodeParams: (params) => params,
      );

      expect(
        () => childRef.startWithContext(context, const {'value': 'x'}),
        throwsStateError,
      );
    },
  );

  test(
    'startAndWaitWithContext throws when child workflow support is unavailable',
    () {
      final context = FlowContext(
        workflow: 'demo',
        runId: 'run-5',
        stepName: 'spawn',
        params: const {},
        previousResult: null,
        stepIndex: 0,
      );
      final childRef = WorkflowRef<Map<String, Object?>, String>(
        name: 'child.flow',
        encodeParams: (params) => params,
      );

      expect(
        () => childRef.startAndWaitWithContext(
          context,
          const {'value': 'x'},
        ),
        throwsStateError,
      );
    },
  );

  test('FlowContext.enqueue delegates to the configured enqueuer', () async {
    final enqueuer = _RecordingEnqueuer();
    final context = FlowContext(
      workflow: 'demo',
      runId: 'run-6',
      stepName: 'dispatch',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      enqueuer: enqueuer,
    );

    final taskId = await context.enqueue(
      'tasks.child',
      args: const {'value': 42},
      meta: const {'source': 'flow'},
    );

    expect(taskId, equals('recorded-1'));
    expect(enqueuer.lastName, equals('tasks.child'));
    expect(enqueuer.lastArgs, equals({'value': 42}));
    expect(enqueuer.lastMeta, containsPair('source', 'flow'));
  });

  test('FlowContext.enqueue throws when no enqueuer is configured', () {
    final context = FlowContext(
      workflow: 'demo',
      runId: 'run-7',
      stepName: 'dispatch',
      params: const {},
      previousResult: null,
      stepIndex: 0,
    );

    expect(() => context.enqueue('tasks.child'), throwsStateError);
  });
}

class _RecordingEnqueuer implements TaskEnqueuer {
  String? lastName;
  Map<String, Object?>? lastArgs;
  Map<String, Object?>? lastMeta;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastName = name;
    lastArgs = Map<String, Object?>.from(args);
    lastMeta = Map<String, Object?>.from(meta);
    return 'recorded-1';
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      meta: call.meta,
      options: call.resolveOptions(),
      enqueueOptions: enqueueOptions ?? call.enqueueOptions,
    );
  }
}
