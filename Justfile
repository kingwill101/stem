set shell := ["bash", "-cu"]

ROOT := justfile_directory()
INIT_ENV := ROOT + "/packages/stem_cli/_init_test_env"

test:
    @set -euo pipefail; \
      source "{{INIT_ENV}}"; \
      for dir in "{{ROOT}}"/packages/*; do \
        if [ -f "$$dir/pubspec.yaml" ]; then \
          (cd "$$dir" && dart test --fail-fast); \
        fi; \
      done
