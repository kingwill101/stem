## Why
We want stronger guarantees for Stem core and the cloud gateway by adding property-based and chaos testing within the test suites, exercising invariants and failure conditions at scale.

## What Changes
- Add property-based + chaos testing support (via `property_testing`) to `stem` and `stem_cloud_gateway` tests.
- Introduce per-package test helpers/config to generate data and run chaos scenarios inside tests.
- Add representative property tests covering core invariants and gateway API robustness.

## Impact
- Affected specs: testing
- Affected code: stem tests, stem_cloud_gateway tests
