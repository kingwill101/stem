/// Writes a console line on runtimes without `dart:io`.
void stemConsoleWriteln(String value) {
  // Console output is the intended fallback when dart:io is unavailable.
  // ignore: avoid_print
  print(value);
}
