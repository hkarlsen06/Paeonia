#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$REPOSITORY_ROOT/ios/BuildNumber.xcconfig"
BUILD_NUMBER="$(TZ=Europe/Oslo date +%Y%m%d.%H%M)"
TEMP_PATH="$(mktemp "${TMPDIR:-/tmp}/Paeonia-BuildNumber.XXXXXX")"

cleanup() {
  rm -f "$TEMP_PATH"
}
trap cleanup EXIT

printf 'CURRENT_PROJECT_VERSION = %s\n' "$BUILD_NUMBER" > "$TEMP_PATH"

if [ ! -f "$OUTPUT_PATH" ] || ! cmp -s "$TEMP_PATH" "$OUTPUT_PATH"; then
  mv "$TEMP_PATH" "$OUTPUT_PATH"
fi

echo "Generated CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
