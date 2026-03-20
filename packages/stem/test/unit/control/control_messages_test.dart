import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:test/test.dart';

void main() {
  test('ControlCommandMessage exposes typed payload helpers', () {
    final command = ControlCommandMessage(
      requestId: 'req-1',
      type: 'pause',
      targets: const ['*'],
      payload: const {
        PayloadCodec.versionKey: 2,
        'queue': 'priority',
        'paused': true,
      },
    );

    expect(command.payloadValue<String>('queue'), 'priority');
    expect(command.payloadValueOr<String>('missing', 'fallback'), 'fallback');
    expect(command.requiredPayloadValue<bool>('paused'), isTrue);
    expect(
      command.payloadJson<_ControlPayload>(decode: _ControlPayload.fromJson),
      isA<_ControlPayload>()
          .having((value) => value.queue, 'queue', 'priority')
          .having((value) => value.paused, 'paused', isTrue),
    );
    expect(
      command.payloadVersionedJson<_ControlPayload>(
        version: 2,
        decode: _ControlPayload.fromVersionedJson,
      ),
      isA<_ControlPayload>()
          .having((value) => value.queue, 'queue', 'priority')
          .having((value) => value.paused, 'paused', isTrue),
    );
  });

  test('ControlReplyMessage exposes typed payload and error helpers', () {
    final reply = ControlReplyMessage(
      requestId: 'req-2',
      workerId: 'worker-1',
      status: 'error',
      payload: const {
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

    expect(reply.payloadValue<String>('queue'), 'priority');
    expect(reply.payloadValueOr<String>('missing', 'fallback'), 'fallback');
    expect(reply.requiredPayloadValue<bool>('paused'), isTrue);
    expect(
      reply.payloadJson<_ControlPayload>(decode: _ControlPayload.fromJson),
      isA<_ControlPayload>()
          .having((value) => value.queue, 'queue', 'priority')
          .having((value) => value.paused, 'paused', isTrue),
    );
    expect(
      reply.payloadVersionedJson<_ControlPayload>(
        version: 2,
        decode: _ControlPayload.fromVersionedJson,
      ),
      isA<_ControlPayload>()
          .having((value) => value.queue, 'queue', 'priority')
          .having((value) => value.paused, 'paused', isTrue),
    );
    expect(reply.errorValue<String>('code'), 'pause_failed');
    expect(reply.errorValueOr<String>('missing', 'fallback'), 'fallback');
    expect(reply.requiredErrorValue<String>('message'), 'already paused');
    expect(
      reply.errorJson<_ControlError>(decode: _ControlError.fromJson),
      isA<_ControlError>()
          .having((value) => value.code, 'code', 'pause_failed')
          .having((value) => value.message, 'message', 'already paused'),
    );
    expect(
      reply.errorVersionedJson<_ControlError>(
        version: 2,
        decode: _ControlError.fromVersionedJson,
      ),
      isA<_ControlError>()
          .having((value) => value.code, 'code', 'pause_failed')
          .having((value) => value.message, 'message', 'already paused'),
    );
  });
}

class _ControlPayload {
  const _ControlPayload({required this.queue, required this.paused});

  factory _ControlPayload.fromJson(Map<String, dynamic> json) {
    return _ControlPayload(
      queue: json['queue'] as String,
      paused: json['paused'] as bool,
    );
  }

  factory _ControlPayload.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _ControlPayload.fromJson(json);
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
