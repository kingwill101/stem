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

1. Ensure relevant OpenSpec changes are merged (`openspec validate --strict`).
2. Run CI locally:
   ```bash
   dart format --output=show
   dart analyze
   dart test
   ```
3. Update `.site/docs/` content and cross-links if user-facing changes occurred.
4. Confirm Docker examples (`examples/microservice`, `examples/otel_metrics`) run via `docker compose up`.
5. Draft release notes summarising feature, fixes, migration steps.

## Tagging & Publishing

1. Create a release branch: `git checkout -b release/vX.Y.Z`.
2. Update `CHANGELOG.md` (add the new version section).
3. Commit with message `Release vX.Y.Z`.
4. Tag: `git tag vX.Y.Z` and push: `git push origin vX.Y.Z`.
5. Publish the package(s) via your internal registry or pub.dev if applicable.

## Migration Notes

- Document breaking changes in the release notes and the [Developer Environment](../getting-started/developer-environment.md) guide.
- Provide upgrade snippets (`before`/`after`) for significant API shifts.
- Schedule a docs update walkthrough with maintainers for major releases.

## Post-Release

- Monitor metrics dashboards and error reports for 24 hours after release.
- Open follow-up tasks in OpenSpec for any deferred cleanup.
- Share the release summary on the team channel.
