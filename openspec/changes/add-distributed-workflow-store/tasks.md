## 1. Implementation
- [ ] 1.1 Define distributed workflow store contract (claim/lease/renew/release/list runnable)
- [ ] 1.2 Update in-memory workflow store to implement lease semantics
- [ ] 1.3 Add Postgres workflow store lease fields + migrations
- [ ] 1.4 Add Redis workflow store lease handling
- [ ] 1.5 Update workflow runtime to claim/renew/release runs via the store
- [x] 1.6 Add API gateway workflow store endpoints (list/claim/renew/release)
- [x] 1.7 Wire gateway provider + worker client to use workflow store over HTTP
- [x] 1.8 Add multi-worker distribution tests (claim exclusivity, lease expiry recovery)
- [ ] 1.9 Document configuration and operational guidance
