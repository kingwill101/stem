# stem_cli

[![pub package](https://img.shields.io/pub/v/stem_cli.svg)](https://pub.dev/packages/stem_cli)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.0-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

Command-line tooling for the Stem runtime. The CLI depends on the core package
plus adapter plug-ins (`stem_redis`, `stem_postgres`).

## Install

```bash
dart pub global activate stem_cli
```

Ensure the activation directory is on your `PATH`:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
stem --help
```

## Adapter Support

Out of the box the CLI knows how to talk to the Redis and Postgres adapters
provided by `stem_redis` and `stem_postgres`. Custom adapters can be supported by
wrapping the CLI context builders (see `src/cli/utilities.dart`).

## Local Integration Stack

The package includes the docker compose stack used by integration suites. Start
Redis/Postgres plus TTL CA certificates with:

```bash
docker compose -f docker/testing/docker-compose.yml up -d postgres redis
```

or source the helper script to export integration environment variables:

```bash
source ./_init_test_env
```

## Tests

Run the CLI unit tests with:

```bash
dart test
```

Integration suites auto-skip when the docker services are unavailable. Set
`STEM_CLI_RUN_MULTI=true` to enable the worker multi command smoke test.
