import 'package:stem_cli/src/cli/cloud_config.dart';
import 'package:test/test.dart';

void main() {
  group('cloud config helpers', () {
    test('resolveStemCloudAuthToken prefers non-empty override', () {
      final token = resolveStemCloudAuthToken({
        kStemCloudAccessTokenEnv: 'env-token',
        kStemCloudApiKeyEnv: 'api-key',
      }, override: '  override-token  ');

      expect(token, 'override-token');
    });

    test('resolveStemCloudApiKey falls back to API key env var', () {
      final token = resolveStemCloudApiKey({
        kStemCloudApiKeyEnv: 'api-key-value',
      });

      expect(token, 'api-key-value');
    });

    test('resolveStemCloudApiKey throws when no token sources are set', () {
      expect(
        () => resolveStemCloudApiKey(const {}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(kStemCloudAccessTokenEnv),
          ),
        ),
      );
    });

    test('resolveStemCloudNamespace uses configured fallback order', () {
      expect(
        resolveStemCloudNamespace({
          kStemNamespaceEnv: 'default-ns',
          kStemWorkerNamespaceEnv: 'worker-ns',
        }),
        'default-ns',
      );

      expect(
        resolveStemCloudNamespace({
          kStemCloudNamespaceEnv: '  cloud-ns  ',
          kStemNamespaceEnv: 'default-ns',
        }),
        'cloud-ns',
      );
    });
  });
}
