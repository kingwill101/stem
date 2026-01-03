import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

const String mixedQueue = 'task-context-mixed';

class SqlitePaths {
  const SqlitePaths({required this.broker, required this.backend});

  final File broker;
  final File backend;
}

SqlitePaths resolveDatabasePaths() {
  final brokerOverride = Platform.environment['STEM_SQLITE_BROKER_PATH'];
  final backendOverride = Platform.environment['STEM_SQLITE_BACKEND_PATH'];
  if (brokerOverride != null && brokerOverride.trim().isNotEmpty ||
      backendOverride != null && backendOverride.trim().isNotEmpty) {
    final brokerPath = brokerOverride?.trim().isNotEmpty == true
        ? brokerOverride!.trim()
        : 'task_context_mixed_broker.sqlite';
    final backendPath = backendOverride?.trim().isNotEmpty == true
        ? backendOverride!.trim()
        : 'task_context_mixed_backend.sqlite';
    return SqlitePaths(
      broker: File(brokerPath),
      backend: File(backendPath),
    );
  }

  final base = Platform.environment['STEM_SQLITE_PATH'] ?? 'task_context_mixed';
  final separator = Platform.pathSeparator;
  String prefix;
  if (base.endsWith(separator)) {
    prefix = '${base}task_context_mixed';
  } else {
    final lastSeparator = base.lastIndexOf(separator);
    final fileName =
        lastSeparator == -1 ? base : base.substring(lastSeparator + 1);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      final trimmed = fileName.substring(0, dotIndex);
      final dir =
          lastSeparator == -1 ? '' : base.substring(0, lastSeparator + 1);
      prefix = '$dir$trimmed';
    } else {
      prefix = base;
    }
  }

  return SqlitePaths(
    broker: File('${prefix}_broker.sqlite'),
    backend: File('${prefix}_backend.sqlite'),
  );
}

Future<SqliteBroker> connectBroker() {
  return SqliteBroker.open(resolveDatabasePaths().broker);
}

Future<SqliteResultBackend> connectBackend() {
  return SqliteResultBackend.open(resolveDatabasePaths().backend);
}

class AuditArgs {
  const AuditArgs({required this.runId, required this.message});

  final String runId;
  final String message;
}

final auditDefinition = TaskDefinition<AuditArgs, void>(
  name: 'demo.audit',
  encodeArgs: (args) => {
    'runId': args.runId,
    'message': args.message,
  },
  metadata: const TaskMetadata(
    description: 'Captures audit breadcrumbs from nested tasks.',
    tags: ['task-context', 'audit'],
  ),
  defaultOptions: const TaskOptions(queue: mixedQueue),
);

final linkSuccessDefinition = TaskDefinition<Map<String, Object?>, void>(
  name: 'demo.on_success',
  encodeArgs: (args) => args,
  metadata: const TaskMetadata(
    description: 'Runs when link callbacks are triggered on success.',
  ),
  defaultOptions: const TaskOptions(queue: mixedQueue),
);

final linkErrorDefinition = TaskDefinition<Map<String, Object?>, void>(
  name: 'demo.on_error',
  encodeArgs: (args) => args,
  metadata: const TaskMetadata(
    description: 'Runs when link callbacks are triggered on failure.',
  ),
  defaultOptions: const TaskOptions(queue: mixedQueue),
);

SimpleTaskRegistry buildRegistry() {
  return SimpleTaskRegistry()
    ..register(InlineCoordinatorTask())
    ..register(
      FunctionTaskHandler<void>.inline(
        name: 'demo.inline_entrypoint',
        entrypoint: inlineEntrypoint,
        options: const TaskOptions(queue: mixedQueue),
        metadata: const TaskMetadata(
          description: 'Inline TaskInvocationContext entrypoint.',
          tags: ['task-context', 'inline'],
        ),
      ),
    )
    ..register(
      FunctionTaskHandler<Object?>(
        name: 'demo.isolate_child',
        entrypoint: isolateChildEntrypoint,
        options: const TaskOptions(queue: mixedQueue),
        metadata: const TaskMetadata(
          description: 'Isolate entrypoint that spawns typed calls.',
          tags: ['task-context', 'isolate'],
        ),
      ),
    )
    ..register(
      FunctionTaskHandler<Object?>(
        name: 'demo.flaky',
        entrypoint: flakyEntrypoint,
        options: const TaskOptions(
          queue: mixedQueue,
          maxRetries: 2,
          retryPolicy: TaskRetryPolicy(
            backoff: true,
            backoffMax: Duration(seconds: 5),
            defaultDelay: Duration(milliseconds: 150),
            jitter: true,
          ),
        ),
        metadata: const TaskMetadata(
          description: 'Demonstrates TaskInvocationContext.retry overrides.',
          tags: ['task-context', 'retry'],
        ),
      ),
    )
    ..register(
      FunctionTaskHandler<void>.inline(
        name: auditDefinition.name,
        entrypoint: auditEntrypoint,
        options: auditDefinition.defaultOptions,
        metadata: auditDefinition.metadata,
      ),
    )
    ..register(
      FunctionTaskHandler<void>.inline(
        name: linkSuccessDefinition.name,
        entrypoint: linkSuccessEntrypoint,
        options: linkSuccessDefinition.defaultOptions,
        metadata: linkSuccessDefinition.metadata,
      ),
    )
    ..register(
      FunctionTaskHandler<void>.inline(
        name: linkErrorDefinition.name,
        entrypoint: linkErrorEntrypoint,
        options: linkErrorDefinition.defaultOptions,
        metadata: linkErrorDefinition.metadata,
      ),
    );
}

class InlineCoordinatorTask extends TaskHandler<void> {
  @override
  String get name => 'demo.inline_parent';

  @override
  TaskOptions get options => const TaskOptions(
        queue: mixedQueue,
        maxRetries: 1,
        rateLimit: '30/m',
        priority: 3,
        retryPolicy: TaskRetryPolicy(
          backoff: true,
          defaultDelay: Duration(milliseconds: 250),
          jitter: true,
        ),
      );

  @override
  TaskMetadata get metadata => const TaskMetadata(
        description:
            'Inline TaskContext entrypoint that enqueues nested tasks.',
        tags: ['task-context', 'inline'],
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final runId = (args['runId'] as String?) ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final forceFail = args['forceFail'] as bool? ?? false;

    stdout.writeln(
      '[inline_parent] id=${context.id} attempt=${context.attempt} runId=$runId',
    );

    final inlineId = await context.enqueue(
      'demo.inline_entrypoint',
      args: {'runId': runId},
      headers: const {'x-demo': 'inline-entrypoint'},
      meta: const {'source': 'inline-parent'},
      enqueueOptions: TaskEnqueueOptions(
        queue: mixedQueue,
        eta: DateTime.now().add(const Duration(milliseconds: 300)),
        ignoreResult: true,
        addToParent: false,
      ),
    );

    final isolateId = await context.spawn(
      'demo.isolate_child',
      args: {'runId': runId},
      enqueueOptions: TaskEnqueueOptions(
        queue: mixedQueue,
        countdown: const Duration(milliseconds: 500),
        expires: DateTime.now().add(const Duration(minutes: 2)),
        addToParent: true,
      ),
    );

    final auditId = await context.enqueueCall(
      auditDefinition.call(
        AuditArgs(
          runId: runId,
          message: 'inline parent scheduled child tasks',
        ),
      ),
    );

    final fullApplyAsync = TaskEnqueueOptions(
      taskId: 'flaky-$runId',
      queue: mixedQueue,
      exchange: 'demo-exchange',
      routingKey: 'demo.flaky',
      priority: 9,
      timeLimit: const Duration(seconds: 8),
      softTimeLimit: const Duration(seconds: 4),
      serializer: 'json',
      compression: 'gzip',
      ignoreResult: false,
      shadow: 'demo.flaky',
      replyTo: 'demo.reply',
      retry: true,
      retryPolicy: const TaskRetryPolicy(
        backoff: true,
        backoffMax: Duration(seconds: 3),
        defaultDelay: Duration(milliseconds: 200),
        jitter: true,
        maxRetries: 2,
      ),
      publishConnection: const {'adapter': 'sqlite'},
      producer: const {'app': 'task-context-mixed'},
      link: [
        linkSuccessDefinition.call(
          <String, Object?>{'runId': runId, 'source': 'link'},
        ),
      ],
      linkError: [
        linkErrorDefinition.call(
          <String, Object?>{'runId': runId, 'source': 'link_error'},
        ),
      ],
    );

    final flakyId = await context.enqueue(
      'demo.flaky',
      args: {'runId': runId, 'forceFail': forceFail},
      enqueueOptions: fullApplyAsync,
    );

    stdout.writeln(
      '[inline_parent] queued inline=$inlineId isolate=$isolateId audit=$auditId flaky=$flakyId',
    );
  }

  @override
  TaskEntrypoint? get isolateEntrypoint => null;
}

FutureOr<Object?> inlineEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final runId = args['runId'] as String? ?? 'unknown';
  stdout.writeln(
    '[inline_entrypoint] id=${context.id} attempt=${context.attempt} runId=$runId meta=${context.meta}',
  );

  await context.enqueueCall(
    auditDefinition.call(
      AuditArgs(
        runId: runId,
        message: 'inline entrypoint completed',
      ),
      enqueueOptions: const TaskEnqueueOptions(priority: 4),
    ),
  );

  return 'inline-ok';
}

FutureOr<Object?> isolateChildEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final runId = args['runId'] as String? ?? 'unknown';
  stdout.writeln(
    '[isolate_child] id=${context.id} attempt=${context.attempt} runId=$runId',
  );

  final call = context
      .enqueueBuilder(
        definition: auditDefinition,
        args: AuditArgs(
          runId: runId,
          message: 'isolate child used enqueueBuilder',
        ),
      )
      .header('x-child', 'isolate')
      .meta('origin', 'isolate-child')
      .delay(const Duration(milliseconds: 200))
      .enqueueOptions(const TaskEnqueueOptions(shadow: 'audit-shadow'))
      .build();

  await context.enqueueCall(call);
  return 'isolate-ok';
}

FutureOr<Object?> flakyEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  final runId = args['runId'] as String? ?? 'unknown';
  final forceFail = args['forceFail'] as bool? ?? false;
  stdout.writeln(
    '[flaky] id=${context.id} attempt=${context.attempt} runId=$runId forceFail=$forceFail',
  );

  if (forceFail) {
    throw StateError('Forced failure for runId=$runId');
  }

  if (context.attempt < 1) {
    context.retry(
      countdown: const Duration(milliseconds: 300),
      retryPolicy: const TaskRetryPolicy(
        backoff: true,
        defaultDelay: Duration(milliseconds: 200),
        jitter: true,
        maxRetries: 2,
      ),
      maxRetries: 2,
      timeLimit: const Duration(seconds: 6),
      softTimeLimit: const Duration(seconds: 3),
    );
    return null;
  }

  return {'runId': runId, 'status': 'ok'};
}

FutureOr<void> auditEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  stdout.writeln(
    '[audit] id=${context.id} runId=${args['runId']} message=${args['message']}',
  );
}

FutureOr<void> linkSuccessEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  stdout.writeln(
    '[link_success] id=${context.id} runId=${args['runId']} source=${args['source']}',
  );
}

FutureOr<void> linkErrorEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  stdout.writeln(
    '[link_error] id=${context.id} runId=${args['runId']} source=${args['source']}',
  );
}
