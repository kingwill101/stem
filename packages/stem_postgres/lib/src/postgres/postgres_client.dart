import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import 'package:stem/stem.dart';

/// Lightweight result wrapper to avoid exposing the postgres driver types.
class PostgresResult extends IterableBase<PostgresRow> {
  PostgresResult._(this._rows, this.affectedRows);

  /// Creates a result wrapper from a postgres [Result].
  factory PostgresResult.fromResult(Result result) {
    final rows = result
        .map((row) => PostgresRow(List<Object?>.from(row), row.toColumnMap()))
        .toList(growable: false);
    return PostgresResult._(rows, result.affectedRows);
  }

  final List<PostgresRow> _rows;

  /// Number of rows affected by the query.
  final int affectedRows;

  @override
  Iterator<PostgresRow> get iterator => _rows.iterator;

  @override
  int get length => _rows.length;
  @override
  bool get isEmpty => _rows.isEmpty;
  @override
  bool get isNotEmpty => _rows.isNotEmpty;
  @override
  PostgresRow get first => _rows.first;

  /// Returns the row at [index].
  PostgresRow operator [](int index) => _rows[index];
}

/// Row wrapper that exposes data by index or column name.
class PostgresRow {
  /// Creates a row wrapper from values and column mapping.
  PostgresRow(this._values, this._columnMap);

  final List<Object?> _values;
  final Map<String, Object?> _columnMap;

  /// Returns the value at [index].
  Object? operator [](int index) => _values[index];

  /// Returns the first column value.
  Object? get first => _values.first;

  /// Returns a map of column names to values.
  Map<String, Object?> toColumnMap() => _columnMap;
}

/// Postgres session wrapper used for executing queries.
class PostgresSession {
  /// Creates a session bound to a database connection.
  PostgresSession(this._connection);

  final Connection _connection;

  /// Executes [sql] with optional named [parameters].
  Future<PostgresResult> execute(
    String sql, {
    Map<String, Object?>? parameters,
  }) async {
    final result = await _connection.execute(
      Sql.named(sql),
      parameters: parameters,
    );
    return PostgresResult.fromResult(result);
  }
}

/// Serialized client for executing Postgres operations.
class PostgresClient {
  /// Creates a Postgres client with optional TLS settings.
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

  /// Runs [action] against a serialized session.
  Future<T> run<T>(Future<T> Function(PostgresSession session) action) {
    final completer = Completer<T>();
    _operationChain = _operationChain.then((_) async {
      try {
        final conn = await _ensureOpen();
        final result = await action(PostgresSession(conn));
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Closes the underlying connection after pending work completes.
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
