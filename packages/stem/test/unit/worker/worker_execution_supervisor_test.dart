import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/task_invocation.dart';
import 'package:stem/src/worker/worker_config.dart';
import 'package:stem/src/worker/worker_execution_supervisor.dart';
import 'package:test/test.dart';

void main() {
  test('rejects isolate mode without an entrypoint', () async {
    final supervisor = WorkerExecutionSupervisor(
      concurrency: 1,
      lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      onRecycle: (_) {},
      onSpawned: (_) {},
      onDisposed: (_) {},
    );
    addTearDown(supervisor.dispose);

    final handler = _InvalidIsolateHandler();
    final context = TaskContext(
      id: 'task-1',
      attempt: 0,
      headers: const {},
      meta: const {},
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {data}) async {},
    );

    await expectLater(
      supervisor.execute(
        handler: handler,
        context: context,
        envelope: Envelope(name: handler.name, args: const {}),
        args: const {},
        controlHandler: (_) {},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('declares isolate execution'),
        ),
      ),
    );
  });
}

class _InvalidIsolateHandler
    implements TaskHandler<Object?>, TaskExecutionModeProvider {
  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<Object?> call(TaskContext context, Map<String, Object?> args) async {
    return null;
  }

  @override
  TaskExecutionMode get executionMode => TaskExecutionMode.isolate;

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  String get name => 'invalid.isolate';

  @override
  TaskOptions get options => const TaskOptions();
}
