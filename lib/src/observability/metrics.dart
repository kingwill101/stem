import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
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
  }) : tags = Map.unmodifiable(tags),
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
    'counters': _counters.values.map((counter) => counter.toJson()).toList(),
    'histograms': _histograms.values
        .map((histogram) => histogram.toJson())
        .toList(),
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

/// OTLP HTTP exporter that POSTs each event to [endpoint].
class OtlpHttpMetricsExporter extends MetricsExporter {
  OtlpHttpMetricsExporter(this.endpoint);

  /// Destination OTLP endpoint accepting HTTP POST requests.
  final Uri endpoint;

  /// Client reused across requests to avoid reconnect overhead.
  final _client = HttpClient();

  @override
  /// Sends [event] asynchronously without blocking the caller.
  void record(MetricEvent event) {
    unawaited(_send(event));
  }

  /// Performs the HTTP POST for [event], swallowing network failures.
  Future<void> _send(MetricEvent event) async {
    try {
      final request = await _client.postUrl(endpoint);
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode(event.toJson()));
      await request.close();
    } catch (_) {
      // swallow network errors to avoid impacting worker loops
    }
  }

  @override
  /// Closes the underlying HTTP client.
  Future<void> shutdown() async {
    _client.close(force: true);
  }
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
    final tagString = tags.entries
        .map((entry) => '${entry.key}="${entry.value}"')
        .join(',');
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
