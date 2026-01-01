# Quality Gate Runner

This example provides a `just`-based command runner for common quality gates
(formatting, analysis, unit tests, chaos tests, performance tests, and coverage).

## Usage

```bash
cd example/quality_gates
# or from repo root:
# cd packages/stem/example/quality_gates

# Fast checks
just quick

# Full gate set (format + analyze + unit + chaos + perf + coverage)
just quality

# Smoke-build the example binaries (optional)
just examples-smoke
```

Coverage output is written to `packages/stem/coverage/lcov.info`.
