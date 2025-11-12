## Verification Tasks
- [x] Audit existing Canvas/worker and backend implementations to confirm chord metadata persists and workers dispatch callbacks atomically via `claimChord`.
- [x] Ensure group metadata stores the serialized callback envelope so callbacks can run after producer termination.
- [x] Validate worker unit tests cover chord completion (body success enqueues callback) and backend contract tests assert single claimant semantics.
- [x] Update workflow specification/README to document the durable chord guarantee.
- [x] Run `dart analyze`, targeted unit tests (`worker_test.dart`), and `openspec validate add-chord-callback-reliability --strict`.
