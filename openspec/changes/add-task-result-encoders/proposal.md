# Proposal: Configurable task result encoding

## Problem
Result backends persist task payloads as JSON-friendly blobs captured directly
from handler return values. This works for primitive/Map payloads but breaks
when handlers need to emit binary blobs, protobufs, or redacted values that
should not live in clear text. Today every backend assumes it owns the
serialization format (e.g., `jsonb` columns, Redis hashes), so teams duplicate
encoding logic per backend and cannot plug in custom codecs or encryption
layers consistently. We need a first-class abstraction so result encoding is
configurable, testable, and portable across Redis/Postgres/SQLite backends.

## Goals
- Introduce a pluggable encoder interface that transforms typed task results to
  backend-friendly bytes/JSON plus the inverse decoder when reading statuses.
- Allow encoders to be configured globally (per `StemApp`, `Canvas`, workers)
  so all backends share the same serialization policy without ad-hoc hooks.
- Ensure existing users keep the current JSON semantics as the default encoder
  to avoid breaking compatibility.
- Provide guidance for common scenarios (encryption, compression, protobuf,
  large binary blobs) so adapters expose necessary storage primitives.

## Non-Goals
- Changing the physical schemas of result backends beyond what is required to
  store encoded bytes/blobs alongside metadata.
- Providing built-in encryption libraries; we only surface hooks for teams to
  wire their own codecs.
- Supporting per-task encoders in the first iteration (global encoder is
  sufficient, extensions can add per-definition overrides later).

## Measuring Success
- Backends accept a `TaskResultEncoder` (or similar) that is invoked on every
  `set`/`get`/`watch`, and falling back to JSON when none is supplied.
- Tests demonstrate storing/reading non-JSON payloads (e.g., binary buffers) via
  a custom encoder over in-memory, Redis, and Postgres backends without code
  changes outside encoder registration.
- Documentation walks through configuring encoders plus migration guidance for
  existing deployments.
