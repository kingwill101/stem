/// Marks a top-level codec for use by generated task and workflow bindings.
///
/// The codec's type argument is inferred from its declared `Codec<T, Object?>`
/// type. The annotation is intentionally marker-only: codec values remain
/// ordinary Dart values/getters and are referenced directly by generated
/// code.
class PayloadCodecDefn {
  /// Creates a payload codec binding annotation.
  const PayloadCodecDefn();
}
