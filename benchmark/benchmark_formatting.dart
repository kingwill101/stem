/// Converts a dynamic benchmark value to a numeric value when possible.
num? benchmarkNumber(Object? value) => value is num ? value : null;

/// Formats a benchmark number using compact, stable decimal thresholds.
String benchmarkFixed(Object? value) {
  final number = benchmarkNumber(value);
  if (number == null) return 'n/a';
  if (number.abs() >= 1000000) return number.toStringAsFixed(0);
  if (number.abs() >= 1000) return number.toStringAsFixed(1);
  if (number.abs() >= 1) return number.toStringAsFixed(2);
  return number.toStringAsFixed(3);
}
