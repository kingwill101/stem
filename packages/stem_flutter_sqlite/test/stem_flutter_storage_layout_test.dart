import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

void main() {
  test(
    'forRoot creates the directory and resolves broker/backend paths',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'stem_flutter_storage_layout_test_',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final root = Directory('${sandbox.path}${Platform.pathSeparator}runtime');
      final layout = await StemFlutterStorageLayout.forRoot(
        root,
        brokerFileName: 'jobs.db',
        backendFileName: 'results.db',
      );

      expect(layout.root.path, root.path);
      expect(layout.root.existsSync(), isTrue);
      expect(
        layout.brokerFile.path,
        '${root.path}${Platform.pathSeparator}jobs.db',
      );
      expect(
        layout.backendFile.path,
        '${root.path}${Platform.pathSeparator}results.db',
      );
    },
  );

  test('forRoot rejects broker and backend path collisions', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'stem_flutter_storage_layout_test_',
    );
    addTearDown(() => sandbox.delete(recursive: true));

    await expectLater(
      StemFlutterStorageLayout.forRoot(
        sandbox,
        brokerFileName: 'runtime.sqlite',
        backendFileName: 'runtime.sqlite',
      ),
      throwsArgumentError,
    );
  });

  test('file names cannot escape the application directory', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'stem_flutter_storage_layout_test_',
    );
    addTearDown(() => sandbox.delete(recursive: true));

    for (final name in [
      '',
      '.',
      '..',
      '../outside.db',
      r'..\outside.db',
      '/outside.db',
      r'C:\outside.db',
      'nested/file.db',
    ]) {
      await expectLater(
        StemFlutterStorageLayout.forRoot(sandbox, brokerFileName: name),
        throwsArgumentError,
      );
      await expectLater(
        StemFlutterStorageLayout.forRoot(sandbox, backendFileName: name),
        throwsArgumentError,
      );
    }
    expect(sandbox.listSync(), isEmpty);
  });

  test(
    'application directory name is validated before calling plugins',
    () async {
      await expectLater(
        StemFlutterStorageLayout.applicationSupport(
          directoryName: '../outside',
        ),
        throwsArgumentError,
      );
    },
  );
}
