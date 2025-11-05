#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PACKAGE_DIR"

echo "Fetching package dependencies..."
dart pub get >/dev/null

echo "Running format check..."
dart format --set-exit-if-changed .

echo "Running analyzer..."
dart analyze

echo "Running tests (excluding soak)..."
dart test --exclude-tags soak

if [[ "${RUN_COVERAGE:-1}" != "0" ]]; then
  echo "Running coverage (threshold ${COVERAGE_THRESHOLD:-80}%)..."
  "$SCRIPT_DIR/coverage.sh"
else
  echo "Skipping coverage (RUN_COVERAGE=0)."
fi

echo "Quality checks completed."
