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

    test('valueJson decodes DTO values without a codec constant', () {
      final payload = <String, Object?>{
        'draft': const <String, Object?>{'documentId': 'doc-42'},
      };

      final draft = payload.valueJson<_ApprovalDraft>(
        'draft',
        decode: _ApprovalDraft.fromJson,
      );

      expect(draft?.documentId, 'doc-42');
    });

    test('valueVersionedJson decodes DTO values without a codec constant', () {
      final payload = <String, Object?>{
        'draft': const <String, Object?>{
          PayloadCodec.versionKey: 2,
          'documentId': 'doc-42',
        },
      };

      final draft = payload.valueVersionedJson<_ApprovalDraft>(
        'draft',
        defaultVersion: 2,
        decode: _ApprovalDraft.fromVersionedJson,
      );

      expect(draft?.documentId, 'doc-42');
    });

    test('requiredValueJson throws for missing payload keys', () {
      const payload = <String, Object?>{'name': 'Stem'};

      expect(
        () => payload.requiredValueJson<_ApprovalDraft>(
          'draft',
          decode: _ApprovalDraft.fromJson,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            "Missing required payload key 'draft'.",
          ),
        ),
      );
    });

    test('valueList reads typed scalar lists', () {
      const payload = <String, Object?>{
        'scores': [1, 2, 3],
      };

      expect(payload.valueList<int>('scores'), [1, 2, 3]);
      expect(payload.valueList<int>('missing'), isNull);
    });

    test('valueListOr returns fallback for missing lists', () {
      const payload = <String, Object?>{
        'scores': [1, 2, 3],
      };

      expect(payload.valueListOr<int>('scores', const [9]), [1, 2, 3]);
      expect(payload.valueListOr<int>('missing', const [9]), [9]);
    });

    test('requiredValueList throws for missing payload keys', () {
      const payload = <String, Object?>{'name': 'Stem'};

      expect(
        () => payload.requiredValueList<String>('labels'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            "Missing required payload key 'labels'.",
          ),
        ),
      );
    });

    test('requiredValueList decodes codec-backed DTO lists', () {
      final payload = <String, Object?>{
        'drafts': const [
          <String, Object?>{'documentId': 'doc-42'},
          <String, Object?>{'documentId': 'doc-99'},
        ],
      };

      final drafts = payload.requiredValueList<_ApprovalDraft>(
        'drafts',
        codec: _approvalDraftCodec,
      );

      expect(drafts.map((draft) => draft.documentId), ['doc-42', 'doc-99']);
    });

    test('valueListJson decodes DTO lists without a codec constant', () {
      final payload = <String, Object?>{
        'drafts': const [
          <String, Object?>{'documentId': 'doc-42'},
          <String, Object?>{'documentId': 'doc-99'},
        ],
      };

      final drafts = payload.valueListJson<_ApprovalDraft>(
        'drafts',
        decode: _ApprovalDraft.fromJson,
      );

      expect(
        drafts?.map((draft) => draft.documentId).toList(),
        ['doc-42', 'doc-99'],
      );
    });

    test(
      'valueListVersionedJson decodes DTO lists without a codec constant',
      () {
        final payload = <String, Object?>{
          'drafts': const [
            <String, Object?>{
              PayloadCodec.versionKey: 2,
              'documentId': 'doc-42',
            },
            <String, Object?>{
              PayloadCodec.versionKey: 2,
              'documentId': 'doc-99',
            },
          ],
        };

        final drafts = payload.valueListVersionedJson<_ApprovalDraft>(
          'drafts',
          defaultVersion: 2,
          decode: _ApprovalDraft.fromVersionedJson,
        );

        expect(
          drafts?.map((draft) => draft.documentId).toList(),
          ['doc-42', 'doc-99'],
        );
      },
    );

    test('requiredValueListJson throws for missing payload keys', () {
      const payload = <String, Object?>{'name': 'Stem'};

      expect(
        () => payload.requiredValueListJson<_ApprovalDraft>(
          'drafts',
          decode: _ApprovalDraft.fromJson,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            "Missing required payload key 'drafts'.",
          ),
        ),
      );
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

  factory _ApprovalDraft.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _ApprovalDraft(documentId: json['documentId'] as String);
  }

  final String documentId;

  Map<String, dynamic> toJson() => {'documentId': documentId};
}
