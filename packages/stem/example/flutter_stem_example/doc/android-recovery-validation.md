# Android recovery validation

## Scope

These are observations from the connected Samsung SM-A075M (Android 16),
using the Workmanager profile entrypoint, concurrency one, one task per isolate,
and newly published Standard photos with three retries. Power saving was off,
the app was battery-unrestricted, and USB charging was connected.

The build was an uncommitted development checkout, not a published release.
Times below are the device's clock. This test is distinct from the earlier
uncontrolled Android low-memory kills and does not establish force-stop behavior.

## Opt-in memory diagnostics

```sh
flutter build apk --profile -t lib/workmanager_main.dart \
  --dart-define=STEM_DEMO_MEMORY_DIAGNOSTICS=true
```

The task prints JSON records named `stem.photo.memory` before cache checking,
before source generation, after encoding/decoding/enhancement, after preview and
thumbnail encoding, and after artifact commit. Records include batch/index,
dimensions, PID, timestamp, `rssBytes`, and `processMaxRssBytes`.

Capture only the demo's PID, not every application's logs:

```sh
adb -s <device> shell pidof com.example.flutter_stem_example
adb -s <device> logcat --pid=<pid> -T 1
```

The flag is disabled by default. Samples are not put in persisted/cached task
results. RSS includes all Flutter engines, isolates, native allocations and
mapped pages in the process. `maxRss` is its lifetime high-water mark; neither
value is a per-photo allocation measurement. Stage sampling can miss transient
peaks. Compare the same build mode, battery settings, device pressure, and UI
visibility; opening the UI during a callback can change the process baseline.

## Controlled process interruption

Test batch: `1789051532061121-0`, six Standard photos (1600 × 1000).

1. Confirmed the previous queue was empty and committed six new tasks.
2. Backgrounded the UI. Photos 0–2 completed at attempt zero.
3. At 09:46:13, after photo 3 reported `source-encoded`, sent SIGKILL to **only**
   the demo's PID using its `run-as` identity. Did not use Android force-stop.
4. Inspected copies of the demo's SQLite files and WALs: photo 3 retained
   `running`, attempt zero, `max_retries=3`, and a lease expiring at 09:46:38.
   Photos 4–5 were still queued; completed results survived.
5. The replacement callback started at 09:46:43. At 09:46:44 it classified
   `TaskInterruptedException` and scheduled attempt one after 1840 ms using
   Stem's existing retry strategy.
6. At 09:47:08 it returned `idle` and native WorkManager `SUCCESS`.

Final durable result:

| Photo index | State | Attempt |
| --- | --- | --- |
| 0, 1, 2, 4, 5 | succeeded | 0 |
| 3 (interrupted) | succeeded | 1 |

No matching broker deliveries remained. All six manifests and 18 artifact
SHA-256 checksums matched. The three pre-kill successful result payloads were
unchanged. There were 24 files: three artifacts plus one manifest per photo.
The interrupted photo had not committed artifacts, so it rebuilt them; this
does not claim that a post-commit/pre-ack kill was exercised.

The UI was reopened during recovery. This establishes recovery at a later
execution opportunity, not guaranteed automatic restart timing or continuation
after user force-stop. A callback startup was already logged before that UI
inspection, but Android remains responsible for execution opportunities.

## Memory observations

These measurements predate the multi-worker default. Two workers can now process
photos concurrently; their aggregate memory use can exceed these observations.

| Process | Sampled RSS range | Lifetime high-water mark |
| --- | --- | --- |
| Original callback process | 187.3–245.7 MiB | 323.2 MiB |
| Replacement callback process | 182.6–343.0 MiB | 349.7 MiB |

In the original process, pre-photo RSS decreased across the first three items
(218.6, 206.3, 190.6 MiB); it did not grow monotonically per completed item.
Decoding added roughly 17–21 MiB in several samples. The replacement process
also showed a much larger jump during one source-encoding interval, overlapping
UI/process activity; these samples cannot attribute the entire jump to the
image encoder. Do not conclude that a leak is absent or that OS kills are fixed.

## Still to verify

- Comparable Quick/Standard/Heavy peak profiles with the UI kept backgrounded.
- A kill after artifact commit but before task/result acknowledgement.
- Repeated native interruptions through retry exhaustion.
- Native cancellation versus process death versus user force-stop.
- Recovery under normal battery optimization and denied notification permission.
- Memory attribution within source generation/JPEG encoding and Flutter-engine
  startup before changing the workload or claiming a hard memory ceiling.

Use a fresh retry-enabled batch for destructive tests. Existing envelopes keep
their original retry budgets; installing new defaults does not rewrite them.
Do not clear application data or republish an interrupted batch just to hide a
failed recovery.
