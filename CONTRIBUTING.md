# Contributing

Stem changes should improve a documented contract or close a demonstrated
reliability gap. New subsystems need a design note and failure tests before
they become part of the public product story.

Before opening a pull request:

```bash
flutter pub get
dart run tool/check_examples.dart --skip-diff

cd packages/stem
dart format lib test --set-exit-if-changed
dart analyze --fatal-infos
dart test --exclude-tags soak --fail-fast
```

For package-wide release validation, run the release planner from the
repository root:

```bash
dart run tool/publish.dart --plan
```

The release tool derives package membership and dependency order from the Dart
workspace. It requires a clean Git tree for a real release and validates
formatting, analysis, tests, generated sources, changelog headings, and pub
publication archives.

## Documentation and package skills

Write for the person completing a task, not for the order in which features
were implemented:

- Keep the root README a short entry point: what Stem does, a runnable example,
  and links to the next decision.
- Use `.site/docs/getting-started/` for guided onboarding. Keep existing page
  URLs when changing navigation so external links continue to work.
- Keep each package README useful on pub.dev without assuming a repository
  checkout. Link to detailed guides rather than repeating large API examples.
- Keep workflow lifecycle and recovery contracts in
  [`packages/stem/doc/workflow_host.md`](packages/stem/doc/workflow_host.md);
  onboarding pages should explain the essentials and link to that reference.
- Mark partial snippets as partial. A first example must include imports,
  definitions, an entry point, deterministic completion, and resource cleanup.
- Distinguish the checked-out source from released package versions. Do not
  promise that an unpublished API or skill is available through `dart pub add`.
- Say which storage and process-lifecycle assumptions an example relies on.
  Never equate in-memory checkpoints with restart durability or retries with
  exactly-once external effects.

Package skills live in `packages/<package>/skills/<package-prefixed-name>/`.
These are instructions shipped to **consumers' agents**, not a second set of
repository contribution rules. Follow
[Dart's package-skill authoring guide](https://dart.dev/tools/pub/package-skills):
use YAML frontmatter with a matching skill name, a focused description, and
prescriptive instructions verified against the package's public API.

Installation copies a skill into another project. Bundle any required
references inside the skill directory; do not use relative links that reach
back into this monorepo. Never include secrets, generated build artifacts, or
commands that publish packages or modify a consumer's environment without
their consent.

When changing an API, review its examples and affected skills in the same
change. Validate skill metadata and reference portability from the repository root:

```bash
dart run tool/validate_package_skills.dart
```

Also validate the documentation against the local packages:

```bash
# From the repository root:
flutter pub get
cd .site
npm ci
npm run test:docs
npm run build
```

The docs tests execute selected complete README/site/core-skill programs and
verify the code-region importer. Other examples still need the relevant package
analysis, code-generation, Flutter, or integration checks. Metadata validation
alone does not prove that an API example compiles or a recovery claim is true.
