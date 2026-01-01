## MODIFIED Requirements

### Requirement: Priority-Aware Delivery
Stem MUST clamp and honour queue-defined priority ranges before enqueue and during delivery ordering.

#### Scenario: Priority override clamps to queue range
- **GIVEN** a routing config where queue `critical` declares `priority_range: [2, 5]`
- **AND** a route publishes two envelopes targeting `critical` with priorities `9` and `1`
- **WHEN** the broker stores the envelopes
- **THEN** the persisted priorities MUST be clamped to `5` and `2` respectively
- **AND** a worker consuming `critical` MUST receive the clamped `5` priority envelope before the `2` priority envelope.

### Requirement: Broadcast Channels
Stem MUST provide broadcast routing so a single enqueue reaches all subscribed workers exactly once per acknowledgement window.

#### Scenario: Broadcast fan-out tracks per-worker acknowledgements
- **GIVEN** two workers subscribed to broadcast channel `maintenance`
- **WHEN** a task is enqueued with target `broadcast://maintenance`
- **THEN** each worker MUST receive the envelope once with `route.isBroadcast == true`
- **AND** acknowledging the delivery MUST remove it from the worker's pending set so it is not replayed on reconnect without a new broadcast.
