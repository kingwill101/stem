import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:stem/stable.dart';

/// Creates a host for [WorkflowHostController].
typedef WorkflowHostFactory = Future<WorkflowHost> Function();

/// Flutter lifecycle owner for a workflow host.
///
/// A host supplied directly is borrowed. A host returned by [factory] is
/// owned and is closed by [close]. Recovery is deliberately limited to startup
/// and foreground transitions; pausing the application never cancels work.
final class WorkflowHostController extends ChangeNotifier {
  /// Creates a controller around an owned factory host or borrowed [host].
  WorkflowHostController({
    WorkflowHost? host,
    WorkflowHostFactory? factory,
    this.recoveryLimit = 100,
    this.onError,
  }) : assert(
         (host == null) != (factory == null),
         'Provide exactly one of host or factory.',
       ),
       _host = host,
       _factory = factory,
       _ownsHost = factory != null {
    if ((host == null) == (factory == null)) {
      throw ArgumentError('Provide exactly one of host or factory.');
    }
    if (recoveryLimit <= 0) {
      throw ArgumentError.value(
        recoveryLimit,
        'recoveryLimit',
        'Must be positive.',
      );
    }
  }

  final WorkflowHostFactory? _factory;
  WorkflowHost? _host;
  final bool _ownsHost;

  /// Maximum number of persisted runs passed to core recovery.
  final int recoveryLimit;

  /// Receives startup, recovery, and unawaited disposal errors.
  ///
  /// Reporter failures are logged without replacing the original state error.
  final void Function(Object error, StackTrace stack)? onError;

  Object? _error;
  StackTrace? _errorStack;
  WorkflowRecoveryReport? _recoveryReport;
  Future<void>? _startup;
  Future<void>? _recovery;
  Future<void>? _closing;
  bool _disposed = false;
  bool _closed = false;
  bool _started = false;

  /// The started host, or null while a factory is starting/after close.
  WorkflowHost? get host => _closed ? null : _host;

  /// The latest startup or recovery error.
  Object? get error => _error;

  /// Stack trace associated with [error].
  StackTrace? get errorStack => _errorStack;

  /// The latest core recovery report.
  WorkflowRecoveryReport? get recoveryReport => _recoveryReport;

  /// Whether an async factory is currently creating the host.
  bool get isLoading => _startup != null && _host == null;

  /// Whether close has completed or begun.
  bool get isClosed => _closed;

  /// Starts once and performs initial recovery.
  /// A failed factory may be retried.
  ///
  /// Calls after close are harmless no-ops, as late lifecycle events can arrive
  /// during widget teardown.
  Future<void> start() {
    if (_closed || _started) return Future<void>.value();
    if (_startup != null) return _startup!;
    late final Future<void> startup;
    startup = Future<void>.microtask(_start).whenComplete(() {
      if (identical(_startup, startup)) _startup = null;
      _notify();
    });
    _startup = startup;
    _notify();
    return startup;
  }

  Future<void> _start() async {
    if (_closed) return;
    try {
      _host ??= await _factory!();
      if (_closed) return;
      _started = true;
      _notify();
      await recover();
    } on Object catch (error, stack) {
      _setError(error, stack);
    }
  }

  /// Coalesces concurrent recovery requests into one host operation.
  Future<void> recover() {
    final existing = _recovery;
    if (existing != null) return existing;
    final host = _host;
    if (host == null || _closed) return Future<void>.value();
    late final Future<void> operation;
    operation = Future<void>.microtask(() => _recover(host)).whenComplete(() {
      if (identical(_recovery, operation)) _recovery = null;
    });
    _recovery = operation;
    return operation;
  }

  Future<void> _recover(WorkflowHost host) async {
    try {
      _recoveryReport = await host.recover(limit: recoveryLimit);
      _clearError();
      _notify();
    } on Object catch (error, stack) {
      _setError(error, stack);
    }
  }

  void _setError(Object error, StackTrace stack) {
    _error = error;
    _errorStack = stack;
    _report(error, stack);
    _notify();
  }

  void _clearError() {
    _error = null;
    _errorStack = null;
  }

  void _report(Object error, StackTrace stack) {
    if (onError != null) {
      try {
        onError!(error, stack);
      } on Object catch (reporterError, reporterStack) {
        developer.log(
          'WorkflowHostController error reporter failed.',
          name: 'stem_flutter.workflow_host',
          error: reporterError,
          stackTrace: reporterStack,
        );
      }
    } else {
      developer.log(
        'WorkflowHostController error.',
        name: 'stem_flutter.workflow_host',
        error: error,
        stackTrace: stack,
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Closes an owned host. Borrowed hosts are left untouched.
  Future<void> close() {
    return _closing ??= _close();
  }

  Future<void> _close() async {
    _closed = true;
    try {
      final startup = _startup;
      if (startup != null) await startup;
      final recovery = _recovery;
      if (recovery != null) await recovery;
      final host = _host;
      if (host != null && _ownsHost) await host.close();
    } finally {
      _host = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // ChangeNotifier.dispose cannot be async. The error handler makes this
    // deliberate rather than creating an unobserved future.
    unawaited(
      close().catchError(_report),
    );
    super.dispose();
  }
}
