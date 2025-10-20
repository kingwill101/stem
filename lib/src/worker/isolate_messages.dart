import 'dart:isolate';

import '../core/task_invocation.dart';

class TaskRunRequest {
  TaskRunRequest({
    required this.entrypoint,
    required this.args,
    required this.headers,
    required this.meta,
    required this.attempt,
    required this.controlPort,
    required this.replyPort,
  });

  final TaskEntrypoint entrypoint;
  final Map<String, Object?> args;
  final Map<String, String> headers;
  final Map<String, Object?> meta;
  final int attempt;
  final SendPort controlPort;
  final SendPort replyPort;
}

sealed class TaskRunResponse {
  const TaskRunResponse();
}

class TaskRunSuccess extends TaskRunResponse {
  const TaskRunSuccess(this.result);

  final Object? result;
}

class TaskRunFailure extends TaskRunResponse {
  const TaskRunFailure(this.errorType, this.message, this.stackTrace);

  final String errorType;
  final String message;
  final String stackTrace;
}

class TaskWorkerShutdown {}

void taskWorkerIsolate(SendPort handshakePort) {
  final commandPort = ReceivePort();
  handshakePort.send(commandPort.sendPort);

  commandPort.listen((message) async {
    if (message is TaskWorkerShutdown) {
      commandPort.close();
      return;
    }

    if (message is TaskRunRequest) {
      final invocationContext = TaskInvocationContext.remote(
        controlPort: message.controlPort,
        headers: message.headers,
        meta: message.meta,
        attempt: message.attempt,
      );
      try {
        final result = await message.entrypoint(
          invocationContext,
          message.args,
        );
        message.replyPort.send(TaskRunSuccess(result));
      } catch (error, stack) {
        message.replyPort.send(
          TaskRunFailure(
            error.runtimeType.toString(),
            error.toString(),
            stack.toString(),
          ),
        );
      }
    }
  });
}
