#!/usr/bin/env bash
# Installs the official Swift 6 Linux toolchain from swift.org when `swift` is missing.
#
# Idempotent and safe to run in every fresh worktree:
# - `swift` already on PATH: prints its version and exits 0.
# - Toolchain already installed under the prefix: prints the PATH line and exits 0.
# - Otherwise downloads the release tarball for this distro and CPU from
#   download.swift.org, verifies its published PGP signature against the pinned
#   Swift 6.x release signing key, installs it under a user-writable prefix and
#   prints how to put it on PATH. No sudo, no system packages are changed.
#
# swift.org publishes a detached PGP signature (.sig) for each Linux toolchain,
# not a SHA-256 file; the signature is the published integrity check.
#
# Environment:
#   SWIFT_VERSION         toolchain version (default below)
#   SWIFT_INSTALL_PREFIX  install root (default: $HOME/.local/share/swift)
#
# Usage: scripts/bootstrap-swift.sh
set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.4.1}"
SWIFT_INSTALL_PREFIX="${SWIFT_INSTALL_PREFIX:-${HOME}/.local/share/swift}"

# Primary key fingerprint of "Swift 6.x Release Signing Key
# <swift-infrastructure@forums.swift.org>", from https://www.swift.org/keys/all-keys.asc.
SWIFT_6_SIGNING_KEY_FPR="52BB7E3DE28A71BE22EC05FFEF80A866B47A981F"
SWIFT_KEYS_URL="https://www.swift.org/keys/all-keys.asc"

log() { echo "bootstrap-swift: $*"; }
die() {
  echo "bootstrap-swift: ERROR: $*" >&2
  exit 1
}

if [[ "${SWIFT_VERSION}" != 6.* ]]; then
  die "SWIFT_VERSION must be a Swift 6 release (got '${SWIFT_VERSION}')."
fi

if command -v swift >/dev/null 2>&1; then
  log "swift is already on PATH: $(command -v swift)"
  swift --version
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  die "this script installs the Linux toolchain only. On macOS install Xcode."
fi

# --- Detect platform -------------------------------------------------------------
[[ -r /etc/os-release ]] || die "cannot read /etc/os-release to detect the distro."
# shellcheck disable=SC1091
os_id="$(. /etc/os-release && echo "${ID:-}")"
# shellcheck disable=SC1091
os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"

case "${os_id}" in
  ubuntu)
    platform_dir="ubuntu${os_version//./}"
    platform_file="ubuntu${os_version}"
    ;;
  debian)
    platform_dir="debian${os_version%%.*}"
    platform_file="${platform_dir}"
    ;;
  fedora)
    platform_dir="fedora${os_version}"
    platform_file="${platform_dir}"
    ;;
  amzn)
    platform_dir="amazonlinux${os_version}"
    platform_file="${platform_dir}"
    ;;
  rhel | centos | rocky | almalinux)
    platform_dir="ubi${os_version%%.*}"
    platform_file="${platform_dir}"
    ;;
  *)
    die "unsupported distro '${os_id} ${os_version}'. See https://www.swift.org/install/linux/."
    ;;
esac

case "$(uname -m)" in
  x86_64) arch_suffix="" ;;
  aarch64 | arm64) arch_suffix="-aarch64" ;;
  *) die "unsupported CPU '$(uname -m)'." ;;
esac

tag="swift-${SWIFT_VERSION}-RELEASE"
toolchain_name="${tag}-${platform_file}${arch_suffix}"
url="https://download.swift.org/swift-${SWIFT_VERSION}-release/${platform_dir}${arch_suffix}/${tag}/${toolchain_name}.tar.gz"
install_dir="${SWIFT_INSTALL_PREFIX}/${toolchain_name}"
current_link="${SWIFT_INSTALL_PREFIX}/current"
bin_dir="${current_link}/usr/bin"

print_path_help() {
  log "Put Swift on PATH for this shell with:"
  echo "  export PATH=\"${bin_dir}:\${PATH}\""
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${bin_dir}" >>"${GITHUB_PATH}"
    log "added ${bin_dir} to GITHUB_PATH for later CI steps."
  fi
}

if [[ -x "${install_dir}/usr/bin/swift" ]]; then
  ln -sfn "${install_dir}" "${current_link}"
  log "${toolchain_name} is already installed at ${install_dir}."
  print_path_help
  exit 0
fi

for tool in curl gpg tar; do
  command -v "${tool}" >/dev/null 2>&1 || die "'${tool}' is required but not installed."
done

# --- Download and verify -----------------------------------------------------------
mkdir -p "${SWIFT_INSTALL_PREFIX}"
work_dir="$(mktemp -d "${SWIFT_INSTALL_PREFIX}/.bootstrap.XXXXXX")"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

log "downloading ${url}"
curl --fail --location --silent --show-error --retry 3 -o "${work_dir}/toolchain.tar.gz" "${url}"
curl --fail --location --silent --show-error --retry 3 -o "${work_dir}/toolchain.tar.gz.sig" "${url}.sig"
# The keys file can be served with "Content-Encoding: gzip" even when the client
# did not ask for it; --compressed makes curl decode it so gpg gets plain ASCII armor.
# Only this download uses --compressed: the tarball must be saved byte-for-byte.
curl --fail --location --silent --show-error --retry 3 --compressed -o "${work_dir}/all-keys.asc" "${SWIFT_KEYS_URL}"

export GNUPGHOME="${work_dir}/gnupg"
mkdir -m 700 "${GNUPGHOME}"
gpg --batch --quiet --import "${work_dir}/all-keys.asc" 2>/dev/null ||
  die "could not import the swift.org signing keys."

log "verifying the PGP signature"
status="$(gpg --batch --status-fd 1 --verify "${work_dir}/toolchain.tar.gz.sig" "${work_dir}/toolchain.tar.gz" 2>/dev/null || true)"
# VALIDSIG fields: <signing fpr> <date> <ts> <expire> <ver> <rsv> <pk algo> <hash algo> <class> <primary fpr>
primary_fpr="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' <<<"${status}")"
if ! grep -q '^\[GNUPG:\] GOODSIG ' <<<"${status}" || [[ "${primary_fpr}" != "${SWIFT_6_SIGNING_KEY_FPR}" ]]; then
  echo "${status}" >&2
  die "signature check FAILED for ${toolchain_name}.tar.gz (expected key ${SWIFT_6_SIGNING_KEY_FPR}). Nothing was installed."
fi
log "signature OK (key ${SWIFT_6_SIGNING_KEY_FPR})"

# --- Install -----------------------------------------------------------------------
mkdir "${work_dir}/extract"
tar -xzf "${work_dir}/toolchain.tar.gz" -C "${work_dir}/extract"
[[ -x "${work_dir}/extract/${toolchain_name}/usr/bin/swift" ]] ||
  die "unexpected tarball layout: ${toolchain_name}/usr/bin/swift not found."

mv "${work_dir}/extract/${toolchain_name}" "${install_dir}"
ln -sfn "${install_dir}" "${current_link}"
log "installed ${toolchain_name} at ${install_dir}"

if ! "${install_dir}/usr/bin/swift" --version; then
  log "swift is installed but did not start. Install the system libraries listed at"
  log "https://www.swift.org/install/linux/ for ${os_id} ${os_version}, then re-run."
  exit 1
fi

print_path_help
