#!/bin/sh
# LAS check: `pdal info --summary` must read the file and report one or more points.
# Runs inside the pinned PDAL image started by scripts/verify-exports.sh. POSIX sh,
# because the PDAL image is not guaranteed to ship bash.
# Usage: las.sh <file> [<file> ...]
set -eu

failed=0
for path in "$@"; do
  if ! summary="$(pdal info --summary "${path}" 2>&1)"; then
    echo "FAIL ${path}: pdal info"
    echo "${summary}"
    failed=1
    continue
  fi
  count="$(printf '%s' "${summary}" | grep -o '"num_points": *[0-9]*' | head -n 1 | grep -o '[0-9]*$' || true)"
  if [ -z "${count}" ] || [ "${count}" -eq 0 ]; then
    echo "FAIL ${path}: no points reported"
    failed=1
    continue
  fi
  echo "OK   ${path}: ${count} points"
done
exit "${failed}"
