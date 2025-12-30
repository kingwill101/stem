## ADDED Requirements

### Requirement: Secure Heartbeat Transport
Worker heartbeat transports MUST reuse the shared TLS configuration contract so secure Redis deployments can publish worker state without code changes.

#### Scenario: TLS handshake succeeds
- **GIVEN** `STEM_TLS_CA_CERT` and optional client credentials are configured and the namespace uses `rediss://`
- **WHEN** the worker initialises the Redis heartbeat transport
- **THEN** it MUST establish a TLS-secured connection honouring the allow-insecure flag semantics used elsewhere in Stem

#### Scenario: TLS handshake failure reports context
- **GIVEN** the TLS handshake fails
- **WHEN** the transport attempts to connect
- **THEN** it MUST log the same structured diagnostics (`component`, certificate paths, `allowInsecure`) provided by other Redis connectors so operators can triage the issue
