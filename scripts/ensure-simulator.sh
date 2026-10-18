#!/usr/bin/env bash
# Makes sure an available iOS simulator with the given name exists before `xcodebuild test`.
#
# On a fresh macOS runner CoreSimulator can still be loading its runtimes when a fast job reaches
# its test step; xcodebuild then lists only "Any iOS Simulator Device" and fails with "Unable to
# find a device matching the provided destination specifier". This waits for the device to show
# up and, if it never does, creates it on the newest available iOS runtime.
#
# Usage: scripts/ensure-simulator.sh [device name]   (default: iPhone 17 Pro)
# Exit codes: 0 device available, 1 no iOS runtime or device type to create it with.
set -euo pipefail

name="${1:-iPhone 17 Pro}"
wait_seconds="${SIMULATOR_WAIT_SECONDS:-240}"

has_device() {
  xcrun simctl list devices available | grep -qF "    ${name} ("
}

deadline=$((SECONDS + wait_seconds))
until has_device; do
  if ((SECONDS >= deadline)); then
    break
  fi
  echo "Waiting for the ${name} simulator ($((deadline - SECONDS)) s left)..."
  sleep 10
done

if has_device; then
  echo "${name} simulator is available."
  exit 0
fi

runtime="$(xcrun simctl list runtimes available -j \
  | jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty')"
device_type="$(xcrun simctl list devicetypes -j \
  | jq -r --arg name "${name}" '.devicetypes[] | select(.name == $name) | .identifier' | head -n 1)"

if [[ -z "${runtime}" || -z "${device_type}" ]]; then
  echo "::error::No ${name} simulator, and no iOS runtime (${runtime:-none}) or device type (${device_type:-none}) to create one."
  xcrun simctl list runtimes
  exit 1
fi

echo "Creating ${name} on ${runtime}."
xcrun simctl create "${name}" "${device_type}" "${runtime}"
has_device
