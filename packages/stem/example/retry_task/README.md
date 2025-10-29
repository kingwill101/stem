## Stem Retry Task Demo

This example runs a single Stem worker that executes one task which always
fails. The task is configured with `maxRetries = 3`, so it will be attempted
four times in total (initial attempt + three retries). Every lifecycle event is
logged via `StemSignals` so you can observe the retry cadence.

### Requirements

- Docker and Docker Compose v2

### Usage

```bash
docker compose up --build
```

You should see output similar to:

```
retry-producer-1  | [retry][producer][before_task_publish] {"task":"tasks.always_fail","id":"...","attempt":0,"sender":"stem"}
retry-worker-1    | [retry][worker][task_prerun] {"task":"tasks.always_fail","id":"...","attempt":0,"worker":"retry-demo-worker"}
retry-worker-1    | [retry][task][attempt] {"attempt":0,"max":3}
retry-worker-1    | [retry][worker][task_retry] {"task":"tasks.always_fail","attempt":0,"reason":"StateError: Simulated failure on attempt 0", ...}
...
retry-worker-1    | [retry][worker][task_failed] {"task":"tasks.always_fail","attempt":3,"worker":"retry-demo-worker","error":"StateError: Simulated failure on attempt 3"}
retry-worker-1    | [retry][worker][task_postrun] {"task":"tasks.always_fail","state":"failed", ...}
```

Once the final failure occurs the worker shuts itself down and the compose
stack exits. To run again, clear the previous containers with:

```bash
docker compose down
```

### Tuning retry cadence

Stem calculates retry delays with the worker's `retryStrategy`. This demo sets
`ExponentialJitterRetryStrategy(base: Duration(milliseconds: 200), max: Duration(seconds: 1))`
and connects to Redis with `blockTime=100ms` and `claimInterval=200ms`, so each
retry fires within roughly a second. Increase or decrease the `base` duration or
redis timing parameters in `bin/worker.dart` to change cadence (each retry
doubles the wait up to `max`).

You can also override retries per task via `TaskOptions(maxRetries: N)` in
`bin/producer.dart`. Lower values result in fewer attempts. When you need a
fixed delay instead of exponential backoff, implement a custom
`RetryStrategy` or set `TaskOptions.notBefore` inside your own retry logic.
