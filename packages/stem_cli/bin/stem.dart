import 'dart:io';

import 'package:stem_cli/stem_cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await runStemCli(arguments);
  if (code != 0) {
    exit(code);
  }
}
