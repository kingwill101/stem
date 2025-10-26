import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import '../security/tls.dart';

class PostgresClient {
  PostgresClient(
    String connectionString, {
    String? applicationName,
    TlsConfig? tls,
  }) : _connectionString = connectionString,
       _applicationName = applicationName,
       _tls = tls;

  final String _connectionString;
  final String? _applicationName;
  final TlsConfig? _tls;
  Connection? _connection;
  Future<void>? _opening;
  Future<void> _operationChain = Future<void>.value();

  Future<T> run<T>(Future<T> Function(Connection conn) action) {
    final completer = Completer<T>();
    _operationChain = _operationChain.then((_) async {
      try {
        final conn = await _ensureOpen();
        final result = await action(conn);
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> close() async {
    _operationChain = _operationChain.then((_) async {
      final conn = _connection;
      if (conn != null && conn.isOpen) {
        await conn.close();
      }
      _connection = null;
    });
    await _operationChain;
  }

  Future<Connection> _ensureOpen() async {
    final existing = _connection;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    if (_opening != null) {
      await _opening;
      return _connection!;
    }
    _opening = _openConnection();
    await _opening;
    _opening = null;
    return _connection!;
  }

  Future<void> _openConnection() async {
    final normalized = _normalizeConnectionUri(_connectionString);
    final withApplicationName = _applyApplicationName(normalized);
    final withTls = _applyTls(withApplicationName);
    _connection = await Connection.openFromUrl(withTls.toString());
  }

  Uri _normalizeConnectionUri(String connectionString) {
    var uri = Uri.parse(connectionString);
    final params = Map<String, String>.from(uri.queryParameters);
    final tls = _tls;
    final wantsTls = tls != null && (tls.isEnabled || tls.allowInsecure);
    if (uri.scheme == 'postgresql+ssl' || uri.scheme == 'postgres+ssl') {
      params.putIfAbsent('sslmode', () => 'require');
      uri = uri.replace(scheme: 'postgresql');
    } else if (!params.containsKey('sslmode')) {
      params['sslmode'] = wantsTls ? 'require' : 'disable';
    }
    return uri.replace(queryParameters: params.isEmpty ? null : params);
  }

  Uri _applyApplicationName(Uri uri) {
    final appName = _applicationName;
    if (appName == null || appName.isEmpty) {
      return uri;
    }
    final params = Map<String, String>.from(uri.queryParameters);
    params['application_name'] = appName;
    return uri.replace(queryParameters: params.isEmpty ? null : params);
  }

  Uri _applyTls(Uri uri) {
    final tls = _tls;
    if (tls == null || (!tls.isEnabled && !tls.allowInsecure)) {
      return uri;
    }

    final params = Map<String, String>.from(uri.queryParameters);

    String? normalizePath(String? value) {
      if (value == null || value.trim().isEmpty) return null;
      final trimmed = value.trim();
      if (p.isAbsolute(trimmed)) return p.normalize(trimmed);
      return p.normalize(p.join(Directory.current.path, trimmed));
    }

    void addParam(String key, String? value) {
      final normalized = normalizePath(value);
      if (normalized != null) {
        params[key] = normalized;
      }
    }

    final lowerMode = params['sslmode']?.toLowerCase();
    final shouldOverrideMode =
        lowerMode == null || lowerMode == 'disable' || lowerMode.isEmpty;

    if (shouldOverrideMode) {
      if (tls.allowInsecure) {
        params['sslmode'] = 'require';
      } else {
        params['sslmode'] = 'verify-full';
      }
    } else if (tls.allowInsecure && lowerMode == 'verify-full') {
      // Downgrade verify-full when caller explicitly allows insecure mode.
      params['sslmode'] = 'require';
    }

    addParam('sslrootcert', tls.caCertificateFile);
    addParam('sslcert', tls.clientCertificateFile);
    addParam('sslkey', tls.clientKeyFile);

    if (params['sslmode'] == 'verify-full' &&
        !params.containsKey('sslrootcert')) {
      params['sslmode'] = 'require';
    }

    return uri.replace(queryParameters: params.isEmpty ? null : params);
  }
}
