---
title: Release Process
sidebar_label: Releases
sidebar_position: 3
slug: /deployment/releases
---

This guide covers preparation, versioning, and post-release steps for Stem.

## Versioning

- Follow **semantic versioning** (`MAJOR.MINOR.PATCH`).
- Bump **MAJOR** when breaking public APIs or task behaviour.
- Bump **MINOR** for new backwards-compatible features.
- Bump **PATCH** for bug fixes and doc-only updates.

## Pre-Release Checklist

1. Run the release planner from the repository root:
   ```bash
   dart run tool/publish.dart --allow-dirty --include-unchanged --plan
   ```
   This derives the publishable package graph from the workspace manifests.
   `--allow-dirty` is valid for planning only; the full release gate requires
   the exact release commit to be clean.
2. Run CI locally:
   ```bash
   dart format lib test --set-exit-if-changed
   dart analyze --fatal-infos
   dart test --exclude-tags soak
   ```
3. Run the aggregate workflow checks for every publishable package, including
   standalone resolution outside workspace overrides.
4. Update `.site/docs/` content and cross-links if user-facing changes occurred.
5. Confirm Docker examples (`examples/microservice`, `examples/otel_metrics`) run via `docker compose up`.
6. Draft release notes summarising feature, fixes, migration steps.

## Tagging & Publishing

1. Update each changed package's `CHANGELOG.md` and version.
2. Run `dart run tool/publish.dart` from a clean tree. The tool validates
   formatting, analysis, tests, generated output, changelogs and pub.dev dry
   runs in dependency order.
3. Commit exactly the metadata used for the release.
4. Tag each package independently using `<package>-v<version>`, for example
   `stem-v0.4.0` or `stem_flutter-v0.3.0`, then push the tags. The trusted
   publishing workflow consumes these tags and publishes the matching package.
5. Verify the package pages and dependency resolution after publication.

## Migration Notes

- Document breaking changes in the release notes and the [Developer Environment](../getting-started/developer-environment.md) guide.
- Provide upgrade snippets (`before`/`after`) for significant API shifts.
- Treat database migrations as rolling-deployment boundaries: add nullable or
  defaulted columns first, keep old workers able to write during the rollout,
  then remove obsolete fields only in a later release. Run the historical
  upgrade and legacy-shaped-write compatibility tests before publishing.
- Schedule a docs update walkthrough with maintainers for major releases.

## Post-Release

- Monitor metrics dashboards and error reports for 24 hours after release.
- Open follow-up tasks in OpenSpec for any deferred cleanup.
- Share the release summary on the team channel.
