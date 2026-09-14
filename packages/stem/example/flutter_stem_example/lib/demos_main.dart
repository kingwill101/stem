import 'package:flutter/material.dart';

import 'src/demos/landing_page.dart';

/// Demo gallery entrypoint: `flutter run -t lib/demos_main.dart`.
///
/// Opens on a landing page with one button per demo. Each demo owns its
/// workflow host and cleans it up when its route is popped.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: DemosLandingPage()));
}
