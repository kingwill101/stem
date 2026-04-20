import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:time_machine2/time_machine2.dart' as tm;

Future<void>? _foregroundInitialization;

/// Initializes Flutter-side dependency state needed before opening adapters.
Future<void> ensureStemFlutterDependenciesInitialized() {
  return _foregroundInitialization ??= tm.TimeMachine.initialize(
    <String, dynamic>{'rootBundle': rootBundle},
  );
}

/// Loads dependency assets that must be forwarded into background isolates.
Future<Map<String, Uint8List>> preloadStemFlutterDependencyAssets({
  AssetBundle? bundle,
}) async {
  final resolvedBundle = bundle ?? rootBundle;
  final cultures = await resolvedBundle.load(
    'packages/time_machine2/data/cultures/cultures.bin',
  );
  final tzdb = await resolvedBundle.load(
    'packages/time_machine2/data/tzdb/tzdb.bin',
  );
  return <String, Uint8List>{
    'cultures/cultures.bin': Uint8List.sublistView(cultures),
    'tzdb/tzdb.bin': Uint8List.sublistView(tzdb),
  };
}

/// Initializes Flutter-side dependency state inside a background isolate.
Future<void> initializeStemFlutterBackgroundDependencies(
  Map<String, Uint8List> assets,
) {
  return tm.TimeMachine.initialize(<String, dynamic>{
    'rootBundle': _StemFlutterDependencyAssetBundle(assets),
  });
}

class _StemFlutterDependencyAssetBundle {
  const _StemFlutterDependencyAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  Future<ByteData> load(String key) async {
    final normalized = key.startsWith('packages/time_machine2/data/')
        ? key.substring('packages/time_machine2/data/'.length)
        : key;
    final asset = assets[normalized];
    if (asset == null) {
      throw Exception('Missing Flutter asset: $key');
    }
    return ByteData.sublistView(asset);
  }

  Future<T> loadStructuredBinaryData<T>(
    String key,
    FutureOr<T> Function(ByteData data) parser,
  ) async {
    final data = await load(key);
    return parser(data);
  }

  Future<String> loadString(String key, {bool cache = true}) async {
    final data = await load(key);
    return utf8.decode(data.buffer.asUint8List());
  }
}
