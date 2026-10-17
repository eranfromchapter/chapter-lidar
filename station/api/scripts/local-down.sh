#!/usr/bin/env bash
# Stops the local station stack and deletes its data volumes. Works from any directory.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker compose -f "${script_dir}/../docker-compose.yml" down --volumes --remove-orphans
