import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/task_invocation_portable.dart' as portable;
import 'package:test/test.dart';

void main() {
  test('portable invocation context forwards runtime capabilities', () async {
    var heartbeatCount = 0;
    Duration? extension;
    double? progress;
    Map<String, Object?>? progressData;

    final context = portable.TaskInvocationContext.local(
      id: 'portable-context',
      args: const {'value': 1},
      headers: const {'trace': 'abc'},
      meta: const {'tenant': 'test'},
      attempt: 2,
      heartbeat: () => heartbeatCount += 1,
      extendLease: (by) async => extension = by,
      progress: (percent, {data}) async {
        progress = percent;
        progressData = data;
      },
    );

    context.heartbeat();
    expect(heartbeatCount, 1);
    await context.extendLease(const Duration(seconds: 5));
    expect(extension, const Duration(seconds: 5));
    await context.progress(0.5, data: const {'step': 'half'});

    expect(context.id, 'portable-context');
    expect(context.args, const {'value': 1});
    expect(context.headers, const {'trace': 'abc'});
    expect(context.meta, const {'tenant': 'test'});
    expect(context.attempt, 2);
    expect(context.cancellation, isA<TaskCancellationToken>());
    expect(progress, 0.5);
    expect(progressData, const {'step': 'half'});
  });
}
