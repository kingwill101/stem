const _tag = r'$stem.hosted-result';
const _version = 1;

/// Internal hosted-result wire encoding, always non-null even for encoded null.
Map<String, Object?> encodeHostedResult(Object? payload) => {
  _tag: _version,
  'value': payload,
};

/// Validates the hosted format before exposing its payload to a user codec.
///
/// No legacy-map guessing: hosted runs have no released unwrapped format.
Object? decodeHostedResult(Object? value, String runId) {
  if (value is! Map ||
      value.length != 2 ||
      value[_tag] != _version ||
      !value.containsKey('value')) {
    throw StateError(
      'Hosted workflow $runId returned an invalid final-result envelope.',
    );
  }
  return value['value'];
}
