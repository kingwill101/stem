import '../core/contracts.dart';
import '../core/envelope.dart';

/// Record describing an enqueued task captured by [FakeStem].
class RecordedEnqueue {
  RecordedEnqueue({
    required this.id,
    required this.name,
    required this.args,
    required this.headers,
    required this.options,
    required this.notBefore,
    required this.meta,
    required this.enqueuedAt,
    this.call,
  });

  final String id;
  final String name;
  final Map<String, Object?> args;
  final Map<String, String> headers;
  final TaskOptions options;
  final DateTime? notBefore;
  final Map<String, Object?> meta;
  final DateTime enqueuedAt;
  final TaskCall<dynamic, dynamic>? call;
}

/// Test helper that records enqueue calls without publishing to a broker.
class FakeStem {
  FakeStem();

  final List<RecordedEnqueue> _enqueues = [];

  /// All enqueued tasks captured so far.
  List<RecordedEnqueue> get enqueues => List.unmodifiable(_enqueues);

  /// Clears recorded enqueue history.
  void reset() => _enqueues.clear();

  /// Mimics [Stem.enqueueCall] and records the request.
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call,
  ) async {
    final options = call.resolveOptions();
    final id = generateEnvelopeId();
    _enqueues.add(
      RecordedEnqueue(
        id: id,
        name: call.name,
        args: call.encodeArgs(),
        headers: Map<String, String>.from(call.headers),
        options: options,
        notBefore: call.notBefore,
        meta: Map<String, Object?>.from(call.meta),
        enqueuedAt: DateTime.now(),
        call: call,
      ),
    );
    return id;
  }

  /// Mimics [Stem.enqueue] for map-based usage.
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
  }) async {
    final id = generateEnvelopeId();
    _enqueues.add(
      RecordedEnqueue(
        id: id,
        name: name,
        args: Map<String, Object?>.from(args),
        headers: Map<String, String>.from(headers),
        options: options,
        notBefore: notBefore,
        meta: Map<String, Object?>.from(meta),
        enqueuedAt: DateTime.now(),
      ),
    );
    return id;
  }
}
