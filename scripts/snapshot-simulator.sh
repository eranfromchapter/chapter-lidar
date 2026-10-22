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
#   3. if there is none, downloads the reference version
#      (`xcodebuild -downloadPlatform iOS -buildVersion <version>`: about 8 GB, several minutes)
#      and takes that;
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

runtime="$(reference_runtime)"
if [[ -z "${runtime}" ]]; then
  log "No iOS ${version} simulator runtime here (the references are recorded on it). Installed:"
  xcrun simctl list runtimes >&2
  log "Downloading iOS ${version} (xcodebuild -downloadPlatform iOS -buildVersion ${version})..."
  started=${SECONDS}
  xcodebuild -downloadPlatform iOS -buildVersion "${version}" >&2
  log "Downloaded and installed iOS ${version} in $((SECONDS - started)) s."
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

# The runtime's dyld shared cache: a no-op when it exists (as on the runner image), else built
# now rather than while the tests run.
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
