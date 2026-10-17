#!/usr/bin/env bash
# Pushes HEAD to its branch on origin, waits for the push-triggered run of a GitHub
# Actions workflow for the HEAD commit, and exits with its result.
#
# Usage: scripts/wait-workflow.sh <workflow> [job]
#
#   <workflow>  workflow file name (e.g. ci.yml) or numeric workflow id
#   [job]       optional job name. When given, the script exits with that job's result
#               as soon as it completes. Matrix jobs named "<job> (...)" also match;
#               every match must succeed.
#
# Exit codes: 0 success, 1 failure/cancelled/not found, 2 usage error, 124 timeout.
# Times out after 45 minutes. Uses only GitHub REST endpoints through `gh api`
# (no GraphQL). The repo is taken from GH_REPO (owner/name) or the origin URL.
set -euo pipefail

TIMEOUT_SECONDS=$((45 * 60))
POLL_SECONDS="${WAIT_WORKFLOW_POLL_SECONDS:-15}"

log() { echo "wait-workflow: $*"; }
die() {
  echo "wait-workflow: ERROR: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || {
  echo "usage: scripts/wait-workflow.sh <workflow> [job]" >&2
  exit 2
}
workflow="$1"
job="${2:-}"

command -v gh >/dev/null 2>&1 || die "the gh CLI is required."
command -v git >/dev/null 2>&1 || die "git is required."

# gh api with up to 3 attempts, so one transient API error does not end a long wait.
gh_api() {
  local attempt output
  for attempt in 1 2 3; do
    if output="$(gh api "$@")"; then
      printf '%s\n' "${output}"
      return 0
    fi
    echo "wait-workflow: gh api failed (attempt ${attempt} of 3)" >&2
    sleep 5
  done
  return 1
}

branch="$(git symbolic-ref --quiet --short HEAD)" || die "HEAD is detached; check out a branch first."
sha="$(git rev-parse HEAD)"

repo="${GH_REPO:-}"
if [[ -z "${repo}" ]]; then
  origin_url="$(git remote get-url origin)" || die "no 'origin' remote."
  # Accepts https://github.com/owner/name(.git), git@github.com:owner/name(.git),
  # and ssh://git@github.com/owner/name(.git).
  repo="$(sed -E -e 's#^(https?://[^/]+/|ssh://[^/]+/|[^@]+@[^:]+:)##' -e 's#\.git$##' <<<"${origin_url}")"
fi
[[ "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "cannot work out owner/name from '${repo}'. Set GH_REPO."

log "pushing ${sha:0:12} to origin/${branch}"
git push origin "HEAD:refs/heads/${branch}"

deadline=$(($(date +%s) + TIMEOUT_SECONDS))
check_timeout() {
  if (($(date +%s) >= deadline)); then
    echo "wait-workflow: TIMEOUT after 45 minutes waiting for ${workflow}${job:+ / ${job}} on ${sha:0:12}" >&2
    exit 124
  fi
}

# --- Find the push-triggered run for HEAD -----------------------------------------
run_id=""
log "waiting for a push run of ${workflow} for ${sha:0:12} in ${repo}"
while [[ -z "${run_id}" ]]; do
  run_id="$(gh_api -X GET "repos/${repo}/actions/workflows/${workflow}/runs" \
    -f head_sha="${sha}" -f event=push -f branch="${branch}" -f per_page=20 \
    --jq '[.workflow_runs[]] | sort_by(.run_number) | last | .id // empty')"
  if [[ -z "${run_id}" ]]; then
    check_timeout
    sleep "${POLL_SECONDS}"
  fi
done

run_url="$(gh_api "repos/${repo}/actions/runs/${run_id}" --jq '.html_url')"
log "run ${run_id}: ${run_url}"

# --- Wait for the named job ---------------------------------------------------------
if [[ -n "${job}" ]]; then
  while true; do
    # One line per matching job: "<status>\t<conclusion>\t<name>"
    jobs="$(gh_api --paginate -X GET "repos/${repo}/actions/runs/${run_id}/jobs" \
      -f filter=latest -f per_page=100 \
      --jq '.jobs[] | [.status, (.conclusion // "none"), .name] | @tsv')"
    matching="$(awk -F '\t' -v job="${job}" '$3 == job || index($3, job " (") == 1' <<<"${jobs}")"
    run_status="$(gh_api "repos/${repo}/actions/runs/${run_id}" --jq '.status')"

    if [[ -z "${matching}" ]]; then
      if [[ "${run_status}" == "completed" ]]; then
        die "run ${run_id} completed without a job named '${job}'."
      fi
    elif ! awk -F '\t' '$1 != "completed" { found = 1 } END { exit found ? 0 : 1 }' <<<"${matching}"; then
      # Every matching job is completed.
      echo "${matching}" | awk -F '\t' '{ printf "wait-workflow: job %s: %s\n", $3, $2 }'
      if awk -F '\t' '$2 != "success" { bad = 1 } END { exit bad ? 0 : 1 }' <<<"${matching}"; then
        die "job '${job}' did not succeed. ${run_url}"
      fi
      log "job '${job}' succeeded."
      exit 0
    fi
    check_timeout
    sleep "${POLL_SECONDS}"
  done
fi

# --- Wait for the whole run -----------------------------------------------------------
while true; do
  read -r status conclusion < <(gh_api "repos/${repo}/actions/runs/${run_id}" --jq '"\(.status) \(.conclusion // "none")"')
  if [[ "${status}" == "completed" ]]; then
    log "run ${run_id}: ${conclusion}"
    [[ "${conclusion}" == "success" ]] || die "workflow ${workflow} concluded '${conclusion}'. ${run_url}"
    exit 0
  fi
  check_timeout
  sleep "${POLL_SECONDS}"
done
