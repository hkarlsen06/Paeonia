#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

diff_file=$(mktemp "${TMPDIR:-/tmp}/paeonia-schema-diff.XXXXXX")
log_file=$(mktemp "${TMPDIR:-/tmp}/paeonia-schema-diff-log.XXXXXX")

cleanup() {
  rm -f "$diff_file" "$log_file"
}
trap cleanup EXIT HUP INT TERM

if ! supabase db diff \
  --use-pg-delta \
  --schema public,internal,storage_private,auth,storage \
  --output "$diff_file" >"$log_file" 2>&1; then
  cat "$log_file" >&2
  exit 1
fi

cat "$log_file"

if [ -s "$diff_file" ]; then
  printf '\nDeclarative schema drift detected:\n\n' >&2
  cat "$diff_file" >&2
  printf '\nUpdate supabase/schemas/ and the reviewed migration together.\n' >&2
  exit 1
fi

printf 'Declarative schema and migration history match.\n'
