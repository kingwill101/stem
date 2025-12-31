import 'dart:io';

import 'package:stem/src/observability/metrics.dart';
import 'package:stem/src/signals/stem_signals.dart';

/// Aggregates configuration controlling observability integrations.
class ObservabilityConfig {
  /// Creates a configuration with optional overrides for heartbeat cadence,
  /// namespace tagging, exporter selection, and OTLP endpoint.
  ObservabilityConfig({
    Duration? heartbeatInterval,
    String? namespace,
    List<String>? metricExporters,
    this.otlpEndpoint,
    StemSignalConfiguration? signalConfiguration,
  }) : heartbeatInterval = heartbeatInterval ?? const Duration(seconds: 10),
       namespace = (namespace != null && namespace.isNotEmpty)
           ? namespace
           : 'stem',
       metricExporters = List.unmodifiable(metricExporters ?? const []),
       signalConfiguration =
           signalConfiguration ?? const StemSignalConfiguration();

  /// Builds a configuration by reading relevant environment variables from
  /// [env] or the process environment.
  factory ObservabilityConfig.fromEnvironment([Map<String, String>? env]) {
    final environment = env ?? Platform.environment;
    final interval =
        parseDuration(environment[_EnvKeys.heartbeatInterval]) ??
        const Duration(seconds: 10);
    final namespace = environment[_EnvKeys.namespace]?.trim();
    final exportersRaw = environment[_EnvKeys.metricExporters] ?? '';
    final exporters = exportersRaw
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    final otlpRaw = environment[_EnvKeys.otlpEndpoint]?.trim();
    final otlp = otlpRaw != null && otlpRaw.isNotEmpty
        ? Uri.tryParse(otlpRaw)
        : null;
    final signalsEnabled = _parseBool(environment[_EnvKeys.signalsEnabled]);
    final disabledSignals = _parseList(environment[_EnvKeys.signalsDisabled]);
    final signalConfig = StemSignalConfiguration(
      enabled: signalsEnabled ?? true,
      enabledSignals: {for (final name in disabledSignals) name: false},
    );
    return ObservabilityConfig(
      heartbeatInterval: interval,
      namespace: namespace,
      metricExporters: exporters,
      otlpEndpoint: otlp,
      signalConfiguration: signalConfig,
    );
  }

  /// Interval between worker heartbeats emitted for monitoring.
  final Duration heartbeatInterval;

  /// Namespace tag applied to worker observability signals.
  final String namespace;

  /// Immutable list of exporter specifications (e.g. `console`, `prometheus`).
  final List<String> metricExporters;

  /// Explicit endpoint override for OTLP-compatible exporters.
  final Uri? otlpEndpoint;

  /// Signal dispatch configuration describing enablement flags.
  final StemSignalConfiguration signalConfiguration;

  /// Returns a copy of this configuration with values replaced by [other].
  ObservabilityConfig merge(ObservabilityConfig other) {
    return ObservabilityConfig(
      heartbeatInterval: other.heartbeatInterval,
      namespace: other.namespace,
      metricExporters: other.metricExporters.isEmpty
          ? metricExporters
          : other.metricExporters,
      otlpEndpoint: other.otlpEndpoint ?? otlpEndpoint,
      signalConfiguration: other.signalConfiguration,
    );
  }

  /// Configures [StemMetrics] using the exporters defined on this instance.
  void applyMetricExporters() {
    if (metricExporters.isEmpty) return;
    final exporters = <MetricsExporter>[];
    for (final spec in metricExporters) {
      final normalized = spec.trim();
      if (normalized.isEmpty) continue;
      if (normalized.toLowerCase() == 'console') {
        exporters.add(ConsoleMetricsExporter());
        continue;
      }
      if (normalized.toLowerCase() == 'prometheus') {
        exporters.add(PrometheusMetricsExporter());
        continue;
      }
      if (normalized.toLowerCase().startsWith('otlp')) {
        final endpoint = _endpointFromSpec(normalized) ?? otlpEndpoint;
        if (endpoint != null) {
          exporters.add(
            DartasticMetricsExporter(
              endpoint: endpoint,
              serviceName: namespace,
            ),
          );
        }
      }
    }
    if (exporters.isNotEmpty) {
      StemMetrics.instance.configure(exporters: exporters);
    }
  }

  /// Applies signal configuration globally.
  void applySignalConfiguration() {
    StemSignals.configure(configuration: signalConfiguration);
  }

  /// Parses an OTLP endpoint out of a single exporter [spec] string.
  Uri? _endpointFromSpec(String spec) {
    final separator = spec.indexOf(':');
    if (separator == -1) return null;
    final prefix = spec.substring(0, separator).toLowerCase();
    if (prefix != 'otlp') return null;
    final target = spec.substring(separator + 1).trim();
    if (target.isEmpty) return null;
    return Uri.tryParse(target);
  }

  /// Parses a simple duration token such as `500ms`, `10s`, or `2m`.
  static Duration? parseDuration(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final match = RegExp(r'^(\d+)(ms|s|m)?$').firstMatch(value);
    if (match == null) return null;
    final amount = int.parse(match.group(1)!);
    final unit = match.group(2) ?? 's';
    switch (unit) {
      case 'ms':
        return Duration(milliseconds: amount);
      case 's':
        return Duration(seconds: amount);
      case 'm':
        return Duration(minutes: amount);
      default:
        return null;
    }
  }
}

/// Names for environment variables that feed [ObservabilityConfig].
abstract class _EnvKeys {
  static const heartbeatInterval = 'STEM_HEARTBEAT_INTERVAL';
  static const namespace = 'STEM_WORKER_NAMESPACE';
  static const metricExporters = 'STEM_METRIC_EXPORTERS';
  static const otlpEndpoint = 'STEM_OTLP_ENDPOINT';
  static const signalsEnabled = 'STEM_SIGNALS_ENABLED';
  static const signalsDisabled = 'STEM_SIGNALS_DISABLED';
}

bool? _parseBool(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}

List<String> _parseList(String? input) {
  if (input == null || input.trim().isEmpty) return const [];
  final seen = <String>{};
  final values = <String>[];
  for (final part in input.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) {
      values.add(trimmed);
    }
  }
  return values;
}
