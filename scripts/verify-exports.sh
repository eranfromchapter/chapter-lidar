#!/usr/bin/env bash
# Checks exported files with independent validators (not the code that wrote them).
#
# Usage: scripts/verify-exports.sh <dxf|pdf|preview|gltf|las> <dir>
#
#   dxf      every *.dxf          ezdxf strict read + audit, no errors allowed    Docker
#   pdf      every *.pdf          qpdf --check, and pdftotext must find text      Docker
#   preview  every *.png / *.svg  Pillow verify + full decode / xmllint --noout   Docker
#   gltf     every *.glb / *.gltf Khronos glTF-Validator, zero errors allowed      npm (root devDependency)
#   las      every *.las          PDAL info, must report one or more points       Docker
#
# Files are found recursively under <dir>. Zero matching files is an error.
# Exits non-zero on any error. Docker images and tool versions are pinned below;
# the validators themselves live in scripts/verify/.
set -euo pipefail

# Pinned images and tool versions. Change only on purpose, in one commit.
PYTHON_IMAGE="python:3.12.15-slim-bookworm"
DEBIAN_IMAGE="debian:bookworm-20261005-slim"
PDAL_IMAGE="pdal/pdal:2.9.2"
EZDXF_VERSION="1.4.5"
PILLOW_VERSION="12.2.0"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "usage: scripts/verify-exports.sh <dxf|pdf|preview|gltf|las> <dir>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
kind="$1"
[[ -d "$2" ]] || {
  echo "verify-exports: '$2' is not a directory" >&2
  exit 2
}
dir="$(cd "$2" && pwd)"

case "${kind}" in
  dxf) patterns=("*.dxf") ;;
  pdf) patterns=("*.pdf") ;;
  preview) patterns=("*.png" "*.svg") ;;
  gltf) patterns=("*.glb" "*.gltf") ;;
  las) patterns=("*.las") ;;
  *) usage ;;
esac

# Collect files (relative to dir) for the requested kind.
find_args=()
for pattern in "${patterns[@]}"; do
  [[ ${#find_args[@]} -gt 0 ]] && find_args+=("-o")
  find_args+=("-iname" "${pattern}")
done
files=()
while IFS= read -r -d '' file; do
  files+=("${file#./}")
done < <(cd "${dir}" && find . -type f \( "${find_args[@]}" \) -print0 | LC_ALL=C sort -z)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "verify-exports: FAIL: no ${kind} files (${patterns[*]}) under ${dir}" >&2
  exit 1
fi

echo "verify-exports: ${kind}: ${#files[@]} file(s) under ${dir}"

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "verify-exports: FAIL: docker is required for '${kind}' checks but is not installed." >&2
    exit 1
  fi
}

# Runs a validator from scripts/verify in a pinned image. <dir> is mounted read-only
# at /data (the working directory) and scripts/verify read-only at /verify.
in_docker() {
  local image="$1"
  shift
  docker run --rm \
    -v "${dir}:/data:ro" \
    -v "${repo_root}/scripts/verify:/verify:ro" \
    -w /data "${image}" "$@"
}

case "${kind}" in
  dxf)
    require_docker
    in_docker "${PYTHON_IMAGE}" bash /verify/dxf.sh "${EZDXF_VERSION}" "${files[@]}"
    ;;
  pdf)
    require_docker
    in_docker "${DEBIAN_IMAGE}" bash /verify/pdf.sh "${files[@]}"
    ;;
  preview)
    require_docker
    in_docker "${PYTHON_IMAGE}" bash /verify/preview.sh "${PILLOW_VERSION}" "${files[@]}"
    ;;
  gltf)
    absolute=()
    for file in "${files[@]}"; do
      absolute+=("${dir}/${file}")
    done
    node "${repo_root}/scripts/verify/gltf.mjs" "${absolute[@]}"
    ;;
  las)
    require_docker
    in_docker "${PDAL_IMAGE}" sh /verify/las.sh "${files[@]}"
    ;;
esac

echo "verify-exports: ${kind}: all ${#files[@]} file(s) passed."
