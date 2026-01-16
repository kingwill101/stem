import 'package:build/build.dart';

import 'package:stem_builder/src/stem_registry_builder.dart';

/// Creates the builder that generates `stem_registry.g.dart`.
Builder stemRegistryBuilder(BuilderOptions options) => StemRegistryBuilder();
