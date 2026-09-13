import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

void main() {
  final uri =
      Platform.environment['STEM_TEST_REDIS_URL'] ??
      Platform.environment['REDIS_URL'];
  if (uri == null || uri.isEmpty) {
    test(
      'topic cleanup requires Redis',
      () {},
      skip: 'Set STEM_TEST_REDIS_URL or REDIS_URL.',
    );
    return;
  }

  for (final namespacePart in ['plain', 'nested:wf:namespace']) {
    for (final transition in _Transition.values) {
      test('$transition cleans special run IDs in $namespacePart', () async {
        final namespace =
            'workflow_cleanup_${DateTime.now().microsecondsSinceEpoch}'
            ':$namespacePart';
        final store = await RedisWorkflowStore.connect(
          uri,
          namespace: namespace,
        );
        addTearDown(store.close);
        final runId = 'run:wf:${transition.name}';
        final topic = 'topic:wf:${transition.name}';
        await store.createRun(
          workflow: 'topic.cleanup',
          params: const {},
          runId: runId,
        );
        final claim = transition == _Transition.fencedFailure
            ? await store.claimRunExecution(runId, ownerId: 'cleanup-test')
            : null;
        await store.suspendOnTopic(runId, 'wait', topic);
        expect(await store.runsWaitingOn(topic), [runId]);

        switch (transition) {
          case _Transition.complete:
            expect(await store.completeIfActive(runId, null), isTrue);
          case _Transition.cancel:
            expect(await store.cancelIfActive(runId), isTrue);
          case _Transition.running:
            await store.markRunning(runId);
          case _Transition.resumed:
            await store.markResumed(runId);
          case _Transition.failure:
            await store.markFailed(
              runId,
              StateError('failure'),
              StackTrace.empty,
              terminal: true,
            );
          case _Transition.fencedFailure:
            expect(
              await store.markFailedForExecution(
                runId,
                executionId: claim!.executionId,
                error: StateError('failure'),
                stack: StackTrace.empty,
              ),
              TerminalFailureResult.applied,
            );
        }
        expect(await store.runsWaitingOn(topic), isEmpty);
      });
    }
  }
}

enum _Transition { complete, cancel, running, resumed, failure, fencedFailure }
