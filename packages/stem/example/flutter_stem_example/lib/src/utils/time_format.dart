String formatTimestamp(DateTime? value) {
  if (value == null) return 'none';
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}
