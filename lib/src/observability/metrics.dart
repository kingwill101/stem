import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as dotel_api;
import 'package:opentelemetry/api.dart' as otel;

/// Known metric aggregation types supported by the exporters.
enum MetricType { counter, histogram, gauge }

/// Immutable metric event emitted to exporters.
class MetricEvent {
  /// Creates a metric event and derives OpenTelemetry attributes from [tags].
  MetricEvent({
    required this.type,
    required this.name,
    required this.value,
    Map<String, String> tags = const {},
    DateTime? timestamp,
    this.unit,
  })  : tags = Map.unmodifiable(tags),
        timestamp = (timestamp ?? DateTime.now()).toUtc(),
        attributes = tags.entries
            .map((entry) => otel.Attribute.fromString(entry.key, entry.value))
            .toList();

  /// Type of aggregation represented by this event.
  final MetricType type;

  /// Metric identity used when exporting and aggregating.
  final String name;

  /// Measured value recorded for the metric.
  final double value;

  /// Immutable set of tag key/value pairs attached to the event.
  final Map<String, String> tags;

  /// UTC timestamp when the measurement was captured.
  final DateTime timestamp;

  /// Optional display unit for the recorded [value].
  final String? unit;

  /// Derived OpenTelemetry attributes used by OTLP exporters.
  final List<otel.Attribute> attributes;

  /// Encodes this metric event into a JSON map for transport.
  Map<String, Object> toJson() => {
        'type': type.name,
        'name': name,
        'value': value,
        'tags': tags,
        'timestamp': timestamp.toIso8601String(),
        if (unit != null) 'unit': unit!,
      };
}

/// Consumers implement exporters to relay metric events to specific sinks.
abstract class MetricsExporter {
  const MetricsExporter();

  /// Processes a single [event] from the registry.
  void record(MetricEvent event);

  /// Flushes buffered state, if any, to the downstream sink.
  Future<void> flush() async {}

  /// Releases held resources and performs final cleanup.
  Future<void> shutdown() async {}
}

/// Central registry that aggregates metrics before exporting them.
class StemMetrics {
  StemMetrics._();

  /// Singleton instance used by Stem workers.
  static final StemMetrics instance = StemMetrics._();

  /// Metrics exporters that receive emitted events.
  final List<MetricsExporter> _exporters = [];

  /// Tracked counters keyed by metric name and tag set.
  final Map<_MetricKey, _CounterState> _counters = {};

  /// Tracked histograms keyed by metric name and tag set.
  final Map<_MetricKey, _HistogramState> _histograms = {};

  /// Tracked gauges keyed by metric name and tag set.
  final Map<_MetricKey, _GaugeState> _gauges = {};

  /// Replaces the configured exporters with [exporters].
  void configure({List<MetricsExporter> exporters = const []}) {
    _exporters
      ..clear()
      ..addAll(exporters);
  }

  /// Registers an additional [exporter] without disturbing existing ones.
  void addExporter(MetricsExporter exporter) => _exporters.add(exporter);

  /// Increments the counter named [name] by [value] using optional [tags].
  void increment(
    String name, {
    Map<String, String> tags = const {},
    int value = 1,
  }) {
    final key = _MetricKey(name, tags);
    final counter = _counters.putIfAbsent(key, () => _CounterState(name, tags));
    counter.add(value);
    _emit(
      MetricEvent(
        type: MetricType.counter,
        name: name,
        value: value.toDouble(),
        tags: tags,
        unit: 'count',
      ),
    );
  }

  /// Records a histogram measurement for [name] using [duration].
  void recordDuration(
    String name,
    Duration duration, {
    Map<String, String> tags = const {},
  }) {
    final key = _MetricKey(name, tags);
    final histogram = _histograms.putIfAbsent(
      key,
      () => _HistogramState(name, tags),
    );
    final value = duration.inMicroseconds / 1000.0;
    histogram.record(value);
    _emit(
      MetricEvent(
        type: MetricType.histogram,
        name: name,
        value: value,
        tags: tags,
        unit: 'ms',
      ),
    );
  }

  /// Updates the gauge named [name] to [value].
  void setGauge(
    String name,
    double value, {
    Map<String, String> tags = const {},
  }) {
    final key = _MetricKey(name, tags);
    final gauge = _gauges.putIfAbsent(key, () => _GaugeState(name, tags));
    gauge.update(value);
    _emit(
      MetricEvent(type: MetricType.gauge, name: name, value: value, tags: tags),
    );
  }

  /// Returns a serializable representation of the aggregate state.
  Map<String, Object> snapshot() => {
        'counters':
            _counters.values.map((counter) => counter.toJson()).toList(),
        'histograms':
            _histograms.values.map((histogram) => histogram.toJson()).toList(),
        'gauges': _gauges.values.map((gauge) => gauge.toJson()).toList(),
      };

  /// Resets all internal aggregates.
  void reset() {
    _counters.clear();
    _histograms.clear();
    _gauges.clear();
  }

  /// Flushes all exporters concurrently.
  Future<void> flush() async {
    await Future.wait(_exporters.map((exporter) => exporter.flush()));
  }

  /// Shuts down all exporters concurrently.
  Future<void> shutdown() async {
    await Future.wait(_exporters.map((exporter) => exporter.shutdown()));
  }

  /// Emits [event] to each exporter while isolating failures.
  void _emit(MetricEvent event) {
    for (final exporter in _exporters) {
      try {
        exporter.record(event);
      } catch (_) {
        // Exporter errors are isolated so other outputs proceed.
      }
    }
  }
}

/// Mutable aggregate backing a counter metric.
class _CounterState {
  _CounterState(this.name, Map<String, String> tags)
      : tags = Map.unmodifiable(tags);

  /// Counter name.
  final String name;

  /// Tags describing this counter instance.
  final Map<String, String> tags;

  /// Total count accumulated so far.
  int value = 0;

  /// Adds [delta] to the running total.
  void add(int delta) => value += delta;

  /// Serializes the counter aggregate.
  Map<String, Object> toJson() => {'name': name, 'tags': tags, 'value': value};
}

/// Mutable aggregate backing a histogram metric.
class _HistogramState {
  _HistogramState(this.name, Map<String, String> tags)
      : tags = Map.unmodifiable(tags);

  /// Histogram name.
  final String name;

  /// Tags describing this histogram instance.
  final Map<String, String> tags;

  /// Number of recorded measurements.
  int count = 0;

  /// Sum of recorded measurements.
  double sum = 0;

  /// Minimum observed measurement.
  double min = double.infinity;

  /// Maximum observed measurement.
  double max = -double.infinity;

  /// Records [value] into the aggregate statistics.
  void record(double value) {
    count += 1;
    sum += value;
    if (value < min) min = value;
    if (value > max) max = value;
  }

  /// Serializes the histogram aggregate.
  Map<String, Object> toJson() => {
        'name': name,
        'tags': tags,
        'count': count,
        'sum': sum,
        'min': count == 0 ? 0 : min,
        'max': count == 0 ? 0 : max,
        'avg': count == 0 ? 0 : sum / count,
      };
}

/// Mutable aggregate backing a gauge metric.
class _GaugeState {
  _GaugeState(this.name, Map<String, String> tags)
      : tags = Map.unmodifiable(tags);

  /// Gauge name.
  final String name;

  /// Tags describing this gauge instance.
  final Map<String, String> tags;

  /// Latest gauge value.
  double value = 0;

  /// Timestamp when [value] was last updated.
  DateTime updatedAt = DateTime.now().toUtc();

  /// Sets the gauge [value] to [newValue].
  void update(double newValue) {
    value = newValue;
    updatedAt = DateTime.now().toUtc();
  }

  /// Serializes the gauge aggregate.
  Map<String, Object> toJson() => {
        'name': name,
        'tags': tags,
        'value': value,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// Lookup key combining metric name and tags.
class _MetricKey {
  _MetricKey(this.name, Map<String, String> tags)
      : tags = Map.unmodifiable(tags);

  /// Metric name.
  final String name;

  /// Normalized tags for this metric instance.
  final Map<String, String> tags;

  /// Hash code based on name and tag content.
  @override
  int get hashCode => Object.hash(name, const MapEquality().hash(tags));

  /// Equality compares both name and tags.
  @override
  bool operator ==(Object other) {
    return other is _MetricKey &&
        other.name == name &&
        const MapEquality<String, String>().equals(other.tags, tags);
  }
}

/// Simple exporter that prints JSON metrics to either [sink] or stdout.
class ConsoleMetricsExporter extends MetricsExporter {
  ConsoleMetricsExporter({this.sink});

  /// Optional sink used instead of stdout.
  final StringSink? sink;

  @override

  /// Writes the encoded [event] as a single JSON line.
  void record(MetricEvent event) {
    final line = jsonEncode(event.toJson());
    final target = sink;
    if (target != null) {
      target.writeln(line);
    } else {
      stdout.writeln(line);
    }
  }
}

/// Metrics exporter that relays events through Dartastic's OTLP pipeline.
class DartasticMetricsExporter extends MetricsExporter {
  DartasticMetricsExporter({
    required Uri endpoint,
    required String serviceName,
    Duration exportInterval = const Duration(seconds: 15),
  }) : _runtime = _DartasticMetricsRuntimeRegistry.instance.obtain(
          endpoint: endpoint,
          serviceName: serviceName,
          exportInterval: exportInterval,
        );

  final _DartasticMetricsRuntime _runtime;

  @override
  void record(MetricEvent event) {
    _runtime.record(event);
  }

  @override
  Future<void> flush() => _runtime.flush();

  @override
  Future<void> shutdown() => _runtime.flush();
}

/// Exporter that accumulates metrics into Prometheus exposition format.
class PrometheusMetricsExporter extends MetricsExporter {
  /// Cached samples keyed by metric identity and tag string.
  final Map<String, _PrometheusSample> _samples = {};

  @override

  /// Updates Prometheus-style aggregates for [event].
  void record(MetricEvent event) {
    final key = _PrometheusSample.keyFor(event);
    final sample = _samples.putIfAbsent(
      key,
      () => _PrometheusSample(event.name, event.tags, event.type),
    );
    sample.record(event.value);
  }

  /// Renders accumulated samples into the Prometheus text exposition format.
  String render() {
    final buffer = StringBuffer();
    for (final sample in _samples.values) {
      buffer.writeln(sample.render());
    }
    return buffer.toString();
  }
}

/// Holds intermediate aggregation state for a Prometheus sample.
class _PrometheusSample {
  _PrometheusSample(this.name, Map<String, String> tags, this.type)
      : tags = Map.unmodifiable(tags);

  /// Metric name written to the exposition output.
  final String name;

  /// Immutable labels associated with the metric sample.
  final Map<String, String> tags;

  /// Metric type guiding aggregation strategy.
  final MetricType type;

  /// Latest counter or gauge value.
  double value = 0;

  /// Cumulative sum for histogram values.
  double sum = 0;

  /// Total histogram samples recorded.
  int count = 0;

  /// Minimum histogram value (if any recorded).
  double min = double.infinity;

  /// Maximum histogram value (if any recorded).
  double max = -double.infinity;

  /// Generates a unique cache key for the supplied [event].
  static String keyFor(MetricEvent event) {
    final tags = event.tags.entries
        .map((entry) => '${entry.key}="${entry.value}"')
        .join(',');
    return '${event.name}{$tags}';
  }

  /// Records [measurement] into the Prometheus aggregate.
  void record(double measurement) {
    switch (type) {
      case MetricType.counter:
        value += measurement;
      case MetricType.gauge:
        value = measurement;
      case MetricType.histogram:
        sum += measurement;
        count += 1;
        if (measurement < min) min = measurement;
        if (measurement > max) max = measurement;
    }
  }

  /// Renders the aggregate into the Prometheus exposition format.
  String render() {
    final tagString =
        tags.entries.map((entry) => '${entry.key}="${entry.value}"').join(',');
    switch (type) {
      case MetricType.counter:
        return '$name{$tagString} $value';
      case MetricType.gauge:
        return '$name{$tagString} $value';
      case MetricType.histogram:
        final avg = count == 0 ? 0 : sum / count;
        return '${name}_sum{$tagString} $sum\n'
            '${name}_count{$tagString} $count\n'
            '${name}_min{$tagString} ${count == 0 ? 0 : min}\n'
            '${name}_max{$tagString} ${count == 0 ? 0 : max}\n'
            '${name}_avg{$tagString} $avg';
    }
  }
}

/// Registry caching Dartastic metric runtimes by endpoint/service key.
class _DartasticMetricsRuntimeRegistry {
  _DartasticMetricsRuntimeRegistry._();

  static final _DartasticMetricsRuntimeRegistry instance =
      _DartasticMetricsRuntimeRegistry._();

  final Map<_DartasticRuntimeKey, _DartasticMetricsRuntime> _runtimes = {};

  _DartasticMetricsRuntime obtain({
    required Uri endpoint,
    required String serviceName,
    required Duration exportInterval,
  }) {
    final key = _DartasticRuntimeKey(
      endpoint: endpoint,
      serviceName: serviceName,
      exportInterval: exportInterval,
    );
    return _runtimes.putIfAbsent(
      key,
      () => _DartasticMetricsRuntime(
        endpoint: endpoint,
        serviceName: serviceName,
        exportInterval: exportInterval,
      ),
    );
  }
}

/// Unique key for runtime lookup based on exporter configuration.
class _DartasticRuntimeKey {
  _DartasticRuntimeKey({
    required this.endpoint,
    required this.serviceName,
    required this.exportInterval,
  });

  final Uri endpoint;
  final String serviceName;
  final Duration exportInterval;

  @override
  int get hashCode =>
      Object.hash(endpoint.toString(), serviceName, exportInterval);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DartasticRuntimeKey &&
        other.endpoint == endpoint &&
        other.serviceName == serviceName &&
        other.exportInterval == exportInterval;
  }
}

/// Runtime that initializes Dartastic OTLP pipeline and records measurements.
class _DartasticMetricsRuntime {
  _DartasticMetricsRuntime({
    required this.endpoint,
    required this.serviceName,
    required this.exportInterval,
  }) {
    _ensureInitialized();
  }

  final Uri endpoint;
  final String serviceName;
  final Duration exportInterval;

  dotel_api.APIMeter? _meter;
  bool _initialized = false;
  Future<void>? _initializing;
  final List<MetricEvent> _buffer = [];
  final Map<String, dotel_api.APICounter<double>> _counters = {};
  final Map<String, dotel_api.APIHistogram<double>> _histograms = {};
  final Map<String, dotel_api.APIGauge<double>> _gauges = {};

  Future<void> _ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }
    if (_initializing != null) {
      return _initializing!;
    }
    return _initializing = _start();
  }

  Future<void> _start() async {
    try {
      final grpcEndpoint = _normaliseGrpcEndpoint(endpoint);
      final exporter = dotel.OtlpGrpcMetricExporter(
        dotel.OtlpGrpcMetricExporterConfig(
          endpoint: grpcEndpoint.toString(),
          insecure: grpcEndpoint.scheme != 'https',
        ),
      );
      final reader = dotel.PeriodicExportingMetricReader(
        exporter,
        interval: exportInterval,
      );
      await dotel.OTel.initialize(
        serviceName: serviceName,
        endpoint: grpcEndpoint.toString(),
        secure: grpcEndpoint.scheme == 'https',
        enableMetrics: true,
        metricExporter: exporter,
        metricReader: reader,
        spanProcessor: _NoopSpanProcessor(),
      );
      _meter = dotel.OTel.meterProvider().getMeter(name: 'stem');
      _initialized = true;
      if (_buffer.isNotEmpty) {
        final pending = List<MetricEvent>.from(_buffer);
        _buffer.clear();
        for (final event in pending) {
          _record(event);
        }
      }
    } catch (_) {
      // If initialization fails, keep events buffered for a later attempt.
      _initializing = null;
    }
  }

  void record(MetricEvent event) {
    if (!_initialized) {
      _buffer.add(event);
      _ensureInitialized();
      return;
    }

    if (_meter == null) {
      return;
    }

    _record(event);
  }

  void _record(MetricEvent event) {
    if (_meter == null) return;
    final instrumentName = _instrumentNameFor(event.name);
    final attributes = event.tags.isEmpty
        ? const <String, Object>{}
        : Map<String, Object>.from(event.tags);
    switch (event.type) {
      case MetricType.counter:
        final counter = _counters.putIfAbsent(instrumentName, () {
          return _meter!.createCounter<double>(
            name: instrumentName,
            unit: event.unit == 'count' ? null : event.unit,
          );
        });
        counter.addWithMap(event.value, attributes);
        break;
      case MetricType.histogram:
        final histogram = _histograms.putIfAbsent(instrumentName, () {
          return _meter!.createHistogram<double>(
            name: instrumentName,
            unit: _normalizedHistogramUnit(event.unit),
          );
        });
        histogram.recordWithMap(
          _normalizedHistogramValue(event.value, event.unit),
          attributes,
        );
        break;
      case MetricType.gauge:
        final gauge = _gauges.putIfAbsent(instrumentName, () {
          return _meter!.createGauge<double>(
            name: instrumentName,
            unit: event.unit,
          );
        });
        gauge.recordWithMap(event.value, attributes);
        break;
    }
  }

  Future<void> flush() async {
    await _ensureInitialized();
    await dotel.OTel.meterProvider().forceFlush();
  }
}

/// Span processor that drops all tracing data (metrics-only usage).
class _NoopSpanProcessor extends dotel.SpanProcessor {
  _NoopSpanProcessor();

  @override
  Future<void> onStart(dotel.Span span, dotel.Context? parentContext) async {}

  @override
  Future<void> onEnd(dotel.Span span) async {}

  @override
  Future<void> onNameUpdate(dotel.Span span, String newName) async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<void> forceFlush() async {}
}

Uri _normaliseGrpcEndpoint(Uri endpoint) {
  final useHttps = endpoint.scheme == 'https';
  final defaultPort = useHttps ? 443 : 80;
  var port = endpoint.hasPort ? endpoint.port : defaultPort;

  // Many configurations point at the HTTP OTLP port 4318 with a /v1/metrics path.
  // When using gRPC we need to target the gRPC port (4317) with no path.
  if (endpoint.path.contains('/v1/metrics') && port == 4318) {
    port = 4317;
  }

  return Uri(
    scheme: useHttps ? 'https' : 'http',
    host: endpoint.host,
    port: port,
  );
}

String _instrumentNameFor(String rawName) {
  var name = rawName;
  if (name.startsWith('stem.')) {
    name = name.substring('stem.'.length);
  }
  return name.replaceAll('.', '_');
}

double _normalizedHistogramValue(double value, String? unit) {
  if (unit == 'ms') {
    return value / 1000.0;
  }
  return value;
}

String? _normalizedHistogramUnit(String? unit) {
  if (unit == 'ms') {
    return 's';
  }
  return unit;
}
