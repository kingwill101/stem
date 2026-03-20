import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('PayloadMapX', () {
    test('value reads typed scalar values', () {
      const payload = <String, Object?>{'name': 'Stem'};

      expect(payload.value<String>('name'), 'Stem');
      expect(payload.value<int>('missing'), isNull);
    });

    test('valueOr returns fallback for missing values', () {
      const payload = <String, Object?>{'name': 'Stem'};

      expect(payload.valueOr<String>('name', 'fallback'), 'Stem');
      expect(payload.valueOr<String>('tenant', 'global'), 'global');
    });

    test('requiredValue throws for missing payload keys', () {
      const payload = <String, Object?>{'name': 'Stem'};

      expect(
        () => payload.requiredValue<String>('tenant'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            "Missing required payload key 'tenant'.",
          ),
        ),
      );
    });

    test('requiredValue decodes codec-backed DTO values', () {
      final payload = <String, Object?>{
        'draft': const <String, Object?>{'documentId': 'doc-42'},
      };

      final draft = payload.requiredValue<_ApprovalDraft>(
        'draft',
        codec: _approvalDraftCodec,
      );

      expect(draft.documentId, 'doc-42');
    });
  });
}

const _approvalDraftCodec = PayloadCodec<_ApprovalDraft>.json(
  decode: _ApprovalDraft.fromJson,
);

class _ApprovalDraft {
  const _ApprovalDraft({required this.documentId});

  factory _ApprovalDraft.fromJson(Map<String, dynamic> json) {
    return _ApprovalDraft(documentId: json['documentId'] as String);
  }

  final String documentId;

  Map<String, dynamic> toJson() => {'documentId': documentId};
}
