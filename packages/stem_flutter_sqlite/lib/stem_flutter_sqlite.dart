/// Durable local storage for the ordinary Stem application API in Flutter.
///
/// `StemFlutterSqlite.createApp` returns a core `StemApp`. Task execution,
/// observation, and resource ownership follow the core application lifecycle.
library;

export 'package:stem_flutter/stem_flutter.dart';

export 'src/runtime/stem_flutter_sqlite.dart'
    show StemFlutterSqlite, StemFlutterSqliteConfig;
export 'src/runtime/stem_flutter_storage_layout.dart'
    show StemFlutterStorageLayout;
