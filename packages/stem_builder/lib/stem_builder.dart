import 'package:build/build.dart';

import 'package:stem_builder/src/stem_registry_builder.dart';

/// Creates the builder that generates per-library `*.stem.g.dart` part files.
Builder stemRegistryBuilder(BuilderOptions options) => StemRegistryBuilder();
