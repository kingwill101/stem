# Security policy

Stem is experimental software. Security reports are welcome, especially
reports involving payload signing, TLS, broker credentials, task isolation,
lease ownership, or data exposure in logs and telemetry.

Please do not publish a suspected vulnerability in a public issue. Contact the
repository owner through the private security-reporting mechanism provided by
GitHub, including the affected package and version, reproduction steps, impact,
and any suggested mitigation.

Disposable certificates and keys used by tests are not production credentials.
They must never be reused in deployments or committed outside explicitly
labelled test fixtures.
