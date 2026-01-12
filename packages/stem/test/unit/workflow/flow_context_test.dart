import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
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
}
