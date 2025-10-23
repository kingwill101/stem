## Stem Signals Demo

This example showcases Stem's signal hooks. Running `docker compose up`
starts a Redis broker, a Stem worker, and a producer process. Both processes
subscribe to `StemSignals` and print structured JSON lines describing every
signal dispatch (publish, task lifecycle, worker lifecycle, retries, failures).

### Requirements

- Docker and Docker Compose v2

### Usage

```bash
docker compose up --build
```

Expect console output similar to:

```
signals-worker-1  | [signals][worker][worker_init] {"worker":"signals-demo-worker","queues":["default"]}
signals-producer-1| [signals][producer][before_task_publish] {"task":"tasks.hello","id":"...","attempt":0,"sender":"stem"}
signals-worker-1  | [signals][worker][task_prerun] {"task":"tasks.hello","id":"...","attempt":0,"worker":"signals-demo-worker"}
signals-worker-1  | [signals][worker][task_retry] {"task":"tasks.flaky","id":"...","reason":"StateError: first attempt always fails","nextRunAt":"...","worker":"signals-demo-worker"}
signals-worker-1  | [signals][worker][task_postrun] {"task":"tasks.always_fail","id":"...","state":"failed","worker":"signals-demo-worker"}
```

Stop the demo with `Ctrl+C`. The worker and producer trap TERM signals and
shut down gracefully. To rebuild after editing the example, run
`docker compose build`.
