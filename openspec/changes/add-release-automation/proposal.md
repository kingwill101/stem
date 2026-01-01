## Why
We need a repeatable, low-risk way to publish Stem packages, aligned with the ORMed release flow, to reduce manual steps and missed packages.

## What Changes
- Add a release automation script for Stem packages modeled after ormed/tool/publish.dart.
- Publish packages in dependency order with dry-run as the default.
- Support skipping unchanged or already-published versions via flags.

## Impact
- Affected specs: release-automation (new)
- Affected code: new tool script under repo root (tool/publish.dart), release workflow documentation if needed.
