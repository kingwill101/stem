import 'dart:io';

import 'package:stem/stem.dart';
// import 'package:stem_cloud_worker/stem_cloud_worker.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

/// Creates a [RevokeStore] based on configuration and URL overrides.
class RevokeStoreFactory {
  const RevokeStoreFactory._();

  static Future<RevokeStore> create({
    required StemConfig config,
    String? urlOverride,
    String namespace = 'stem',
    Map<String, String>? environment,
    String? cloudApiKey,
    String? cloudNamespace,
  }) async {
    final candidate = _resolveUrl(config, urlOverride);
    if (candidate == null || candidate.isEmpty) {
      final path = File('revokes.stem').absolute.path;
      return FileRevokeStore.open(path);
    }

    final _ = environment ?? const <String, String>{};
    final uri = Uri.parse(candidate);
    switch (uri.scheme) {
      case 'memory':
        return InMemoryRevokeStore();
      case 'file':
      case '':
        final path = uri.scheme == 'file'
            ? uri.toFilePath()
            : uri.path.isEmpty
            ? candidate
            : uri.path;
        return FileRevokeStore.open(path);
      case 'redis':
      case 'rediss':
        return RedisRevokeStore.connect(
          candidate,
          namespace: namespace,
          tls: config.tls,
        );
      case 'postgres':
      case 'postgresql':
      case 'postgres+ssl':
      case 'postgresql+ssl':
        return PostgresRevokeStore.connect(
          candidate,
          namespace: namespace,
          applicationName: 'stem-revoke-store',
          tls: config.tls,
        );
      // case 'http':
      // case 'https':
      //   return StemCloudRevokeStore.connect(
      //     apiBase: uri,
      //     apiKey: resolveStemCloudApiKey(env, override: cloudApiKey),
      //     namespace: cloudNamespace ?? resolveStemCloudNamespace(env),
      //   );
      default:
        throw StateError('Unsupported revoke store scheme: ${uri.scheme}');
    }
  }

  static String? _resolveUrl(StemConfig config, String? urlOverride) {
    if (urlOverride != null && urlOverride.trim().isNotEmpty) {
      return urlOverride.trim();
    }
    if (config.revokeStoreUrl != null && config.revokeStoreUrl!.isNotEmpty) {
      return config.revokeStoreUrl;
    }
    if (config.resultBackendUrl != null &&
        config.resultBackendUrl!.isNotEmpty) {
      return config.resultBackendUrl;
    }
    return config.brokerUrl;
  }
}
