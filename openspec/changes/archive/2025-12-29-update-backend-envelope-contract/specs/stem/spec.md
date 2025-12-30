## MODIFIED Requirements

### Requirement: Result Backend Semantics
Result backends MUST persist canonical task records including payload, error metadata, and **all** headers/meta supplied on the envelope; they MUST treat signatures (e.g., `stem-signature` and `stem-signature-key`) as opaque values and return them unchanged when tasks are retrieved.

#### Scenario: Signed envelope round-trips unchanged
- **GIVEN** a task is enqueued with signature headers already applied
- **WHEN** the worker records or fetches the task through any result backend
- **THEN** the backend MUST persist and return the exact signature headers without modification so verification succeeds downstream
