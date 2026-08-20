/// Optional in-memory adapters for local development and tests.
///
/// Production applications should import a concrete adapter package instead.
/// This library is intentionally separate from the primary `stem.dart` API so
/// adapter usage is explicit in new code.
library;

export 'src/memory.dart';
