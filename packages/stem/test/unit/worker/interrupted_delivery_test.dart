import 'package:stem/memory.dart';
import 'package:stem/stable.dart' as stable;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('recovery options round trip and remain available from stable', () {
    const options = stable.TaskOptions(
      recoveryPolicy: stable.TaskRecoveryPolicy.retry,
    );
    expect(
      TaskOptions.fromJson(
        options.toJson(),
      ).copyWith(queue: 'other').recoveryPolicy,
      TaskRecoveryPolicy.retry,
    );
    expect(TaskOptions.fromJson({}).recoveryPolicy, TaskRecoveryPolicy.replay);
    for (final policy in TaskRecoveryPolicy.values) {
      expect(
        TaskOptions.fromJson({'recoveryPolicy': policy}).recoveryPolicy,
        policy,
      );
      expect(
        TaskOptions.fromJson({'recoveryPolicy': policy.name}).recoveryPolicy,
        policy,
      );
    }
    expect(
      TaskOptions.fromJson({'recoveryPolicy': 'unknown'}).recoveryPolicy,
      TaskRecoveryPolicy.replay,
    );
    expect(
      options
          .copyWith(recoveryPolicy: TaskRecoveryPolicy.replay)
          .recoveryPolicy,
      TaskRecoveryPolicy.replay,
    );
    expect(
      const stable.TaskInterruptedException(taskId: 'task', attempt: 0),
      isA<Exception>(),
    );
  });

  for (final scenario in [
    for (final group in [false, true])
      for (final replay in [false, true])
        (
          name: 'limited recovery group=$group replay=$replay',
          state: TaskState.running,
          attempt: 0,
          options: TaskOptions(
            recoveryPolicy: replay
                ? TaskRecoveryPolicy.replay
                : TaskRecoveryPolicy.retry,
            rateLimit: group ? null : const RateLimit.perSecond(1),
            groupRateLimit: group ? const RateLimit.perSecond(1) : null,
          ),
          executions: replay ? [0] : <int>[],
          signals: 1,
          terminal: replay ? TaskState.succeeded : TaskState.failed,
        ),
    (
      name: 'default replay',
      state: TaskState.running,
      attempt: 0,
      options: const TaskOptions(),
      executions: [0],
      signals: 1,
      terminal: TaskState.succeeded,
    ),
    (
      name: 'retry uses next attempt',
      state: TaskState.running,
      attempt: 0,
      options: const TaskOptions(
        recoveryPolicy: TaskRecoveryPolicy.retry,
        maxRetries: 1,
        retryPolicy: TaskRetryPolicy(
          defaultDelay: Duration(milliseconds: 20),
          jitter: false,
          autoRetryFor: [TaskInterruptedException],
        ),
      ),
      executions: [1],
      signals: 1,
      terminal: TaskState.succeeded,
    ),
    (
      name: 'retry exhausted',
      state: TaskState.running,
      attempt: 0,
      options: const TaskOptions(recoveryPolicy: TaskRecoveryPolicy.retry),
      executions: <int>[],
      signals: 1,
      terminal: TaskState.failed,
    ),
    (
      name: 'retry filter excludes interruption',
      state: TaskState.running,
      attempt: 0,
      options: const TaskOptions(
        recoveryPolicy: TaskRecoveryPolicy.retry,
        maxRetries: 2,
        rateLimit: RateLimit.perSecond(1),
        retryPolicy: TaskRetryPolicy(
          dontAutoRetryFor: [TaskInterruptedException],
        ),
      ),
      executions: <int>[],
      signals: 1,
      terminal: TaskState.failed,
    ),
    (
      name: 'retry allowlist does not include interruption',
      state: TaskState.running,
      attempt: 0,
      options: const TaskOptions(
        recoveryPolicy: TaskRecoveryPolicy.retry,
        maxRetries: 2,
        retryPolicy: TaskRetryPolicy(autoRetryFor: [StateError]),
      ),
      executions: <int>[],
      signals: 1,
      terminal: TaskState.failed,
    ),
    (
      name: 'ordinary retry',
      state: TaskState.retried,
      attempt: 1,
      options: const TaskOptions(recoveryPolicy: TaskRecoveryPolicy.retry),
      executions: [1],
      signals: 0,
      terminal: TaskState.succeeded,
    ),
    (
      name: 'previous running attempt',
      state: TaskState.running,
      attempt: 1,
      options: const TaskOptions(recoveryPolicy: TaskRecoveryPolicy.retry),
      executions: [1],
      signals: 0,
      terminal: TaskState.succeeded,
    ),
    (
      name: 'terminal dedup',
      state: TaskState.succeeded,
      attempt: 0,
      options: const TaskOptions(recoveryPolicy: TaskRecoveryPolicy.retry),
      executions: <int>[],
      signals: 0,
      terminal: TaskState.succeeded,
    ),
  ]) {
    test(scenario.name, () async {
      final broker = _AcknowledgementBroker();
      final backend = InMemoryResultBackend();
      final executions = <int>[];
      final interruptions = <TaskInterruptedPayload>[];
      final retries = <TaskRetryPayload>[];
      final handler = FunctionTaskHandler<String>.inline(
        name: 'recover',
        options: scenario.options,
        entrypoint: (context, args) async {
          executions.add(context.attempt);
          expect(interruptions.length, scenario.signals);
          return 'done';
        },
      );
      final interrupted = StemSignals.onTaskInterrupted(
        (payload, _) {
          interruptions.add(payload);
        },
        taskName: 'recover',
        workerId: 'replacement',
      );
      final retry = StemSignals.onTaskRetry((payload, _) {
        retries.add(payload);
      }, taskName: 'recover');
      addTearDown(interrupted.cancel);
      addTearDown(retry.cancel);
      // Model the durable residue of a previous runtime. The new worker has no
      // in-memory active-delivery entry for this task.
      await backend.set(
        'task',
        scenario.state,
        meta: {'worker': 'previous'},
      );
      await broker.publish(
        Envelope(
          id: 'task',
          name: 'recover',
          args: {},
          attempt: scenario.attempt,
          maxRetries: scenario.options.maxRetries,
        ),
      );
      final worker = Worker(
        broker: broker,
        backend: backend,
        tasks: [handler],
        rateLimiter: _DenyOnceRateLimiter(),
        consumerName: 'replacement',
        concurrency: 1,
      );
      addTearDown(() async {
        await worker.shutdown();
        await broker.close();
        await backend.close();
      });
      final completed = <TaskPostrunPayload>[];
      final postrun = StemSignals.taskPostrun.connect((payload, _) {
        completed.add(payload);
      });
      addTearDown(postrun.cancel);
      await worker.start();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      if (scenario.name == 'terminal dedup') {
        while (broker.acknowledgements == 0) {
          if (DateTime.now().isAfter(deadline)) {
            fail('No terminal acknowledgement');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      while (completed.length <
          (scenario.name == 'retry uses next attempt'
              ? 2
              : scenario.name == 'terminal dedup'
              ? 0
              : 1)) {
        if (DateTime.now().isAfter(deadline)) fail('Recovery did not complete');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await worker.shutdown();
      expect(executions, scenario.executions);
      expect(interruptions, hasLength(scenario.signals));
      expect((await backend.get('task'))?.state, scenario.terminal);
      if (interruptions.isNotEmpty) {
        expect(interruptions.single.priorStatus.meta['worker'], 'previous');
        expect(interruptions.single.envelope.attempt, 0);
        expect(interruptions.single.policy, scenario.options.recoveryPolicy);
      }
      if (scenario.terminal == TaskState.failed) {
        expect(
          (await backend.get('task'))?.error?.type,
          'TaskInterruptedException',
        );
      }
      if (scenario.name == 'retry uses next attempt') {
        expect(retries.single.reason, isA<TaskInterruptedException>());
      }
    });
  }
}

class _AcknowledgementBroker extends InMemoryBroker {
  int acknowledgements = 0;

  @override
  Future<void> ack(Delivery delivery) async {
    await super.ack(delivery);
    acknowledgements++;
  }
}

class _DenyOnceRateLimiter implements RateLimiter {
  bool denied = false;

  @override
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  }) async {
    if (denied) return const RateLimitDecision(allowed: true);
    denied = true;
    return const RateLimitDecision(
      allowed: false,
      retryAfter: Duration(milliseconds: 5),
    );
  }
}
