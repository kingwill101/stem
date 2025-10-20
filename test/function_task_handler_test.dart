import 'package:test/test.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/function_task_handler.dart';

void main() {
  test(
    'FunctionTaskHandler forwards context utilities to entrypoint',
    () async {
      var heartbeats = 0;
      Duration? extended;
      double? progressValue;
      Map<String, Object?>? progressData;

      final handler = FunctionTaskHandler<int>(
        name: 'math.add',
        entrypoint: (invocation, args) async {
          invocation.heartbeat();
          await invocation.extendLease(const Duration(seconds: 3));
          await invocation.progress(0.5, data: {'stage': 'halfway'});
          final a = args['a'] as int;
          final b = args['b'] as int;
          return a + b;
        },
      );

      final result = await handler(
        TaskContext(
          id: 'task-1',
          attempt: 1,
          headers: const {},
          meta: const {},
          heartbeat: () {
            heartbeats += 1;
          },
          extendLease: (duration) async {
            extended = duration;
          },
          progress: (percent, {data}) async {
            progressValue = percent;
            progressData = data;
          },
        ),
        const {'a': 2, 'b': 3},
      );

      expect(result, equals(5));
      expect(handler.isolateEntrypoint, isNotNull);
      expect(heartbeats, equals(1));
      expect(extended, equals(const Duration(seconds: 3)));
      expect(progressValue, equals(0.5));
      expect(progressData, equals({'stage': 'halfway'}));
    },
  );
}
