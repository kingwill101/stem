## ADDED Requirements

### Requirement: Publish automation script
The system SHALL provide a release automation script that publishes Stem packages in dependency order with dry-run as the default mode.

#### Scenario: Dry-run without force
- **WHEN** the script is run without `--force`
- **THEN** it SHALL run `dart pub publish --dry-run` for each selected package
- **AND** it SHALL not perform an actual publish

### Requirement: Change-based filtering
The system SHALL detect a baseline Git tag and skip unchanged packages unless explicitly included.

#### Scenario: Skip unchanged packages
- **WHEN** a baseline tag exists and a package has no changes since that tag
- **THEN** the script SHALL skip publishing that package
- **AND** it SHALL log the skip reason

### Requirement: Published version guard
The system SHALL optionally skip packages that are already published on pub.dev when `--skip-published` is provided.

#### Scenario: Skip already published versions
- **WHEN** `--skip-published` is set and the package version exists on pub.dev
- **THEN** the script SHALL skip publishing that package
- **AND** it SHALL log the skip reason

### Requirement: Fail fast on validation errors
The system SHALL stop the release process when a dry-run or publish step fails.

#### Scenario: Dry-run failure
- **WHEN** a package `dart pub publish --dry-run` fails
- **THEN** the script SHALL stop processing further packages
- **AND** it SHALL exit with a non-zero status
