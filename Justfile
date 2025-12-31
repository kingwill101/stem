set shell := ["bash", "-cu"]

ROOT := justfile_directory()
INIT_ENV := ROOT + "/packages/stem_cli/_init_test_env"

test:
    @set -uo pipefail; \
      if ! source "{{INIT_ENV}}"; then exit 1; fi; \
      failures=""; \
      for dir in "{{ROOT}}"/packages/*; do \
        if [ -f "$dir/pubspec.yaml" ]; then \
          pkg="$(basename "$dir")"; \
          echo "==> $pkg"; \
          if [ "$pkg" = "stem_cli" ]; then \
            if ! (cd "$dir" && STEM_CLI_RUN_MULTI=true dart test --fail-fast); then \
              failures="$failures $pkg"; \
            fi; \
          else \
            if ! (cd "$dir" && dart test --fail-fast); then \
              failures="$failures $pkg"; \
            fi; \
          fi; \
        fi; \
      done; \
      if [ -n "$failures" ]; then \
        echo "Failed packages:$failures"; \
        exit 1; \
      fi
