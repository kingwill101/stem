import 'package:opentelemetry/api.dart' as otel;

/// Facade over the global OpenTelemetry tracer used by Stem workers.
class StemTracer {
  /// Creates a tracer that delegates to [tracer] or the global Stem tracer.
  StemTracer({otel.Tracer? tracer})
    : _tracer = tracer ?? otel.globalTracerProvider.getTracer('stem');

  /// Underlying tracer emitting spans.
  final otel.Tracer _tracer;

  /// Runs [body] within a new span named [name], recording errors as needed.
  ///
  /// The optional [attributes] map can be used to enrich the span in future
  /// instrumentation updates.
  R runSpan<R>(
    String name,
    R Function(otel.Span span) body, {
    Map<String, Object?> attributes = const {},
  }) {
    final span = _tracer.startSpan(name);
    try {
      final result = body(span);
      return result;
    } catch (error, stack) {
      span.recordException(error, stackTrace: stack);
      rethrow;
    } finally {
      span.end();
    }
  }
}
