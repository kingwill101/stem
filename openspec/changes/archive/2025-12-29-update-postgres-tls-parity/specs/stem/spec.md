## MODIFIED Requirements

### Requirement: Result Backend Semantics
Result backends MUST persist canonical task records, treat envelope headers/signatures as opaque, and respect Stem's security configuration when establishing connections.

#### Scenario: Postgres backend respects TLS settings
- **GIVEN** `STEM_TLS_*` variables are set with CA/client credentials and a Postgres URL is configured
- **WHEN** Stem connects to the Postgres result backend
- **THEN** it MUST establish a TLS-secured connection honouring `allowInsecure`, surfacing actionable diagnostics on handshake failure
