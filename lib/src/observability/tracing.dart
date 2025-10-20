import 'package:opentelemetry/api.dart' as otel;

/// Utilities for Stem's tracing integration (OpenTelemetry).
class StemTracer {
  StemTracer._() : tracer = otel.globalTracerProvider.getTracer('stem');

  /// Singleton instance used across the runtime.
  static final StemTracer instance = StemTracer._();

  /// Underlying tracer emitting spans.
  final otel.Tracer tracer;

  final otel.TextMapPropagator _propagator = otel.W3CTraceContextPropagator();
  final _HeaderSetter _setter = _HeaderSetter();
  final _HeaderGetter _getter = _HeaderGetter();

  /// Runs [fn] within an async span named [name].
  Future<T> trace<T>(
    String name,
    Future<T> Function() fn, {
    otel.Context? context,
    List<otel.Attribute> attributes = const [],
    otel.SpanKind spanKind = otel.SpanKind.internal,
  }) {
    return otel.trace(
      name,
      fn,
      tracer: tracer,
      context: context,
      spanAttributes: attributes,
      spanKind: spanKind,
    );
  }

  /// Runs [fn] within a synchronous span named [name].
  T traceSync<T>(
    String name,
    T Function() fn, {
    otel.Context? context,
    List<otel.Attribute> attributes = const [],
    otel.SpanKind spanKind = otel.SpanKind.internal,
  }) {
    return otel.traceSync(
      name,
      fn,
      tracer: tracer,
      context: context,
      spanAttributes: attributes,
      spanKind: spanKind,
    );
  }

  /// Injects the active trace context into [headers].
  void injectTraceContext(
    Map<String, String> headers, {
    otel.Context? context,
  }) {
    _propagator.inject(context ?? otel.Context.current, headers, _setter);
  }

  /// Extracts a trace context from [headers].
  otel.Context extractTraceContext(
    Map<String, String> headers, {
    otel.Context? context,
  }) {
    return _propagator.extract(
      context ?? otel.Context.current,
      headers,
      _getter,
    );
  }

  /// Returns trace identifiers for inclusion in structured logs.
  Map<String, String> traceFields({otel.Context? context}) {
    final span = otel.spanFromContext(context ?? otel.Context.current);
    final spanContext = span.spanContext;
    if (!spanContext.isValid) return const {};
    return {
      'traceId': spanContext.traceId.toString(),
      'spanId': spanContext.spanId.toString(),
    };
  }
}

class _HeaderSetter implements otel.TextMapSetter<Map<String, String>> {
  @override
  void set(Map<String, String> carrier, String key, String value) {
    carrier[key] = value;
  }
}

class _HeaderGetter implements otel.TextMapGetter<Map<String, String>> {
  @override
  String? get(Map<String, String>? carrier, String key) =>
      carrier == null ? null : carrier[key];

  @override
  Iterable<String> keys(Map<String, String> carrier) => carrier.keys;
}
