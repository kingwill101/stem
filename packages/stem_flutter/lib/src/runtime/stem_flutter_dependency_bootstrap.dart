import 'dart:async';

import 'package:flutter/services.dart';
import 'package:time_machine2/time_machine2.dart' as tm;

Future<void>? _foregroundInitialization;

/// Initializes Flutter-side dependency state needed before opening adapters.
Future<void> ensureStemFlutterDependenciesInitialized() {
  final pending = _foregroundInitialization;
  if (pending != null) return pending;

  final initialization = _initializeForegroundDependencies();
  _foregroundInitialization = initialization;
  return initialization;
}

Future<void> _initializeForegroundDependencies() async {
  try {
    await tm.TimeMachine.initialize(<String, dynamic>{
      'rootBundle': rootBundle,
    });
  } on Object {
    _foregroundInitialization = null;
    rethrow;
  }
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

class _StemFlutterDependencyAssetBundle extends CachingAssetBundle {
  _StemFlutterDependencyAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
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
}
