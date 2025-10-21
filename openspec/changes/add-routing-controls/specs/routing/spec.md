## ADDED Requirements
### Requirement: Default Queue Aliasing
Stem MUST allow operators to rename the default queue without modifying every task definition.

#### Scenario: Config renames default queue
- **GIVEN** a routing config that sets `default_queue: critical`
- **WHEN** a task without an explicit queue is enqueued
- **THEN** the broker MUST publish it to the `critical` queue
- **AND** existing workers consuming the default queue MUST use the updated name.

### Requirement: Declarative Routing Policies
Stem MUST support declaratively routing tasks based on task name patterns and metadata.

#### Scenario: Task name matches routing rule
- **GIVEN** a routing policy that routes `reports.*` tasks to the `reports` queue
- **WHEN** the coordinator enqueues `reports.generate`
- **THEN** the routing layer MUST publish to the `reports` queue without application code branching.

### Requirement: Priority-Aware Delivery
Brokers MUST honour task priority when queuing and delivering messages.

#### Scenario: Higher priority task is delivered first
- **GIVEN** two tasks enqueued to the same queue with priorities 9 and 1
- **WHEN** a worker fetches the next task
- **THEN** the priority 9 task MUST be delivered before the priority 1 task, assuming equal available retries and schedules.

### Requirement: Broadcast Channels
Stem MUST provide broadcast routing so a single enqueue reaches all subscribed workers.

#### Scenario: Broadcast task reaches all workers
- **GIVEN** three workers subscribing to broadcast channel `maintenance`
- **WHEN** a task is enqueued with target `broadcast://maintenance`
- **THEN** each worker MUST receive the task once
- **AND** the broadcast MUST not be silently dropped if one worker is offline (delivery semantics documented).

### Requirement: Multi-Queue Worker Subscription
Workers MUST be able to consume from multiple queues specified via configuration or CLI flags.

#### Scenario: Worker consumes two queues
- **GIVEN** a worker configured for queues `default` and `reports`
- **WHEN** tasks arrive on both queues
- **THEN** the worker MUST fetch tasks from both without restart or redeploy
- **AND** heartbeats MUST report the queues it currently services.
