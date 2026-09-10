import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:image/image.dart' as img;
import 'package:stem_flutter/stem_flutter.dart';

void main() {
  late Directory directory;
  PhotoTaskArgs args({
    int index = 0,
    int width = 96,
    int height = 64,
    String batchId = 'test-batch',
  }) => PhotoTaskArgs(
    outputDirectory: directory.path,
    batchId: batchId,
    index: index,
    width: width,
    height: height,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stem-photo-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'module executes isolated photo task and reuses verified artifacts',
    () async {
      final app = await StemApp.inMemory(
        module: demoModule,
        workerConfig: StemFlutter.defaultWorkerConfig,
      );
      addTearDown(app.close);
      await app.start();
      Future<Map<String, Object?>> run() async {
        final id = await app.enqueueCall(preparePhoto.buildCall(args()));
        final result = await preparePhoto.waitFor(
          app,
          id,
          timeout: const Duration(seconds: 20),
        );
        expect(result?.value, isNotNull);
        return result!.value!;
      }

      final first = await run();
      expect(first['reused'], false);
      expect(first['batchId'], 'test-batch');
      expect(first['index'], 0);
      for (final key in ['sourcePath', 'previewPath', 'thumbnailPath']) {
        final bytes = await File(first[key]! as String).readAsBytes();
        final decoded = img.decodeJpg(bytes)!;
        expect(decoded.width, 96);
        expect(decoded.height, 64);
        if (key == 'previewPath') {
          expect(first['sha256'], sha256.convert(bytes).toString());
        }
      }
      final second = await run();
      expect(second, {...first, 'reused': true});
    },
  );

  test('recovers corrupt/missing artifacts and malformed manifest', () async {
    final first = await processPhoto(args());
    final manifest = File('${directory.path}/test-batch/photo-0/manifest.json');
    await File(first['previewPath']! as String).writeAsString('incomplete');
    final repaired = await processPhoto(args());
    expect(repaired['reused'], false);
    expect(repaired['sha256'], first['sha256']);
    await File(first['thumbnailPath']! as String).delete();
    expect((await processPhoto(args()))['reused'], false);
    await manifest.writeAsString('{broken');
    expect((await processPhoto(args()))['reused'], false);
    final stored = jsonDecode(await manifest.readAsString()) as Map;
    expect(stored['sha256'], first['sha256']);
    await manifest.delete();
    expect((await processPhoto(args()))['reused'], false);
  });

  test(
    'changed config rebuilds; photo indices produce distinct images',
    () async {
      final first = await processPhoto(args());
      final other = await processPhoto(args(index: 1));
      expect(other['sha256'], isNot(first['sha256']));
      final resized = await processPhoto(args(width: 384, height: 256));
      expect(resized['reused'], false);
      expect(resized['width'], 384);
      final thumb = img.decodeJpg(
        await File(resized['thumbnailPath']! as String).readAsBytes(),
      )!;
      expect(thumb.width, 256);
      expect(thumb.height, 171);
      expect(
        (await processPhoto(args(width: 384, height: 256)))['reused'],
        true,
      );
    },
  );

  test(
    'validates payload before enqueue and again inside processing',
    () async {
      for (final invalid in [
        args(batchId: '../outside'),
        args(batchId: ''),
        args(batchId: 'a/b'),
        args(batchId: r'a\b'),
        args(index: -1),
        args(index: 12),
        args(width: 63),
        args(height: 2049),
      ]) {
        expect(() => preparePhoto.encodeArgs(invalid), throwsArgumentError);
        await expectLater(processPhoto(invalid), throwsArgumentError);
      }
      expect(await directory.list().toList(), isEmpty);
      expect(PhotoTaskArgs.fromJson(args().toJson()).toJson(), args().toJson());
    },
  );

  test('reports coarse real processing phases', () async {
    final phases = <double>[];
    await processPhoto(
      args(),
      onProgress: (percent, phase) async {
        phases.add(percent);
        expect(phase, isNotEmpty);
      },
    );
    expect(phases, [0, 10, 35, 60, 85, 100]);
  });
}
