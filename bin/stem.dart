import 'dart:io';

import 'package:untitled6/src/cli/cli_runner.dart';

Future<void> main(List<String> arguments) async {
  final code = await runStemCli(arguments);
  if (code != 0) {
    exit(code);
  }
}
