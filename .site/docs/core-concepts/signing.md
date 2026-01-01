---
title: Payload Signing
sidebar_label: Payload Signing
sidebar_position: 3
slug: /core-concepts/signing
---

Stem can sign every task envelope so workers can detect tampering or untrusted
publishers. This guide covers the mental model, a quick start, and a full
reference for signing configuration.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Why sign envelopes?

Signing lets workers verify that the envelope payload (args, headers, metadata,
and timing fields) is unchanged between the producer and the broker. When
signing is enabled on workers, any envelope missing a signature or carrying an
invalid signature is rejected and moved to the DLQ with a `signature-invalid`
reason.

## How signing works in Stem

- Producers create a `PayloadSigner` from environment-derived config and pass it
  into `Stem` to sign new envelopes.
- Workers create the same signer (or verification-only config) and pass it into
  `Worker` to verify each delivery.
- Signatures are stored in envelope headers: `stem-signature` and
  `stem-signature-key`.

Signing is opt-in: if no signing keys are configured, envelopes are sent and
accepted unsigned.

## Quick start (HMAC)

1) Generate a shared secret and export signing variables on **every** producer
   and worker (and any scheduler that enqueues tasks):

```bash
export STEM_SIGNING_ALGORITHM=hmac-sha256
export STEM_SIGNING_KEYS="v1:$(openssl rand -base64 32)"
export STEM_SIGNING_ACTIVE_KEY=v1
```

2) Wire the signer into producers, workers, and schedulers:

<Tabs>
<TabItem value="producer" label="Producer: sign envelopes">

Create a signer from your environment-driven config:

```dart title="enqueuer/bin/main.dart" file=<rootDir>/../packages/stem/example/microservice/enqueuer/bin/main.dart#signing-producer-signer

```

Attach the signer to the producer so envelopes are signed:

```dart title="enqueuer/bin/main.dart" file=<rootDir>/../packages/stem/example/microservice/enqueuer/bin/main.dart#signing-producer-stem

```

</TabItem>
<TabItem value="worker" label="Worker: verify signatures">

If your worker only needs to verify, the signer can be created from public keys:

```dart title="worker/bin/worker.dart" file=<rootDir>/../packages/stem/example/microservice/worker/bin/worker.dart#signing-worker-signer

```

Attach the signer to the worker so signatures are verified:

```dart title="worker/bin/worker.dart" file=<rootDir>/../packages/stem/example/microservice/worker/bin/worker.dart#signing-worker-wire

```

</TabItem>
<TabItem value="scheduler" label="Scheduler: sign scheduled tasks">

Schedulers that enqueue tasks should also sign:

```dart title="beat/bin/beat.dart" file=<rootDir>/../packages/stem/example/microservice/beat/bin/beat.dart#signing-beat-signer

```

```dart title="beat/bin/beat.dart" file=<rootDir>/../packages/stem/example/microservice/beat/bin/beat.dart#signing-beat-wire

```

</TabItem>
</Tabs>

## Ed25519 (asymmetric signing)

Ed25519 keeps private keys only on producers while workers verify with public
keys.

1) Generate keys and export the values:

```bash
dart run scripts/security/generate_ed25519_keys.dart
```

2) Set variables on producers, workers, and schedulers:

```bash
export STEM_SIGNING_ALGORITHM=ed25519
export STEM_SIGNING_PUBLIC_KEYS=primary:<base64-public>
export STEM_SIGNING_PRIVATE_KEYS=primary:<base64-private>
export STEM_SIGNING_ACTIVE_KEY=primary
```

3) For workers, you may omit `STEM_SIGNING_PRIVATE_KEYS` if you only want to
   verify signatures.

## Key rotation (safe overlap)

1) Add the new key alongside the old one in your key list.
2) Update `STEM_SIGNING_ACTIVE_KEY` on producers first.
3) Roll workers (they accept all configured keys).
4) Remove the old key after the backlog drains.

Example: producer logging the active key and enqueuing during rotation:

<Tabs>
<TabItem value="active-key" label="Rotation: log active key">

```dart title="signing_key_rotation/bin/producer.dart" file=<rootDir>/../packages/stem/example/signing_key_rotation/bin/producer.dart#signing-rotation-producer-active-key

```

</TabItem>
<TabItem value="enqueue" label="Rotation: enqueue tasks">

```dart title="signing_key_rotation/bin/producer.dart" file=<rootDir>/../packages/stem/example/signing_key_rotation/bin/producer.dart#signing-rotation-producer-enqueue

```

</TabItem>
</Tabs>

## Reference: signing environment variables

| Variable | Purpose | Notes |
| --- | --- | --- |
| `STEM_SIGNING_ALGORITHM` | `hmac-sha256` (default) or `ed25519` | Defaults to HMAC. |
| `STEM_SIGNING_KEYS` | HMAC secrets (`keyId:base64`) | Comma-separated list. Required for HMAC. |
| `STEM_SIGNING_ACTIVE_KEY` | Key id used for new signatures | Required when signing. |
| `STEM_SIGNING_PUBLIC_KEYS` | Ed25519 public keys (`keyId:base64`) | Comma-separated list. Required for Ed25519. |
| `STEM_SIGNING_PRIVATE_KEYS` | Ed25519 private keys (`keyId:base64`) | Only needed by signers. |

## Failure behavior & troubleshooting

- Missing or invalid signatures are dead-lettered with reason
  `signature-invalid` and increment the `stem.tasks.signature_invalid` metric.
- If you see `signature-invalid` in the DLQ, confirm all producers are signing
  and that workers have the same key set.
- If the active key id is not present in the key list, producers will fail fast
  when trying to sign.

## Next steps

- Review [Prepare for Production](../getting-started/production-checklist.md)
  for TLS guidance and deployment hardening.
- Use the [Producer API](./producer.md) guide for advanced enqueue patterns.
