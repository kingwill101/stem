import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/core/clock.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:test/test.dart';

void main() {
  test('payload getters expose task metadata', () {
    final envelope = Envelope(
      id: 'task-1',
      name: 'demo.task',
      args: const {},
      attempt: 2,
    );
    const worker = WorkerInfo(
      id: 'worker-1',
      queues: ['default'],
      broadcasts: ['events'],
    );

    final received = TaskReceivedPayload(envelope: envelope, worker: worker);
    expect(received.taskId, equals('task-1'));
    expect(received.taskName, equals('demo.task'));

    final context = TaskContext(
      id: envelope.id,
      attempt: envelope.attempt,
      headers: const {},
      meta: const {},
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
    );
    final prerun = TaskPrerunPayload(
      envelope: envelope,
      worker: worker,
      context: context,
    );
    expect(prerun.taskId, equals('task-1'));
    expect(prerun.taskName, equals('demo.task'));
    expect(prerun.attempt, equals(2));

    final postrun = TaskPostrunPayload(
      envelope: envelope,
      worker: worker,
      context: context,
      result: const {'ok': true},
      state: TaskState.succeeded,
    );
    expect(postrun.taskId, equals('task-1'));
    expect(postrun.taskName, equals('demo.task'));
    expect(postrun.attempt, equals(2));
    expect(
      postrun.resultJson<_TaskResultPayload>(
        decode: _TaskResultPayload.fromJson,
      ),
      isA<_TaskResultPayload>().having((value) => value.ok, 'ok', isTrue),
    );
    expect(
      postrun.resultVersionedJson<_TaskResultPayload>(
        version: 2,
        decode: _TaskResultPayload.fromVersionedJson,
      ),
      isA<_TaskResultPayload>().having((value) => value.ok, 'ok', isTrue),
    );

    final retry = TaskRetryPayload(
      envelope: envelope,
      worker: worker,
      reason: 'boom',
      nextRetryAt: DateTime.utc(2025),
      emittedAt: DateTime.utc(2024),
    );
    expect(retry.taskId, equals('task-1'));
    expect(retry.taskName, equals('demo.task'));
    expect(retry.attempt, equals(2));
    expect(retry.occurredAt, equals(DateTime.utc(2024)));
    expect(
      retry.attributes['nextRetryAt'],
      equals(DateTime.utc(2025).toIso8601String()),
    );

    final success = TaskSuccessPayload(
      envelope: envelope,
      worker: worker,
      result: const {'ok': true},
    );
    expect(
      success.resultJson<_TaskResultPayload>(
        decode: _TaskResultPayload.fromJson,
      ),
      isA<_TaskResultPayload>().having((value) => value.ok, 'ok', isTrue),
    );
    expect(
      success.resultVersionedJson<_TaskResultPayload>(
        version: 2,
        decode: _TaskResultPayload.fromVersionedJson,
      ),
      isA<_TaskResultPayload>().having((value) => value.ok, 'ok', isTrue),
    );
  });

  test('control command payload timestamps are frozen at creation', () {
    const worker = WorkerInfo(
      id: 'worker-1',
      queues: ['default'],
      broadcasts: [],
    );
    final command = ControlCommandMessage(
      requestId: 'req-1',
      type: 'pause',
      targets: const ['*'],
    );
    final clock = FakeStemClock(DateTime.utc(2025));

    withStemClock(clock, () {
      final received = ControlCommandReceivedPayload(
        worker: worker,
        command: command,
      );
      clock.advance(const Duration(minutes: 1));
      final completed = ControlCommandCompletedPayload(
        worker: worker,
        command: command,
        status: 'ok',
      );
      clock.advance(const Duration(minutes: 1));

      expect(received.occurredAt, DateTime.utc(2025));
      expect(completed.occurredAt, DateTime.utc(2025, 1, 1, 0, 1));
    });
  });

  test('workflow run payload exposes typed metadata helpers', () {
    final payload = WorkflowRunPayload(
      runId: 'run-1',
      workflow: 'demo.workflow',
      status: WorkflowRunStatus.suspended,
      metadata: const {
        'attempt': 3,
        'approval': {'approved': true},
      },
    );

    expect(payload.metadataValue<int>('attempt'), 3);
    expect(payload.metadataValueOr<String>('missing', 'fallback'), 'fallback');
    expect(payload.requiredMetadataValue<int>('attempt'), 3);
    expect(
      payload.metadataPayloadJson<_WorkflowRunEnvelope>(
        decode: _WorkflowRunEnvelope.fromJson,
      ),
      isA<_WorkflowRunEnvelope>()
          .having((value) => value.attempt, 'attempt', 3)
          .having((value) => value.approved, 'approved', isTrue),
    );
    expect(
      payload.metadataPayloadVersionedJson<_WorkflowRunEnvelope>(
        version: 2,
        decode: _WorkflowRunEnvelope.fromVersionedJson,
      ),
      isA<_WorkflowRunEnvelope>()
          .having((value) => value.attempt, 'attempt', 3)
          .having((value) => value.approved, 'approved', isTrue),
    );
    expect(
      payload.metadataJson<_WorkflowRunMetadata>(
        'approval',
        decode: _WorkflowRunMetadata.fromJson,
      ),
      isA<_WorkflowRunMetadata>().having(
        (value) => value.approved,
        'approved',
        isTrue,
      ),
    );
    expect(
      payload.metadataVersionedJson<_WorkflowRunMetadata>(
        'approval',
        version: 2,
        decode: _WorkflowRunMetadata.fromVersionedJson,
      ),
      isA<_WorkflowRunMetadata>().having(
        (value) => value.approved,
        'approved',
        isTrue,
      ),
    );
  });

  test('control command payload exposes typed response and error helpers', () {
    const worker = WorkerInfo(
      id: 'worker-1',
      queues: ['default'],
      broadcasts: [],
    );
    final command = ControlCommandMessage(
      requestId: 'req-2',
      type: 'pause',
      targets: const ['*'],
    );
    final payload = ControlCommandCompletedPayload(
      worker: worker,
      command: command,
      status: 'error',
      response: const {
        PayloadCodec.versionKey: 2,
        'queue': 'priority',
        'paused': true,
      },
      error: const {
        PayloadCodec.versionKey: 2,
        'code': 'pause_failed',
        'message': 'already paused',
      },
    );

    expect(payload.responseValue<String>('queue'), 'priority');
    expect(payload.responseValueOr<String>('missing', 'fallback'), 'fallback');
    expect(payload.requiredResponseValue<bool>('paused'), isTrue);
    expect(
      payload.responseJson<_ControlResponse>(decode: _ControlResponse.fromJson),
      isA<_ControlResponse>()
          .having((value) => value.queue, 'queue', 'priority')
          .having((value) => value.paused, 'paused', isTrue),
    );
    expect(
      payload.responseVersionedJson<_ControlResponse>(
        version: 2,
        decode: _ControlResponse.fromVersionedJson,
      ),
      isA<_ControlResponse>()
          .having((value) => value.queue, 'queue', 'priority')
          .having((value) => value.paused, 'paused', isTrue),
    );
    expect(payload.errorValue<String>('code'), 'pause_failed');
    expect(payload.errorValueOr<String>('missing', 'fallback'), 'fallback');
    expect(payload.requiredErrorValue<String>('message'), 'already paused');
    expect(
      payload.errorJson<_ControlError>(decode: _ControlError.fromJson),
      isA<_ControlError>()
          .having((value) => value.code, 'code', 'pause_failed')
          .having((value) => value.message, 'message', 'already paused'),
    );
    expect(
      payload.errorVersionedJson<_ControlError>(
        version: 2,
        decode: _ControlError.fromVersionedJson,
      ),
      isA<_ControlError>()
          .having((value) => value.code, 'code', 'pause_failed')
          .having((value) => value.message, 'message', 'already paused'),
    );
  });
}

class _TaskResultPayload {
  const _TaskResultPayload({required this.ok});

  factory _TaskResultPayload.fromJson(Map<String, dynamic> json) {
    return _TaskResultPayload(ok: json['ok'] as bool);
  }

  factory _TaskResultPayload.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _TaskResultPayload(ok: json['ok'] as bool);
  }

  final bool ok;
}

class _WorkflowRunMetadata {
  const _WorkflowRunMetadata({required this.approved});

  factory _WorkflowRunMetadata.fromJson(Map<String, dynamic> json) {
    return _WorkflowRunMetadata(approved: json['approved'] as bool);
  }

  factory _WorkflowRunMetadata.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _WorkflowRunMetadata(approved: json['approved'] as bool);
  }

  final bool approved;
}

class _WorkflowRunEnvelope {
  const _WorkflowRunEnvelope({required this.attempt, required this.approved});

  factory _WorkflowRunEnvelope.fromJson(Map<String, dynamic> json) {
    final approval = Map<String, dynamic>.from(
      json['approval']! as Map<Object?, Object?>,
    );
    return _WorkflowRunEnvelope(
      attempt: json['attempt'] as int,
      approved: approval['approved'] as bool,
    );
  }

  factory _WorkflowRunEnvelope.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _WorkflowRunEnvelope.fromJson(json);
  }

  final int attempt;
  final bool approved;
}

class _ControlResponse {
  const _ControlResponse({required this.queue, required this.paused});

  factory _ControlResponse.fromJson(Map<String, dynamic> json) {
    return _ControlResponse(
      queue: json['queue'] as String,
      paused: json['paused'] as bool,
    );
  }

  factory _ControlResponse.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _ControlResponse.fromJson(json);
  }

  final String queue;
  final bool paused;
}

class _ControlError {
  const _ControlError({required this.code, required this.message});

  factory _ControlError.fromJson(Map<String, dynamic> json) {
    return _ControlError(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }

  factory _ControlError.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _ControlError.fromJson(json);
  }

  final String code;
  final String message;
}
