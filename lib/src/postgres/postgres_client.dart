import 'dart:async';
import 'package:postgres/postgres.dart';

class PostgresClient {
  PostgresClient(String connectionString, {String? applicationName})
      : _connectionString = connectionString,
        _applicationName = applicationName;

  final String _connectionString;
  final String? _applicationName;
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
    _connection = await Connection.openFromUrl(withApplicationName.toString());
  }

  Uri _normalizeConnectionUri(String connectionString) {
    var uri = Uri.parse(connectionString);
    final params = Map<String, String>.from(uri.queryParameters);
    if (uri.scheme == 'postgresql+ssl' || uri.scheme == 'postgres+ssl') {
      params.putIfAbsent('sslmode', () => 'require');
      uri = uri.replace(scheme: 'postgresql');
    } else if (!params.containsKey('sslmode')) {
      params['sslmode'] = 'disable';
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
}
