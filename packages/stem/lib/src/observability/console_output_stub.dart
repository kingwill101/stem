/// Writes a console line on runtimes without `dart:io`.
void stemConsoleWriteln(String value) {
  // ignore: avoid_print
  print(value);
}
