import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final lcovFile = File(options.lcovPath);
  if (!await lcovFile.exists()) {
    stderr.writeln('LCOV file not found: ${options.lcovPath}');
    exitCode = 66;
    return;
  }

  final lines = await lcovFile.readAsLines();
  var linesFound = 0;
  var linesHit = 0;

  for (final line in lines) {
    if (line.startsWith('LF:')) {
      linesFound += _parseMetric(line, prefixLength: 3);
    } else if (line.startsWith('LH:')) {
      linesHit += _parseMetric(line, prefixLength: 3);
    }
  }

  final coverage = linesFound == 0 ? 0.0 : (linesHit / linesFound) * 100.0;
  final message = '${_formatCoverage(coverage)}%';
  final badge = <String, Object>{
    'schemaVersion': 1,
    'label': 'coverage',
    'message': message,
    'color': _coverageColor(coverage),
  };

  final outputFile = File(options.outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(badge) + '\n',
  );

  stdout.writeln('Coverage: $message (lines hit $linesHit / $linesFound)');

  if (coverage + 1e-9 < options.minimumCoverage) {
    stderr.writeln(
      'Coverage $message is below the minimum '
      '${options.minimumCoverage.toStringAsFixed(2)}%.',
    );
    exitCode = 1;
  }
}

int _parseMetric(String line, {required int prefixLength}) {
  if (line.length <= prefixLength) return 0;
  return int.tryParse(line.substring(prefixLength).trim()) ?? 0;
}

String _formatCoverage(double value) {
  final rounded = (value * 100).roundToDouble() / 100;
  final formatted = rounded.toStringAsFixed(2);
  if (formatted.endsWith('00')) {
    return rounded.toStringAsFixed(0);
  }
  if (formatted.endsWith('0')) {
    return rounded.toStringAsFixed(1);
  }
  return formatted;
}

String _coverageColor(double coverage) {
  if (coverage >= 90) return 'brightgreen';
  if (coverage >= 80) return 'green';
  if (coverage >= 70) return 'yellow';
  if (coverage >= 60) return 'orange';
  return 'red';
}

_Options? _parseArgs(List<String> args) {
  String? lcovPath;
  String? outputPath;
  double? minimumCoverage;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      return null;
    }
    if (arg.startsWith('--lcov=')) {
      lcovPath = arg.substring('--lcov='.length);
      continue;
    }
    if (arg == '--lcov' && i + 1 < args.length) {
      lcovPath = args[++i];
      continue;
    }
    if (arg.startsWith('--out=')) {
      outputPath = arg.substring('--out='.length);
      continue;
    }
    if (arg == '--out' && i + 1 < args.length) {
      outputPath = args[++i];
      continue;
    }
    if (arg.startsWith('--min=')) {
      minimumCoverage = double.tryParse(arg.substring('--min='.length));
      continue;
    }
    if (arg == '--min' && i + 1 < args.length) {
      minimumCoverage = double.tryParse(args[++i]);
      continue;
    }

    stderr.writeln('Unknown argument: $arg');
    return null;
  }

  if (lcovPath == null || outputPath == null || minimumCoverage == null) {
    return null;
  }

  return _Options(
    lcovPath: lcovPath,
    outputPath: outputPath,
    minimumCoverage: minimumCoverage,
  );
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/coverage/coverage_badge.dart '
    '--lcov <path> --out <path> --min <percent>',
  );
}

class _Options {
  const _Options({
    required this.lcovPath,
    required this.outputPath,
    required this.minimumCoverage,
  });

  final String lcovPath;
  final String outputPath;
  final double minimumCoverage;
}
