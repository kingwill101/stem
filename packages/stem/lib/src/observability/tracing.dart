import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as dotel_api;

/// Utilities for Stem's tracing integration (Dartastic OpenTelemetry).
class StemTracer {
  StemTracer._();

  static const _traceLinkHeader = 'stem.trace.link';
  static const _traceLinkStateHeader = 'stem.trace.link.state';

  /// Singleton instance used across the runtime.
  static final StemTracer instance = StemTracer._();

  dotel_api.APITracer get _tracer => _obtainTracer();

  bool get _isTelemetryReady => dotel_api.OTelFactory.otelFactory != null;

  dotel_api.Context _fallbackContext() => dotel_api.OTelAPI.context();

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
    List<dotel_api.SpanLink>? links,
    dotel.SpanKind spanKind = dotel.SpanKind.internal,
  }) async {
    if (!_isTelemetryReady) {
      return fn();
    }
    final tracer = _tracer;
    // Dartastic 0.10 exposes the SDK's no-processor fast path through the
    // tracer. Avoid allocating spans and attribute sets when the application
    // has intentionally disabled trace processors.
    if (!tracer.enabled) return fn();
    final attributeSet = attributes.isEmpty
        ? null
        : dotel.Attributes.of(Map<String, Object>.from(attributes));
    final baseContext = context ?? dotel.Context.current;
    final span = tracer.startSpan(
      name,
      context: baseContext,
      kind: spanKind,
      attributes: attributeSet,
      links: links,
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
    List<dotel_api.SpanLink>? links,
    dotel.SpanKind spanKind = dotel.SpanKind.internal,
  }) {
    if (!_isTelemetryReady) {
      return fn();
    }
    final tracer = _tracer;
    if (!tracer.enabled) return fn();
    final attributeSet = attributes.isEmpty
        ? null
        : dotel.Attributes.of(Map<String, Object>.from(attributes));
    final baseContext = context ?? dotel.Context.current;
    final span = tracer.startSpan(
      name,
      context: baseContext,
      kind: spanKind,
      attributes: attributeSet,
      links: links,
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
    final baseContext = context ?? dotel.Context.current;
    _globalPropagator?.inject(
      baseContext,
      headers,
      _StringMapSetter(headers),
    );
    if (!_traceContextPropagationEnabled) return;
    final spanContext = _spanContextFrom(baseContext);
    if (spanContext == null) return;

    final traceParent = _formatTraceparent(spanContext);
    if (traceParent == null || headers['traceparent'] != null) return;

    headers['traceparent'] = traceParent;

    final traceState = spanContext.traceState;
    if (traceState != null && traceState.entries.isNotEmpty) {
      headers['tracestate'] = traceState.toString();
    } else {
      headers.remove('tracestate');
    }
  }

  /// Adds the current span as a causal link for a later fan-out operation.
  ///
  /// This is separate from `traceparent`: a Canvas composition span remains
  /// the useful causal anchor even when a consumer also has a normal parent
  /// span. The header uses W3C traceparent formatting for interoperability.
  void injectTraceLink(
    Map<String, String> headers, {
    dotel.Context? context,
  }) {
    if (!_isTelemetryReady) return;
    final spanContext = _spanContextFrom(context ?? dotel.Context.current);
    if (spanContext == null) return;
    final traceParent = _formatTraceparent(spanContext);
    if (traceParent == null) return;
    headers[_traceLinkHeader] = traceParent;
    final traceState = spanContext.traceState;
    if (traceState != null && traceState.entries.isNotEmpty) {
      headers[_traceLinkStateHeader] = traceState.toString();
    } else {
      headers.remove(_traceLinkStateHeader);
    }
  }

  /// Extracts the optional Canvas fan-out link from task headers.
  List<dotel_api.SpanLink> extractTraceLinks(Map<String, String> headers) {
    if (!_isTelemetryReady) return const [];
    final traceParent = headers[_traceLinkHeader];
    if (traceParent == null) return const [];
    final traceHeaders = <String, String>{'traceparent': traceParent};
    final traceState = headers[_traceLinkStateHeader];
    if (traceState != null) traceHeaders['tracestate'] = traceState;
    final spanContext = _parseTraceContext(traceHeaders);
    if (spanContext == null) return const [];
    return [dotel.OTel.spanLink(spanContext)];
  }

  /// Extracts a trace context from [headers].
  dotel.Context extractTraceContext(
    Map<String, String> headers, {
    dotel.Context? context,
  }) {
    if (!_isTelemetryReady) {
      return context ?? _fallbackContext();
    }
    // Default to a fresh context when no explicit parent is supplied.
    // Using ambient context here can accidentally chain unrelated async
    // deliveries into one long trace when headers are missing traceparent.
    final baseContext = context ?? _fallbackContext();
    final propagated = _globalPropagator?.extract(
      baseContext,
      headers,
      _StringMapGetter(headers),
    );
    if (!_traceContextPropagationEnabled) return baseContext;
    if (propagated != null && _spanContextFrom(propagated) != null) {
      return propagated;
    }
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

  /// Returns the current ambient tracing context when telemetry is ready.
  ///
  /// Returns `null` if OpenTelemetry is not initialized or no ambient context
  /// can be resolved safely.
  dotel.Context? ambientContextOrNull() {
    if (!_isTelemetryReady) return null;
    try {
      return dotel.Context.current;
    } on Object {
      return null;
    }
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

  dotel_api.TextMapPropagator<dynamic, String>? get _globalPropagator {
    try {
      final propagator = dotel_api.OTelAPI.textMapPropagator;
      if (propagator.fields().isEmpty) return null;
      return propagator as dotel_api.TextMapPropagator<dynamic, String>;
    } on Object {
      return null;
    }
  }

  bool get _propagationDisabled {
    try {
      return dotel.OTelEnv.getPropagators().contains('none');
    } on Object {
      return false;
    }
  }

  bool get _traceContextPropagationEnabled {
    try {
      final propagators = dotel.OTelEnv.getPropagators();
      return !_propagationDisabled && propagators.contains('tracecontext');
    } on Object {
      // Preserve the legacy fallback if the optional environment integration
      // is unavailable in a platform implementation.
      return true;
    }
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

final class _StringMapGetter implements dotel_api.TextMapGetter<String> {
  const _StringMapGetter(this._headers);

  final Map<String, String> _headers;

  @override
  String? get(String key) => _headers[key];

  @override
  Iterable<String> keys() => _headers.keys;
}

final class _StringMapSetter extends dotel_api.TextMapSetter<String> {
  _StringMapSetter(this._headers);

  final Map<String, String> _headers;

  @override
  void set(String key, String value) {
    if ((key == 'traceparent' || key == 'tracestate') &&
        _headers.containsKey(key)) {
      return;
    }
    _headers[key] = value;
  }
}
