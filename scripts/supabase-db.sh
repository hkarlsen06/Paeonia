#!/bin/sh
# Run a Supabase CLI `db` subcommand against the self-hosted Paeonia database on mdr.
# Postgres there is bound to localhost only, so this opens an SSH tunnel for the
# duration of the command and reads the password from the stack's .env over SSH.
#
#   ./scripts/supabase-db.sh push --dry-run
#   ./scripts/supabase-db.sh push
#   ./scripts/supabase-db.sh pull
set -eu

host=mdr
remote_port=5433          # supavisor session-mode port on mdr (see docker-compose.override.yml)
local_port=${PAEONIA_DB_TUNNEL_PORT:-54399}
stack_env=/srv/paeonia/paeonia-sb/.env

password=$(ssh "$host" "grep '^POSTGRES_PASSWORD=' $stack_env | cut -d= -f2-")
password=$(printf %s "$password" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')

ssh -f -N -M -S "/tmp/paeonia-db-tunnel.$$" -o ExitOnForwardFailure=yes \
  -L "$local_port:127.0.0.1:$remote_port" "$host"
cleanup() { ssh -S "/tmp/paeonia-db-tunnel.$$" -O exit "$host" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

supabase db "$@" --db-url "postgresql://postgres.paeonia:$password@127.0.0.1:$local_port/postgres?sslmode=disable"
