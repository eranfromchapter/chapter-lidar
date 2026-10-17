#!/usr/bin/env bash
# Runs `swift test` for every Swift package under contract/swift and ios/Packages.
#
# - A Swift package is a directory that contains Package.swift.
# - A package with an `.apple-only` marker file at its root is skipped (it needs
#   Apple frameworks and is tested on the macOS runner). Each skip is printed.
# - No Swift packages at all: prints that and exits 0.
# - Packages exist but `swift` is not on PATH: fails loudly. Run
#   scripts/bootstrap-swift.sh first.
#
# Usage: scripts/swift-test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

packages=()

# contract/swift is a single package.
if [[ -f "${repo_root}/contract/swift/Package.swift" ]]; then
  packages+=("contract/swift")
fi

# ios/Packages/<Name> are individual packages.
if [[ -d "${repo_root}/ios/Packages" ]]; then
  while IFS= read -r manifest; do
    packages+=("$(dirname "${manifest#"${repo_root}/"}")")
  done < <(find "${repo_root}/ios/Packages" -mindepth 2 -maxdepth 2 -name Package.swift -type f | LC_ALL=C sort)
fi

if [[ ${#packages[@]} -eq 0 ]]; then
  echo "swift-test: no Swift packages found under contract/swift or ios/Packages; nothing to test."
  exit 0
fi

runnable=()
for package in "${packages[@]}"; do
  if [[ -e "${repo_root}/${package}/.apple-only" ]]; then
    echo "swift-test: SKIP ${package} (.apple-only marker; tested on the macOS runner)"
  else
    runnable+=("${package}")
  fi
done

if [[ ${#runnable[@]} -eq 0 ]]; then
  echo "swift-test: every Swift package is marked .apple-only; nothing to test on this host."
  exit 0
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift-test: FAIL: 'swift' is not on PATH but these packages need testing:" >&2
  printf '  %s\n' "${runnable[@]}" >&2
  echo "swift-test: run scripts/bootstrap-swift.sh and put the toolchain on PATH." >&2
  exit 1
fi

swift --version

failed=()
for package in "${runnable[@]}"; do
  echo "swift-test: swift test --package-path ${package}"
  if ! swift test --package-path "${repo_root}/${package}"; then
    failed+=("${package}")
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "swift-test: FAIL in:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi

echo "swift-test: all ${#runnable[@]} package(s) passed."
