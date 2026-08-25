double profilePercentile(List<double> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index.clamp(0, sorted.length - 1).toInt()];
}

String? profileStringOption(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

int profileIntOption(List<String> args, String name, int fallback) {
  return int.tryParse(profileStringOption(args, name) ?? '') ?? fallback;
}
