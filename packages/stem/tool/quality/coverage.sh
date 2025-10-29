#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-.dart_tool/coverage}" 
RAW_DIR="$OUTPUT_DIR/raw"
LCOV_FILE="$OUTPUT_DIR/lcov.info"
THRESHOLD="${COVERAGE_THRESHOLD:-60}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$RAW_DIR"

echo "Running tests with coverage (output: $OUTPUT_DIR)"
dart test --exclude-tags soak --coverage="$RAW_DIR"

dart run coverage:format_coverage \
  --lcov \
  --in="$RAW_DIR" \
  --out="$LCOV_FILE" \
  --report-on=lib \
  --packages=.dart_tool/package_config.json

echo "Coverage report saved to $LCOV_FILE"

# Optionally remove files from the coverage report. By default we exclude
# components that require external services to exercise (e.g. Postgres-backed
# schedule stores) so that coverage thresholds reflect runnable test suites.
EXCLUDES=${COVERAGE_EXCLUDE:-"lib/src/scheduler/postgres_schedule_store.dart,lib/src/backend/postgres_backend.dart,lib/src/control/postgres_revoke_store.dart"}
if [[ -n "$EXCLUDES" ]]; then
  TMP_LCOV="${LCOV_FILE}.tmp"
  mv "$LCOV_FILE" "$TMP_LCOV"
  awk -v patterns="$EXCLUDES" '
    BEGIN {
      split(patterns, pat, /[, \n]+/);
    }
    /^SF:/ {
      keep = 1;
      for (i in pat) {
        if (length(pat[i]) > 0 && index($0, pat[i]) > 0) {
          keep = 0;
          break;
        }
      }
    }
    /^end_of_record/ {
      if (keep) {
        print $0;
      }
      next;
    }
    {
      if (keep) {
        print $0;
      }
    }
  ' "$TMP_LCOV" > "$LCOV_FILE"
  rm -f "$TMP_LCOV"
fi

read -r COVERED TOTAL <<<"$(awk -F: '
  /^LH:/ {covered += $2}
  /^LF:/ {total += $2}
  END {print (covered+0)" "(total+0)}
' "$LCOV_FILE")"

percentage() {
  local num=$1
  local denom=$2
  if [[ "$denom" -eq 0 ]]; then
    echo "0.00"
    return
  fi
  awk -v n="$num" -v d="$denom" 'BEGIN {printf "%.2f", (n / d) * 100}'
}

COVERAGE_PCT=$(percentage "$COVERED" "$TOTAL")

echo "Lines covered: $COVERED / $TOTAL ($COVERAGE_PCT%)"

awk -v pct="$COVERAGE_PCT" -v threshold="$THRESHOLD" 'BEGIN {
  if (pct+0 < threshold+0) {
    printf "Coverage %.2f%% is below threshold %.2f%%\n", pct, threshold;
    exit 1;
  }
}'

echo "Coverage meets threshold (${THRESHOLD}%)."
