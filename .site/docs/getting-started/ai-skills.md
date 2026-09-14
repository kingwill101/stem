---
title: AI-assisted authoring
sidebar_label: AI skills
sidebar_position: 5
slug: /getting-started/ai-skills
---

Package skills give your coding assistant instructions tied to the Stem packages
you use: real API names, lifecycle rules, examples, and mistakes to avoid.
They complement the documentation; they do not configure a worker or database.

## Choose the skills you need

| Dependency | Skill | Use it for |
| --- | --- | --- |
| `stem` | `stem-tasks` | Typed task definitions, workers, results, and shutdown |
| `stem` | `stem-hosted-workflows` | Checkpoints, waits, recovery, retries, and compensation |
| `stem_builder` | `stem_builder-codegen` | Annotation setup, generated definitions, and custom codecs |
| `stem_flutter` | `stem_flutter-lifecycle` | App/host ownership, foreground recovery, and UI observation |
| `stem_sqlite` | `stem_sqlite-persistence` | SQLite storage setup and restart boundaries |

These skills are included in the current source tree. **Older published
versions do not include them.** Check the release notes for the package version
you installed rather than assuming that the latest source is already on pub.dev.

## Install into your application

After adding the dependency and resolving packages, run this in your
application directory:

```bash
dart run skills@ get -p stem
```

Select the task and/or workflow skills from the prompt. Repeat with
`-p stem_builder`, `-p stem_flutter`, or `-p stem_sqlite` for dependencies your
application uses.

To install both core skills for a known agent without a selection prompt:

```bash
dart run skills@ get -p stem --all --agent codex
```

Choose the agent supported by your editor; use `dart run skills@ get --help`
for the current choices. The Codex target uses `.agents/skills/`. Other agents
may use different locations. Inspect the installed instructions before letting
an agent act on them.

Specifying `-p` also avoids the CLI's separate first-run suggestion to install
official Dart/Flutter skill repositories. An unfiltered `get --all` can still
show that suggestion in the current CLI.

## Verify local skills before a release

Use a disposable consumer project with a path dependency on the local package:

```yaml
dependencies:
  stem:
    path: /absolute/path/to/stem/packages/stem
```

Resolve it, then run the same `skills@ get -p stem` command. For Flutter
dependencies, create a Flutter consumer and use `flutter pub get`. If you are
testing several unreleased packages, point their dependencies at the matching
local package versions too; do not silently combine incompatible pub releases
and workspace sources.

Confirm that the expected `SKILL.md` files appear in the consumer's agent
directory. Test there rather than overwriting your real application's
instructions while authoring a skill.

## Keep instructions current

After upgrading dependencies, run `dart run skills@ get -p stem` again to update
the core skills. Use `dart run skills@ list` to inspect installed managed skills.
Review local instruction changes before replacing them.

Package authors maintain consumer skills under each package's `skills/`
directory. `.agents/skills/` is the installation location, not the source to
publish. Repository contribution rules remain in `CONTRIBUTING.md`; they are
not copied into downstream applications.

See Dart's [package skills guide](https://dart.dev/ai/package-skills) for
installation and management, and
[Ship skills with packages](https://dart.dev/tools/pub/package-skills) for
authoring conventions.
