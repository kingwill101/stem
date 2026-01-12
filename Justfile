set shell := ["bash", "-cu"]

ROOT := justfile_directory()
INIT_ENV := ROOT + "/packages/stem_cli/_init_test_env"
COVERAGE_PACKAGES := "stem stem_cli stem_postgres stem_redis stem_sqlite"

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

coverage:
    @set -uo pipefail; \
      if ! source "{{INIT_ENV}}"; then exit 1; fi; \
      failures=""; \
      for pkg in {{COVERAGE_PACKAGES}}; do \
        dir="{{ROOT}}/packages/$pkg"; \
        echo "==> $pkg (coverage)"; \
        if [ "$pkg" = "stem" ]; then \
          test_cmd="dart test --exclude-tags soak --fail-fast --coverage=coverage"; \
        elif [ "$pkg" = "stem_cli" ]; then \
          test_cmd="STEM_CLI_RUN_MULTI=true dart test --fail-fast --coverage=coverage"; \
        else \
          test_cmd="dart test --fail-fast --coverage=coverage"; \
        fi; \
        if ! (cd "$dir" && eval "$test_cmd"); then \
          failures="$failures $pkg"; \
          continue; \
        fi; \
        if ! (cd "$dir" && dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib); then \
          failures="$failures $pkg"; \
          continue; \
        fi; \
        if ! (cd "$dir" && dart run ../../tool/coverage/coverage_badge.dart --lcov coverage/lcov.info --out coverage/coverage.json --min 80); then \
          failures="$failures $pkg"; \
          continue; \
        fi; \
      done; \
      if [ -n "$failures" ]; then \
        echo "Coverage failed for packages:$failures"; \
        exit 1; \
      fi
