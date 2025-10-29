#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

echo "Running format check..."
dart format --set-exit-if-changed .

echo "Running analyzer..."
dart analyze

echo "Running tests (excluding soak)..."
dart test --exclude-tags soak

if [[ "${RUN_COVERAGE:-1}" != "0" ]]; then
  echo "Running coverage (threshold ${COVERAGE_THRESHOLD:-80}%)..."
  tool/quality/coverage.sh
else
  echo "Skipping coverage (RUN_COVERAGE=0)."
fi

echo "Quality checks completed."
