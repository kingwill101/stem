## Why
Workflow detail views need canonical metadata about workflow definitions and step execution history. Today this information is only available in-process and not persisted or surfaced in a structured way.

## What Changes
- Add workflow definition metadata models (workflow, step, edges, versioning).
- Add workflow registry interface and default in-memory implementation.
- Add workflow introspection sink interface for step-level execution events with a default no-op implementation.
- Emit registry entries on `StemWorkflowApp` boot and step events during workflow runtime execution.

## Impact
- Affected specs: workflow-introspection
- Affected code: stem workflow runtime, StemWorkflowApp bootstrap
