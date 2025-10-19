import 'package:collection/collection.dart';

class StemMetrics {
  StemMetrics._();
  static final StemMetrics instance = StemMetrics._();

  final Map<String, _Counter> _counters = {};

  void increment(
    String name, {
    Map<String, String> tags = const {},
    int value = 1,
  }) {
    final key = _MetricKey(name, tags);
    _counters
        .putIfAbsent(key.toString(), () => _Counter(name, tags))
        .add(value);
  }

  Map<String, Object> snapshot() {
    return {'counters': _counters.values.map((c) => c.toJson()).toList()};
  }

  void reset() => _counters.clear();
}

class _Counter {
  _Counter(this.name, this.tags);

  final String name;
  final Map<String, String> tags;
  int value = 0;

  void add(int delta) => value += delta;

  Map<String, Object> toJson() => {'name': name, 'tags': tags, 'value': value};
}

class _MetricKey {
  _MetricKey(this.name, Map<String, String> tags)
    : tags = Map.unmodifiable(tags);
  final String name;
  final Map<String, String> tags;

  @override
  String toString() {
    final entries = tags.entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    return '$name:${entries.join(',')}';
  }

  @override
  bool operator ==(Object other) {
    return other is _MetricKey &&
        other.name == name &&
        const MapEquality<String, String>().equals(other.tags, tags);
  }

  @override
  int get hashCode =>
      Object.hash(name, const MapEquality<String, String>().hash(tags));
}
