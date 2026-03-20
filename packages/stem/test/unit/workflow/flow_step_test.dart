import 'package:stem/src/core/payload_codec.dart';
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

  test('FlowStepControl JSON factories encode DTO payloads', () {
    final sleep = FlowStepControl.sleepJson(
      const Duration(seconds: 5),
      const _SuspensionPayload(stage: 'sleeping'),
    );
    final wait = FlowStepControl.awaitTopicJson(
      'topic',
      const _SuspensionPayload(stage: 'waiting'),
      deadline: DateTime.parse('2025-01-01T00:00:00Z'),
    );
    final versionedSleep = FlowStepControl.sleepVersionedJson(
      const Duration(seconds: 6),
      const _SuspensionPayload(stage: 'versioned-sleep'),
      version: 2,
    );
    final versionedWait = FlowStepControl.awaitTopicVersionedJson(
      'versioned-topic',
      const _SuspensionPayload(stage: 'versioned-wait'),
      version: 2,
      deadline: DateTime.parse('2025-01-01T00:00:01Z'),
    );

    expect(sleep.data, equals(const {'stage': 'sleeping'}));
    expect(
      sleep.dataJson<_SuspensionPayload>(decode: _SuspensionPayload.fromJson),
      isA<_SuspensionPayload>().having(
        (value) => value.stage,
        'stage',
        'sleeping',
      ),
    );
    expect(
      sleep.dataVersionedJson<_SuspensionPayload>(
        version: 2,
        decode: _SuspensionPayload.fromVersionedJson,
      ),
      isA<_SuspensionPayload>().having(
        (value) => value.stage,
        'stage',
        'sleeping',
      ),
    );
    expect(wait.data, equals(const {'stage': 'waiting'}));
    expect(wait.deadline, DateTime.parse('2025-01-01T00:00:00Z'));
    expect(versionedSleep.data, {
      PayloadCodec.versionKey: 2,
      'stage': 'versioned-sleep',
    });
    expect(versionedWait.data, {
      PayloadCodec.versionKey: 2,
      'stage': 'versioned-wait',
    });
  });
}

class _SuspensionPayload {
  const _SuspensionPayload({required this.stage});

  factory _SuspensionPayload.fromJson(Map<String, dynamic> json) {
    return _SuspensionPayload(stage: json['stage'] as String);
  }

  factory _SuspensionPayload.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _SuspensionPayload(stage: json['stage'] as String);
  }

  final String stage;

  Map<String, dynamic> toJson() => {'stage': stage};
}
