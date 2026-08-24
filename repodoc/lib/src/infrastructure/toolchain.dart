import 'dart:io';

/// Resolves the Dart and Flutter executables used by repodoc subprocesses.
final class Toolchain {
  Toolchain._();

  static Future<String?>? _flutterExecutableLookup;

  /// Returns the Flutter executable path, caching the PATH lookup.
  static Future<String?> flutterExecutable() {
    return _flutterExecutableLookup ??= _lookupFlutterExecutable();
  }

  /// Uses Flutter's pub frontend when Flutter is installed, otherwise Dart.
  static Future<String> pubTool() async {
    return await flutterExecutable() == null ? 'dart' : 'flutter';
  }

  /// Returns the Flutter SDK root for subprocess environment setup.
  static Future<String> flutterRoot() async {
    final executable = await flutterExecutable();
    if (executable == null) {
      throw StateError('Flutter executable was not found on PATH.');
    }
    final resolved = await File(executable).resolveSymbolicLinks();
    return Directory(resolved).parent.parent.path;
  }

  static Future<String?> _lookupFlutterExecutable() async {
    final lookup = await Process.run(Platform.isWindows ? 'where' : 'which', [
      'flutter',
    ]);
    if (lookup.exitCode != 0) return null;
    final firstLine = lookup.stdout.toString().trim().split('\n').first;
    return firstLine.isEmpty ? null : firstLine;
  }
}
