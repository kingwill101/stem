import 'dart:io';

import 'package:repodoc/repodoc.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runRepodoc(arguments);
}
