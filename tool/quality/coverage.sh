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
