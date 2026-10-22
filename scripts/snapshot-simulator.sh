#!/usr/bin/env bash
# Finds, and when missing installs, the simulator the phone snapshot tests compare on, and prints
# its xcodebuild destination.
#
# The phone snapshot references (ChapterUISnapshotTesting) are recorded on an iPhone 17 Pro with
# iOS `ChapterSnapshot.referenceSystemVersion` (read from the harness source, e.g. "26.0"). The
# harness treats that version and its point releases ("26.0.1") as the reference system; other
# versions draw the system chrome differently, beyond the snapshot tolerance. Hosted macOS runner
# images carry a few iOS runtimes and swap them over time (macos-15 replaced iOS 26.0 with 26.0.1,
# next to 26.1 and 26.2), so a fixed `OS=26.0` destination stops matching any simulator. This:
#   1. waits until CoreSimulator lists the device or the reference runtime (a fresh runner can
#      still be loading its runtimes);
#   2. takes the available iOS runtime of the reference version, else the newest available point
#      release of it;
#   3. if there is none, downloads the reference version, or the first point release of it that
#      Xcode offers (`xcodebuild -downloadPlatform iOS -buildVersion <version>
#      -architectureVariant arm64 -exportPath`, then `simctl runtime add`: 8 GB), and takes that;
#   4. takes an available device of that name on that runtime, or creates one;
#   5. builds the runtime's dyld shared cache if it has none yet, boots the device and waits until
#      it has finished booting, at most SIMULATOR_BOOT_SECONDS; a boot that hangs is shut down
#      and tried again (the third time on an erased device);
#   6. prints `platform=iOS Simulator,id=<UDID>` on stdout (the log goes to stderr) and, on
#      GitHub Actions, writes `destination=` and `runtime=` to $GITHUB_OUTPUT.
# It never falls back to another iOS version: the snapshots are compared on the reference system
# or the script fails.
#
# Usage: scripts/snapshot-simulator.sh [device name]   (default: iPhone 17 Pro)
#   SNAPSHOT_IOS_VERSION     use this reference version instead of the harness's
#   SIMULATOR_WAIT_SECONDS   bound of the wait of step 1 (default 240)
#   SIMULATOR_BOOT_SECONDS   bound of each boot attempt of step 5 (default 180)
# Exit codes: 0 destination printed, 1 no reference runtime or device and none could be installed,
#   or the device did not finish booting.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness="${repo_root}/ios/Packages/ChapterUI/Sources/ChapterUISnapshotTesting/ChapterSnapshot.swift"
name="${1:-iPhone 17 Pro}"
wait_seconds="${SIMULATOR_WAIT_SECONDS:-240}"

log() { echo "$*" >&2; }

version="${SNAPSHOT_IOS_VERSION:-}"
if [[ -z "${version}" ]]; then
  version="$(sed -n 's/.*static let referenceSystemVersion = "\([0-9][0-9.]*\)".*/\1/p' "${harness}" | head -n 1)"
fi
if [[ ! "${version}" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  log "::error::No reference iOS version (ChapterSnapshot.referenceSystemVersion in ${harness}): '${version}'."
  exit 1
fi
if ! xcrun simctl list runtimes -j >/dev/null; then
  log "::error::xcrun simctl does not work (no Xcode selected? DEVELOPER_DIR=${DEVELOPER_DIR:-unset})."
  exit 1
fi

# The available iOS runtime of `version`, else the newest available point release of it, as
# "<identifier> <version> <build>"; empty when there is none.
reference_runtime() {
  xcrun simctl list runtimes available -j | jq -r --arg v "${version}" '
    [.runtimes[]
      | select(.platform == "iOS" and (.isAvailable // true))
      | select(.version == $v or (.version | startswith($v + ".")))]
    | (map(select(.version == $v)) + (sort_by(.version | split(".") | map(tonumber)) | reverse))
    | first // empty
    | "\(.identifier) \(.version) \(.buildversion)"'
}

has_device() {
  xcrun simctl list devices available | grep -qF "    ${name} ("
}

deadline=$((SECONDS + wait_seconds))
until [[ -n "$(reference_runtime)" ]] || has_device; do
  if ((SECONDS >= deadline)); then
    break
  fi
  log "Waiting for the iOS simulators to load ($((deadline - SECONDS)) s left)..."
  sleep 10
done

# Downloads the runtime disk image of the reference version, else of the first of its point
# releases on offer, for this Mac's architecture (-architectureVariant arm64 on Apple silicon),
# and adds it to CoreSimulator with `simctl runtime add`. On the macos-15 runner Xcode 26.3
# downloads iOS 26.0 (23A343, 7.5 GB) this way in about 3 min and adds it in about 1 min; asked
# to download and install it in one go, without the variant, it answers "iOS 26.0 is not
# available for download".
download_runtime() {
  local candidate output started dir image variant
  variant="universal"
  [[ "$(uname -m)" == arm64 ]] && variant="arm64"
  for candidate in "${version}" "${version}.1" "${version}.2" "${version}.3"; do
    dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/snapshot-runtime.XXXXXX")"
    log "Downloading iOS ${candidate} (${variant}): xcodebuild -downloadPlatform iOS" \
      "-buildVersion ${candidate} -architectureVariant ${variant} -exportPath ..."
    started=${SECONDS}
    if output="$(xcodebuild -downloadPlatform iOS -buildVersion "${candidate}" \
      -architectureVariant "${variant}" -exportPath "${dir}" 2>&1)"; then
      image="$(find "${dir}" -name '*.dmg' -type f -print -quit)"
      if [[ -n "${image}" ]]; then
        log "Downloaded $(basename "${image}") ($(du -h "${image}" | cut -f1)) in $((SECONDS - started)) s; adding it."
        started=${SECONDS}
        xcrun simctl runtime add "${image}" -m >&2 || log "simctl runtime add failed."
        rm -rf "${dir}"
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
          [[ -n "$(reference_runtime)" ]] && break
          sleep 5
        done
        if [[ -n "$(reference_runtime)" ]]; then
          log "Added iOS ${candidate} in $((SECONDS - started)) s."
          return 0
        fi
        log "iOS ${candidate} is still not an available runtime."
        continue
      else
        log "xcodebuild wrote no disk image."
      fi
    fi
    log "iOS ${candidate}: $(tr '\r' '\n' <<<"${output}" | grep -v '^[[:space:]]*$' | tail -n 2 | tr '\n' ' ')"
    rm -rf "${dir}"
  done
  return 1
}

runtime="$(reference_runtime)"
if [[ -z "${runtime}" ]]; then
  log "No iOS ${version} simulator runtime here (the references are recorded on it). Installed:"
  xcrun simctl list runtimes >&2
  if ! download_runtime; then
    log "::error::Could not download iOS ${version} or a point release of it."
    exit 1
  fi
  deadline=$((SECONDS + 120))
  until [[ -n "$(reference_runtime)" ]]; do
    if ((SECONDS >= deadline)); then
      log "::error::iOS ${version} is still not an available simulator runtime after the download."
      xcrun simctl list runtimes >&2
      exit 1
    fi
    sleep 5
  done
  runtime="$(reference_runtime)"
fi
read -r runtime_id runtime_version runtime_build <<<"${runtime}"
log "Snapshot runtime: iOS ${runtime_version} (${runtime_build}), ${runtime_id}; references: iOS ${version}."

udid="$(xcrun simctl list devices available -j | jq -r --arg rt "${runtime_id}" --arg name "${name}" \
  '.devices[$rt][]? | select(.name == $name) | .udid' | head -n 1)"
if [[ -z "${udid}" ]]; then
  device_type="$(xcrun simctl list devicetypes -j \
    | jq -r --arg name "${name}" '.devicetypes[] | select(.name == $name) | .identifier' | head -n 1)"
  if [[ -z "${device_type}" ]]; then
    log "::error::No ${name} device type to create the snapshot simulator with."
    exit 1
  fi
  log "Creating ${name} on iOS ${runtime_version}."
  udid="$(xcrun simctl create "${name}" "${device_type}" "${runtime_id}")"
fi

# The runtime's dyld shared cache: a no-op when it exists (as on the runner image); a runtime
# downloaded above has none yet, and building it (213 s on the runner) is better done now than
# while the tests run.
started=${SECONDS}
xcrun simctl runtime dyld_shared_cache update "${runtime_id}" >&2
log "dyld shared cache of iOS ${runtime_version} ready ($((SECONDS - started)) s)."

# Boots the device and waits until it has finished booting (data migration, BackBoard, the system
# app), for at most $1 seconds. On the macos-15 runner the first boot of an iOS 26.0.1 device
# often stops at "Waiting on BackBoard" for good (9 of 15 first boots in October 2026, none got
# past it in 180-240 s; left to xcodebuild, such a device hangs app launches and accessibility
# and runs the tests several times slower), while a second boot after `simctl shutdown` finished
# in 41-75 s every time (5 of 5).
boot_device() {
  local limit=$1 started=${SECONDS} status_log pid
  status_log="$(mktemp -t snapshot-simulator-boot)"
  xcrun simctl bootstatus "${udid}" -b >"${status_log}" 2>&1 &
  pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    if ((SECONDS - started >= limit)); then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      log "Not booted after ${limit} s, still at: $(grep -E $'^\t[A-Z]' "${status_log}" | tail -n 1 | tr -d '\t')."
      rm -f "${status_log}"
      return 1
    fi
    sleep 2
  done
  if wait "${pid}"; then
    # The stages it went through, or simctl's one line ("Device already booted, ...").
    local stages
    stages="$(grep -E $'^\t[A-Z]' "${status_log}" | tr -d '\t' | uniq | paste -sd ',' - | sed 's/,/, /g')"
    [[ -n "${stages}" ]] || stages="$(grep -v -e '^Monitoring' -e '^$' "${status_log}" | head -n 1)"
    log "${name} booted in $((SECONDS - started)) s (${stages})."
    rm -f "${status_log}"
    return 0
  fi
  log "simctl bootstatus failed:"
  cat "${status_log}" >&2
  rm -f "${status_log}"
  return 1
}

boot_seconds="${SIMULATOR_BOOT_SECONDS:-180}"
booted=0
for attempt in 1 2 3; do
  log "Booting ${name} on iOS ${runtime_version} (attempt ${attempt} of 3, at most ${boot_seconds} s)..."
  if boot_device "${boot_seconds}"; then
    booted=1
    break
  fi
  xcrun simctl shutdown "${udid}" >&2 || true
  if ((attempt == 2)); then
    log "Erasing ${name}."
    xcrun simctl erase "${udid}" >&2
  fi
done
if ((booted == 0)); then
  log "::error::${name} on iOS ${runtime_version} did not finish booting in 3 attempts."
  exit 1
fi

destination="platform=iOS Simulator,id=${udid}"
log "Snapshot simulator: ${name} (${udid}) on iOS ${runtime_version}."
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "destination=${destination}"
    echo "runtime=iOS ${runtime_version} (${runtime_build})"
  } >>"${GITHUB_OUTPUT}"
fi
echo "${destination}"
