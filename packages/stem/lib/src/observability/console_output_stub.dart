// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

/// Writes a console line on runtimes without `dart:io`.
void stemConsoleWriteln(String value) {
  // Console output is the intended fallback when dart:io is unavailable.
  // ignore: avoid_print
  print(value);
}
