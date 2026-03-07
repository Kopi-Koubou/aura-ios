#!/bin/bash
# Runs fixture-mode regression checks for applying readiness page limits from metrics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/apply-readiness-page-limits-from-metrics.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Readiness page-limit apply fixture tests failed: could not locate repository root."
  exit 1
fi

APPLY_SCRIPT="${REPO_ROOT}/scripts/apply-readiness-page-limits-from-metrics.sh"

for dependency in jq mktemp grep sed; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Readiness page-limit apply fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${APPLY_SCRIPT}" ]; then
  echo "Readiness page-limit apply fixture tests failed: missing script ${APPLY_SCRIPT}."
  exit 1
fi

TMP_FIXTURE_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_FIXTURE_DIR}"
}
trap cleanup EXIT

run_fixture_case() {
  local expected_exit="$1"
  local label="$2"
  shift 2

  echo ""
  echo "Case: ${label}"

  set +e
  CASE_OUTPUT="$("$@" 2>&1)"
  local actual_exit=$?
  set -e

  if [ "${actual_exit}" -ne "${expected_exit}" ]; then
    echo "${CASE_OUTPUT}"
    echo "Case failed: expected exit ${expected_exit}, got ${actual_exit}."
    exit 1
  fi

  echo "Case passed."
}

assert_case_output_contains() {
  local expected_text="$1"
  if ! printf '%s\n' "${CASE_OUTPUT}" | grep -Fq "${expected_text}"; then
    echo "${CASE_OUTPUT}"
    echo "Case failed: expected output to contain '${expected_text}'."
    exit 1
  fi
}

assert_file_contains() {
  local file_path="$1"
  local expected_text="$2"
  if ! grep -Fq "${expected_text}" "${file_path}"; then
    echo "Case failed: expected file ${file_path} to contain '${expected_text}'."
    echo "--- file contents ---"
    cat "${file_path}"
    echo "---------------------"
    exit 1
  fi
}

write_workflow_fixture() {
  local workflow_path="$1"
  cat > "${workflow_path}" <<'YAML'
name: Readiness Fixture

on:
  workflow_dispatch:
    inputs:
      escalation_open_issues_max_pages:
        description: "Max open issue pages scanned before escalation upsert"
        required: false
        default: "10"
        type: string
      escalation_closed_issues_max_pages:
        description: "Max closed issue pages scanned before escalation upsert"
        required: false
        default: "10"
        type: string

jobs:
  readiness-check:
    steps:
      - name: Resolve defaults
        run: |
          if [ -z "${ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT:-}" ]; then
            ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="10"
          fi
          if [ -z "${ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT:-}" ]; then
            ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="10"
          fi
YAML
}

echo "Running readiness page-limit apply fixture regression suite..."

case_one_dir="${TMP_FIXTURE_DIR}/case-one"
mkdir -p "${case_one_dir}"
case_one_auth_workflow="${case_one_dir}/auth.yml"
case_one_cache_workflow="${case_one_dir}/cache.yml"
case_one_summary="${case_one_dir}/summary.json"

write_workflow_fixture "${case_one_auth_workflow}"
write_workflow_fixture "${case_one_cache_workflow}"
cat > "${case_one_summary}" <<'JSON'
{
  "runs_analyzed": 12,
  "recommendation": {
    "escalation_open_issues_max_pages": 14,
    "escalation_closed_issues_max_pages": 9
  }
}
JSON

run_fixture_case \
  0 \
  "applies recommended page limits from summary file to both readiness workflows" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_one_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_one_cache_workflow}" \
  READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE="${case_one_summary}" \
  bash "${APPLY_SCRIPT}"
assert_case_output_contains "Applied recommended readiness page limits."
assert_file_contains "${case_one_auth_workflow}" 'default: "14"'
assert_file_contains "${case_one_auth_workflow}" 'default: "9"'
assert_file_contains "${case_one_auth_workflow}" 'ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="14"'
assert_file_contains "${case_one_auth_workflow}" 'ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="9"'
assert_file_contains "${case_one_cache_workflow}" 'default: "14"'
assert_file_contains "${case_one_cache_workflow}" 'default: "9"'
assert_file_contains "${case_one_cache_workflow}" 'ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="14"'
assert_file_contains "${case_one_cache_workflow}" 'ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="9"'

case_two_dir="${TMP_FIXTURE_DIR}/case-two"
mkdir -p "${case_two_dir}"
case_two_auth_workflow="${case_two_dir}/auth.yml"
case_two_cache_workflow="${case_two_dir}/cache.yml"
case_two_summary="${case_two_dir}/summary.json"

write_workflow_fixture "${case_two_auth_workflow}"
write_workflow_fixture "${case_two_cache_workflow}"
cat > "${case_two_summary}" <<'JSON'
{
  "runs_analyzed": 3,
  "recommendation": {
    "escalation_open_issues_max_pages": 22,
    "escalation_closed_issues_max_pages": 20
  }
}
JSON

run_fixture_case \
  2 \
  "fails confidence guard when run count is below minimum" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_two_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_two_cache_workflow}" \
  READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE="${case_two_summary}" \
  bash "${APPLY_SCRIPT}"
assert_case_output_contains "Error: sample size below minimum confidence threshold"
assert_file_contains "${case_two_auth_workflow}" 'default: "10"'
assert_file_contains "${case_two_auth_workflow}" 'ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="10"'
assert_file_contains "${case_two_cache_workflow}" 'default: "10"'
assert_file_contains "${case_two_cache_workflow}" 'ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="10"'

case_three_dir="${TMP_FIXTURE_DIR}/case-three"
mkdir -p "${case_three_dir}"
case_three_auth_workflow="${case_three_dir}/auth.yml"
case_three_cache_workflow="${case_three_dir}/cache.yml"
case_three_summary="${case_three_dir}/summary.json"

write_workflow_fixture "${case_three_auth_workflow}"
write_workflow_fixture "${case_three_cache_workflow}"
cat > "${case_three_summary}" <<'JSON'
{
  "runs_analyzed": 3,
  "recommendation": {
    "escalation_open_issues_max_pages": 16,
    "escalation_closed_issues_max_pages": 15
  }
}
JSON

run_fixture_case \
  0 \
  "supports low-confidence override in dry-run mode without mutating workflows" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_three_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_three_cache_workflow}" \
  READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE="${case_three_summary}" \
  READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE="true" \
  READINESS_THRESHOLD_APPLY_DRY_RUN="true" \
  bash "${APPLY_SCRIPT}"
assert_case_output_contains "Confidence guard: bypassed"
assert_case_output_contains "Dry run enabled; workflow files were not modified."
assert_file_contains "${case_three_auth_workflow}" 'default: "10"'
assert_file_contains "${case_three_cache_workflow}" 'default: "10"'

case_four_dir="${TMP_FIXTURE_DIR}/case-four"
mkdir -p "${case_four_dir}/metrics"
case_four_auth_workflow="${case_four_dir}/auth.yml"
case_four_cache_workflow="${case_four_dir}/cache.yml"

write_workflow_fixture "${case_four_auth_workflow}"
write_workflow_fixture "${case_four_cache_workflow}"

for index in 1 2 3 4 5 6 7 8 9 10; do
  open_pages=$((index + 1))
  closed_pages="${index}"
  cat > "${case_four_dir}/metrics/run-${index}.json" <<JSON
{
  "kind": "auth_fallback",
  "status": "failure",
  "issue_action": "create",
  "dry_run": false,
  "open_issues_max_pages": 10,
  "open_pages_scanned": ${open_pages},
  "open_match_page": ${index},
  "open_scan_hit_page_limit": false,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": ${closed_pages},
  "closed_match_page": ${closed_pages},
  "closed_scan_hit_page_limit": false,
  "generated_at_utc": "2026-03-10T00:00:${index}Z"
}
JSON
done

run_fixture_case \
  0 \
  "computes recommendation from raw metrics and applies workflow defaults" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_four_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_four_cache_workflow}" \
  bash "${APPLY_SCRIPT}" "${case_four_dir}/metrics"
assert_case_output_contains "Recommended open max pages: 12"
assert_case_output_contains "Recommended closed max pages: 11"
assert_file_contains "${case_four_auth_workflow}" 'default: "12"'
assert_file_contains "${case_four_auth_workflow}" 'default: "11"'
assert_file_contains "${case_four_cache_workflow}" 'default: "12"'
assert_file_contains "${case_four_cache_workflow}" 'default: "11"'

echo ""
echo "Readiness page-limit apply fixture regression suite passed."
