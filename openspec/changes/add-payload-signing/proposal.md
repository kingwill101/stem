## Why
- Phase 7 (Security hardening) requires task payload integrity so workers can detect tampering and replay attacks.
- Today redis streams can be modified between enqueue and execution; there is no signing or verification path.

## What Changes
- Introduce a payload signing helper (client + worker verification) with key rotation support and clear failure semantics.
- Provide configuration/docs for TLS automation and recurring vulnerability scans once signing is in place.

## Impact
- New cryptographic dependency (HMAC/signature libs) and secrets management requirements.
- Workers must fail fast on signature mismatch; enqueue clients must handle signing errors.
- Documentation and examples need updates to cover secure deployment patterns.
