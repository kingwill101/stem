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
