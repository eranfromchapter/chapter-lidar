#!/usr/bin/env bash
# Preview check: SVG must be well-formed XML (xmllint), PNG must decode (Pillow, png.py).
# Runs inside the pinned Python image started by scripts/verify-exports.sh.
# Usage: preview.sh <pillow-version> <file> [<file> ...]
set -euo pipefail

pillow_version="$1"
shift

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends libxml2-utils >/dev/null
pip install --quiet --disable-pip-version-check --no-cache-dir "Pillow==${pillow_version}" >/dev/null

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
pngs=()
for path in "$@"; do
  case "${path,,}" in
    *.svg)
      if xmllint --noout --nonet "${path}"; then
        echo "OK   ${path}: well-formed SVG"
      else
        echo "FAIL ${path}: xmllint"
        failed=1
      fi
      ;;
    *.png) pngs+=("${path}") ;;
    *)
      echo "FAIL ${path}: not a PNG or SVG file"
      failed=1
      ;;
  esac
done

if [[ ${#pngs[@]} -gt 0 ]]; then
  python "${script_dir}/png.py" "${pngs[@]}" || failed=1
fi
exit "${failed}"
