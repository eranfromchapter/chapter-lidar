#!/usr/bin/env bash
# Starts the local station stack (Postgres, Azurite, API with the fake HUB) in the background
# and waits until every service is healthy. Safe to re-run while the stack is up. Works from
# any directory. The API applies migrations before it serves.
#
#   station/api/scripts/local-up.sh
#   curl http://localhost:8080/health
#
# Stop with station/api/scripts/local-down.sh.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose_file="${script_dir}/../docker-compose.yml"

if ! command -v docker >/dev/null 2>&1; then
  echo "local-up: docker is not installed or not on PATH" >&2
  exit 1
fi

# Optional CA certificate for npm inside the image build, for TLS-intercepting proxies.
if [[ -z "${STATION_BUILD_CA_FILE:-}" && -n "${NODE_EXTRA_CA_CERTS:-}" && -s "${NODE_EXTRA_CA_CERTS}" ]]; then
  export STATION_BUILD_CA_FILE="${NODE_EXTRA_CA_CERTS}"
fi

if ! docker compose -f "${compose_file}" up --detach --build --wait --wait-timeout 300; then
  echo "local-up: the stack did not become healthy; recent logs:" >&2
  docker compose -f "${compose_file}" ps >&2 || true
  docker compose -f "${compose_file}" logs --tail 50 >&2 || true
  exit 1
fi

port="${STATION_API_PORT:-8080}"
echo "local-up: station stack is up"
echo "  API       http://localhost:${port}/health"
echo "  Postgres  postgres://station@127.0.0.1:${STATION_PG_PORT:-55432}/station"
echo "  Azurite   http://localhost:${STATION_AZURITE_PORT:-10000}/devstoreaccount1"
