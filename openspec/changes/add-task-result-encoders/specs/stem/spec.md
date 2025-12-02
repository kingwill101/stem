## ADDED Requirements

### Requirement: Configurable task result encoders
Result backends MUST accept a configurable `TaskPayloadEncoder` pair that transforms
handler return values into the storage format used for `payload` fields. When
no encoder is provided, the existing JSON behavior MUST remain unchanged so
current deployments do not break. Encoders MUST run exactly once per persistence
operation (store on success/failure, read via `get`/`watch`/group aggregation)
and MUST include enough metadata (content-type, version, etc.) so consumers can
reconstruct originals without guessing.

#### Scenario: Custom encoder stores binary payloads
- **GIVEN** an operator configures a `TaskPayloadEncoder` that base64-encodes
  binary blobs
- **WHEN** a handler returns a `Uint8List`
- **THEN** the backend MUST invoke the encoder, persist the encoded bytes plus
  encoder metadata, and report `TaskState.succeeded` with no JSON coercion

#### Scenario: Decoder runs once when reading results
- **GIVEN** the same encoder is registered
- **AND** a client calls `Stem.waitForTask<MyType>(taskId)`
- **WHEN** the backend retrieves the stored payload
- **THEN** it MUST call the decoder exactly once, return the original
  `Uint8List` (or typed object), and expose the stored metadata untouched

#### Scenario: JSON fallback remains default
- **GIVEN** no encoder is configured
- **WHEN** tasks complete with JSON-friendly objects
- **THEN** the system MUST behave identically to today (payload stored as JSON,
  no metadata changes) so existing users are unaffected

#### Scenario: Task definitions override global encoder
- **GIVEN** a global encoder is configured to encrypt payloads
- **AND** a specific `TaskDefinition` registers a distinct encoder (e.g., to
  emit unencrypted diagnostic results)
- **WHEN** that task completes
- **THEN** the runtime MUST honor the per-task encoder during persistence and
  decoding without affecting other tasks that share the global encoder

#### Scenario: Task argument encoder runs symmetrically
- **GIVEN** a `TaskArgsEncoder` is configured that base64-encodes argument
  payloads
- **WHEN** a producer enqueues `task.encrypt` with rich argument data
- **THEN** the enqueue path MUST encode the arguments exactly once before they
  leave the process, the broker MUST store the encoded representation, and the
  worker MUST decode the payload before invoking the handler so `TaskContext` sees
  the original argument structure
