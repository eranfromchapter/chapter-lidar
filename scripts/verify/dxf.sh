#!/usr/bin/env bash
# DXF check: installs the pinned ezdxf and runs dxf.py.
# Runs inside the pinned Python image started by scripts/verify-exports.sh.
# Usage: dxf.sh <ezdxf-version> <file> [<file> ...]
set -euo pipefail

ezdxf_version="$1"
shift

pip install --quiet --disable-pip-version-check --no-cache-dir "ezdxf==${ezdxf_version}" >/dev/null

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python "${script_dir}/dxf.py" "$@"
