#!/usr/bin/env bash
# PDF check: qpdf --check must be clean and pdftotext must extract some text.
# Runs inside the pinned Debian image started by scripts/verify-exports.sh.
# Usage: pdf.sh <file> [<file> ...]
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends qpdf poppler-utils >/dev/null

failed=0
for path in "$@"; do
  if ! qpdf_log="$(qpdf --check "${path}" 2>&1)"; then
    echo "FAIL ${path}: qpdf --check"
    echo "${qpdf_log}"
    failed=1
    continue
  fi
  if ! text="$(pdftotext -q "${path}" - 2>&1)"; then
    echo "FAIL ${path}: pdftotext could not read the file"
    failed=1
    continue
  fi
  if [[ -z "${text//[[:space:]]/}" ]]; then
    echo "FAIL ${path}: pdftotext found no text"
    failed=1
    continue
  fi
  echo "OK   ${path}: qpdf check clean, text present"
done
exit "${failed}"
