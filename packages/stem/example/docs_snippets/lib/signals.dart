// Signal configuration example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';

// #region signals-configure
void configureSignals() {
  StemSignals.configure(
    configuration: const StemSignalConfiguration(
      enabled: true,
      enabledSignals: {'worker-heartbeat': false},
    ),
  );
}
// #endregion signals-configure

void main() {
  configureSignals();
  print('Signals configured.');
}
