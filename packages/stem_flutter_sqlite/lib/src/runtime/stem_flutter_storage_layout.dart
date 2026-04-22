import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// File layout for a Flutter-hosted Stem SQLite runtime.
///
/// Use this type to keep the broker and result backend in separate files while
/// still resolving them from a single application-owned directory.
class StemFlutterStorageLayout {
  /// Creates a storage layout rooted at [root].
  const StemFlutterStorageLayout({
    required this.root,
    required this.brokerFile,
    required this.backendFile,
  });

  /// Root directory that holds Stem runtime files.
  final Directory root;

  /// SQLite file used by the broker.
  final File brokerFile;

  /// SQLite file used by the result backend.
  final File backendFile;

  /// Resolves a layout under Flutter's application support directory.
  static Future<StemFlutterStorageLayout> applicationSupport({
    String directoryName = 'stem_flutter',
    String brokerFileName = 'broker.sqlite',
    String backendFileName = 'backend.sqlite',
  }) async {
    final baseDirectory = await getApplicationSupportDirectory();
    final root = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}$directoryName',
    );
    return forRoot(
      root,
      brokerFileName: brokerFileName,
      backendFileName: backendFileName,
    );
  }

  /// Creates a layout from an explicit [root] directory.
  static Future<StemFlutterStorageLayout> forRoot(
    Directory root, {
    String brokerFileName = 'broker.sqlite',
    String backendFileName = 'backend.sqlite',
  }) async {
    await root.create(recursive: true);
    return StemFlutterStorageLayout(
      root: root,
      brokerFile: File('${root.path}${Platform.pathSeparator}$brokerFileName'),
      backendFile: File(
        '${root.path}${Platform.pathSeparator}$backendFileName',
      ),
    );
  }
}
