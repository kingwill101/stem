import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as dotel_api;

/// Utilities for Stem's tracing integration (Dartastic OpenTelemetry).
class StemTracer {
  StemTracer._();

  /// Singleton instance used across the runtime.
  static final StemTracer instance = StemTracer._();

  dotel_api.APITracer get _tracer => _obtainTracer();

  bool get _isTelemetryReady => dotel_api.OTelFactory.otelFactory != null;

  dotel_api.Context _fallbackContext() => dotel_api.ContextCreate.create();

  static dotel_api.APITracer _obtainTracer() {
    try {
      return dotel.OTel.tracerProvider().getTracer('stem');
    } on Object catch (error) {
      if (error is TypeError || error is StateError) {
        if (dotel_api.OTelFactory.otelFactory == null) {
          dotel_api.OTelAPI.initialize();
        }
        return dotel_api.OTelAPI.tracerProvider().getTracer('stem');
      }
      rethrow;
    }
  }

  /// Runs [fn] within an async span named [name].
  Future<T> trace<T>(
    String name,
    Future<T> Function() fn, {
    dotel.Context? context,
    Map<String, Object> attributes = const {},
    dotel.SpanKind spanKind = dotel.SpanKind.internal,
  }) async {
    if (!_isTelemetryReady) {
      return fn();
    }
    final attributeSet = attributes.isEmpty
        ? null
        : dotel.Attributes.of(Map<String, Object>.from(attributes));
    final baseContext = context ?? dotel.Context.current;
    final tracer = _tracer;
    final span = tracer.startSpan(
      name,
      context: baseContext,
      kind: spanKind,
      attributes: attributeSet,
    );
    try {
      return await tracer.withSpanAsync(span, fn);
    } finally {
      span.end();
    }
  }

  /// Runs [fn] within a synchronous span named [name].
  T traceSync<T>(
    String name,
    T Function() fn, {
    dotel.Context? context,
    Map<String, Object> attributes = const {},
    dotel.SpanKind spanKind = dotel.SpanKind.internal,
  }) {
    if (!_isTelemetryReady) {
      return fn();
    }
    final attributeSet = attributes.isEmpty
        ? null
        : dotel.Attributes.of(Map<String, Object>.from(attributes));
    final baseContext = context ?? dotel.Context.current;
    final tracer = _tracer;
    final span = tracer.startSpan(
      name,
      context: baseContext,
      kind: spanKind,
      attributes: attributeSet,
    );
    try {
      return tracer.withSpan(span, fn);
    } finally {
      span.end();
    }
  }

  /// Injects the active trace context into [headers].
  void injectTraceContext(
    Map<String, String> headers, {
    dotel.Context? context,
  }) {
    if (!_isTelemetryReady) return;
    final spanContext = _spanContextFrom(context ?? dotel.Context.current);
    if (spanContext == null) return;

    final traceParent = _formatTraceparent(spanContext);
    if (traceParent == null) return;

    headers['traceparent'] = traceParent;

    final traceState = spanContext.traceState;
    if (traceState != null && traceState.entries.isNotEmpty) {
      headers['tracestate'] = traceState.toString();
    } else {
      headers.remove('tracestate');
    }
  }

  /// Extracts a trace context from [headers].
  dotel.Context extractTraceContext(
    Map<String, String> headers, {
    dotel.Context? context,
  }) {
    if (!_isTelemetryReady) {
      return context ?? _fallbackContext();
    }
    final baseContext = context ?? dotel.Context.current;
    final spanContext = _parseTraceContext(headers);
    if (spanContext == null) return baseContext;
    return baseContext.withSpanContext(spanContext);
  }

  /// Returns trace identifiers for inclusion in structured logs.
  Map<String, String> traceFields({dotel.Context? context}) {
    if (!_isTelemetryReady) return const {};
    final spanContext = _spanContextFrom(context ?? dotel.Context.current);
    if (spanContext == null || !spanContext.isValid) return const {};
    return {
      'traceId': spanContext.traceId.hexString,
      'spanId': spanContext.spanId.hexString,
    };
  }

  dotel.SpanContext? _spanContextFrom(dotel.Context context) {
    final span = context.span;
    if (span != null && span.spanContext.isValid) {
      return span.spanContext;
    }
    final spanContext = context.spanContext;
    if (spanContext != null && spanContext.isValid) {
      return spanContext;
    }
    return null;
  }

  String? _formatTraceparent(dotel.SpanContext spanContext) {
    if (!spanContext.isValid) return null;
    final traceId = spanContext.traceId.hexString;
    final spanId = spanContext.spanId.hexString;
    final flagsHex = spanContext.traceFlags.asByte
        .toRadixString(16)
        .padLeft(2, '0');
    return '00-$traceId-$spanId-$flagsHex';
  }

  dotel.SpanContext? _parseTraceContext(Map<String, String> headers) {
    final traceParent = headers['traceparent'];
    if (traceParent == null) return null;
    final parts = traceParent.trim().split('-');
    if (parts.length != 4) return null;

    final traceIdHex = parts[1];
    final spanIdHex = parts[2];
    final flagsHex = parts[3];

    if (traceIdHex.length != 32 ||
        spanIdHex.length != 16 ||
        flagsHex.length != 2) {
      return null;
    }

    try {
      final traceId = dotel.OTel.traceIdFrom(traceIdHex);
      final spanId = dotel.OTel.spanIdFrom(spanIdHex);
      final traceFlags = dotel.OTel.traceFlags(int.parse(flagsHex, radix: 16));
      final traceStateHeader = headers['tracestate'];
      final traceState = traceStateHeader == null || traceStateHeader.isEmpty
          ? null
          : dotel.TraceState.fromString(traceStateHeader);

      return dotel.OTel.spanContext(
        traceId: traceId,
        spanId: spanId,
        traceFlags: traceFlags,
        traceState: traceState,
        isRemote: true,
      );
    } on Object {
      return null;
    }
  }
}
