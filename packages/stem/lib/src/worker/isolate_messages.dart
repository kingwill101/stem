import 'dart:io';
import 'dart:isolate';

import 'package:stem/src/core/task_invocation.dart';

/// A request to run a task in an isolate.
///
/// Contains the [entrypoint], [args], [headers], [meta], [attempt], and ports
/// for communication.
class TaskRunRequest {
  /// Creates a request to execute a task in an isolate.
  TaskRunRequest({
    required this.entrypoint,
    required this.args,
    required this.headers,
    required this.meta,
    required this.attempt,
    required this.controlPort,
    required this.replyPort,
  });

  /// The entrypoint function to execute.
  final TaskEntrypoint entrypoint;

  /// The arguments to pass to the [entrypoint].
  final Map<String, Object?> args;

  /// The headers for the task invocation.
  final Map<String, String> headers;

  /// The metadata for the task invocation.
  final Map<String, Object?> meta;

  /// The attempt number for this task run.
  final int attempt;

  /// The control port for the task invocation.
  final SendPort controlPort;

  /// The reply port to send the response.
  final SendPort replyPort;
}

/// The response from a task run.
sealed class TaskRunResponse {
  /// Base type for isolate task run responses.
  const TaskRunResponse();
}

/// A successful task run response containing the [result].
class TaskRunSuccess extends TaskRunResponse {
  /// Creates a successful task run response.
  const TaskRunSuccess(this.result, {this.memoryBytes});

  /// The result of the task execution.
  final Object? result;

  /// The reported resident set size after execution, when available.
  final int? memoryBytes;
}

/// A failed task run response with [errorType], [message], and [stackTrace].
class TaskRunFailure extends TaskRunResponse {
  /// Creates a failed task run response.
  const TaskRunFailure(this.errorType, this.message, this.stackTrace);

  /// The type of the error that occurred.
  final String errorType;

  /// The error message.
  final String message;

  /// The stack trace of the error.
  final String stackTrace;
}

/// A message to shut down the task worker.
class TaskWorkerShutdown {
  /// Creates a shutdown signal for worker isolates.
  const TaskWorkerShutdown();
}

/// Runs a task worker isolate that listens for [TaskRunRequest] and
/// [TaskWorkerShutdown] messages.
///
/// Sends the command port back via [handshakePort] and processes messages
/// asynchronously.
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
        int? rssBytes;
        try {
          rssBytes = ProcessInfo.currentRss;
        } on Object {
          // Ignore failures to read RSS in restricted runtimes.
        }
        message.replyPort.send(TaskRunSuccess(result, memoryBytes: rssBytes));
      } on Object catch (error, stack) {
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
