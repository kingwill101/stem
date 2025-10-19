import 'package:opentelemetry/api.dart' as otel;

class StemTracer {
  StemTracer({otel.Tracer? tracer})
    : _tracer = tracer ?? otel.globalTracerProvider.getTracer('stem');

  final otel.Tracer _tracer;

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
