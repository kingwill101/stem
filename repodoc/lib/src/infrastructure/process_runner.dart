import 'dart:convert';
import 'dart:io';

final class ProcessRunner {
  ProcessRunner({this.environment, IOSink? out, IOSink? err})
    : out = out ?? stdout,
      err = err ?? stderr;

  final Map<String, String>? environment;
  final IOSink out;
  final IOSink err;

  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    Map<String, String>? environment,
    String? label,
  }) async {
    out.writeln('>>> ${label ?? _display(executable, arguments)}');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      environment: _mergeEnvironment(environment),
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      throw ProcessException(
        executable,
        arguments,
        'Command exited with status $code.',
        code,
      );
    }
    return code;
  }

  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      environment: _mergeEnvironment(environment),
    );
    final output = process.stdout.toString();
    if (process.exitCode == 0) return output;
    throw ProcessException(
      executable,
      arguments,
      '${process.stderr}\n$output',
      process.exitCode,
    );
  }

  String _display(String executable, List<String> arguments) {
    return [executable, ...arguments].map(_quote).join(' ');
  }

  Map<String, String>? _mergeEnvironment(Map<String, String>? overrides) {
    if (environment == null && overrides == null) return null;
    return {...?environment, ...?overrides};
  }

  String _quote(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(value)) return value;
    return jsonEncode(value);
  }
}
