import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:test/test.dart';

void main() {
  test('FlowStepControl factories set expected fields', () {
    final sleep = FlowStepControl.sleep(
      const Duration(seconds: 5),
      data: const {'ok': true},
    );
    expect(sleep.type, FlowControlType.sleep);
    expect(sleep.delay, const Duration(seconds: 5));
    expect(sleep.data?['ok'], isTrue);

    final wait = FlowStepControl.awaitTopic(
      'topic',
      deadline: DateTime.parse('2025-01-01T00:00:00Z'),
      data: const {'note': 'x'},
    );
    expect(wait.type, FlowControlType.waitForEvent);
    expect(wait.topic, 'topic');
    expect(wait.deadline, DateTime.parse('2025-01-01T00:00:00Z'));

    final cont = FlowStepControl.continueRun();
    expect(cont.type, FlowControlType.continueRun);
  });
}
