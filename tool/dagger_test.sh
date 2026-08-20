#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DAGGER_BIN="${DAGGER_BIN:-dagger}"
DAGGER_PROGRESS="${DAGGER_PROGRESS:-plain}"
DAGGER_CALL="${1:-all}"

if ! command -v "$DAGGER_BIN" >/dev/null 2>&1 && [[ ! -x "$DAGGER_BIN" ]]; then
  echo "Dagger CLI is required. Install it or set DAGGER_BIN to its path." >&2
  exit 1
fi

staged_source="$(mktemp -d "${TMPDIR:-/tmp}/stem-dagger-source.XXXXXX")"
cleanup() {
  rm -rf "$staged_source"
}
trap cleanup EXIT

cd "$REPO_ROOT"

# Dagger's source input is content-addressed before the pipeline starts. Send
# only tracked files plus non-ignored working files so local build artifacts
# cannot turn a test run into a multi-gigabyte source upload.
git ls-files --cached --others --exclude-standard -z \
  | while IFS= read -r -d '' path; do
      [[ -e "$path" ]] && printf '%s\0' "$path"
    done \
  | tar --null --files-from=- --create \
  | tar --directory="$staged_source" --extract

"$DAGGER_BIN" \
  --mod .dagger \
  call "$DAGGER_CALL" \
  --source="$staged_source" \
  --progress="$DAGGER_PROGRESS"
