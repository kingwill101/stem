## MODIFIED Requirements

### Requirement: StemApp exposes full worker configuration
StemApp SHALL accept configuration for all Worker runtime options and forward
those settings when building the managed Worker.

#### Scenario: Configure advanced worker options
- **GIVEN** a developer passes StemWorkerConfig with options such as rate
  limiting, retry strategy, routing subscription, and observability settings
- **WHEN** they create a StemApp via StemApp.create or StemApp.inMemory
- **THEN** the managed worker uses those configuration values

### Requirement: StemApp preserves default worker behavior
StemApp SHALL continue to use the Worker default values for any options not
provided via StemWorkerConfig.

#### Scenario: Omit advanced worker options
- **GIVEN** a developer does not specify advanced options in StemWorkerConfig
- **WHEN** they create a StemApp
- **THEN** the managed worker uses the same defaults as a directly constructed
  Worker

### Requirement: StemApp exposes a Canvas helper
StemApp SHALL provide a Canvas instance that reuses the app broker, backend,
registry, and payload encoder registry.

#### Scenario: Compose tasks with StemApp.canvas
- **GIVEN** a developer creates a StemApp
- **WHEN** they access `app.canvas`
- **THEN** the Canvas instance uses the same broker, backend, registry, and
  encoders as the StemApp
