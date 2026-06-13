#!/usr/bin/env bash
set -euo pipefail

MODE="staged"

while [ $# -gt 0 ]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
    *)
      echo "usage: $0 [--all]" >&2
      exit 2
      ;;
  esac
done

NOTICE_THRESHOLD="${SWIFT_FILE_LENGTH_NOTICE:-300}"
CONCERN_THRESHOLD="${SWIFT_FILE_LENGTH_CONCERN:-450}"

if ! [[ "$NOTICE_THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$CONCERN_THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "SWIFT_FILE_LENGTH_NOTICE and SWIFT_FILE_LENGTH_CONCERN must be numeric" >&2
  exit 2
fi

if [ "$MODE" = "all" ]; then
  FILES="$(git ls-files 'ios/**/*.swift')"
else
  FILES="$(
    git diff --cached --name-only --diff-filter=ACMR |
      grep -E '^ios/.*\.swift$' || true
  )"
fi

if [ -z "$FILES" ]; then
  exit 0
fi

FOUND=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue

  case "$file" in
    *"/.build/"*|*"/DerivedData/"*|*"/Generated/"*)
      continue
      ;;
  esac

  lines="$(wc -l < "$file" | tr -d '[:space:]')"

  if [ "$lines" -ge "$CONCERN_THRESHOLD" ]; then
    FOUND=1
    echo "[file-length] high concern: $file has $lines lines"
  elif [ "$lines" -ge "$NOTICE_THRESHOLD" ]; then
    FOUND=1
    echo "[file-length] notice: $file has $lines lines"
  fi
done <<< "$FILES"

if [ "$FOUND" -eq 1 ]; then
  cat <<EOF
[file-length] Advisory only. There is no hard file-length limit.
[file-length] Consider splitting large Swift files when there is a clear boundary:
[file-length] subviews, styles, helpers, repositories, services, protocols, or pure logic.
EOF
fi
