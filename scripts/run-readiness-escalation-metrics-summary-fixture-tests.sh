#!/bin/bash
# Runs fixture-mode regression checks for readiness escalation metrics summaries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/summarize-readiness-escalation-metrics.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Readiness escalation metrics summary fixture tests failed: could not locate repository root."
  exit 1
fi

SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-readiness-escalation-metrics.sh"

for dependency in jq mktemp grep; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Readiness escalation metrics summary fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${SUMMARY_SCRIPT}" ]; then
  echo "Readiness escalation metrics summary fixture tests failed: missing script ${SUMMARY_SCRIPT}."
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

assert_json_field_equals() {
  local json_file="$1"
  local jq_expr="$2"
  local expected_value="$3"
  local actual_value

  actual_value="$(jq -r "${jq_expr}" "${json_file}")"
  if [ "${actual_value}" != "${expected_value}" ]; then
    echo "Case failed: expected ${jq_expr} == ${expected_value}, got ${actual_value}."
    echo "JSON file: ${json_file}"
    cat "${json_file}"
    exit 1
  fi
}

echo "Running readiness escalation metrics summary fixture regression suite..."

case_one_dir="${TMP_FIXTURE_DIR}/case-one"
mkdir -p "${case_one_dir}"

cat > "${case_one_dir}/run-1.json" <<'JSON'
{
  "kind": "auth_fallback",
  "status": "failure",
  "issue_action": "create",
  "dry_run": false,
  "open_issues_max_pages": 10,
  "open_pages_scanned": 2,
  "open_match_page": 1,
  "open_scan_hit_page_limit": false,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": 3,
  "closed_match_page": 1,
  "closed_scan_hit_page_limit": false,
  "generated_at_utc": "2026-03-01T00:00:01Z"
}
JSON

cat > "${case_one_dir}/run-2.json" <<'JSON'
{
  "kind": "cache_degradation",
  "status": "failure",
  "issue_action": "comment",
  "dry_run": false,
  "open_issues_max_pages": 10,
  "open_pages_scanned": 4,
  "open_match_page": 3,
  "open_scan_hit_page_limit": false,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": 2,
  "closed_match_page": 2,
  "closed_scan_hit_page_limit": false,
  "generated_at_utc": "2026-03-02T00:00:02Z"
}
JSON

cat > "${case_one_dir}/run-3.json" <<'JSON'
{
  "kind": "auth_fallback",
  "status": "recovered",
  "issue_action": "close",
  "dry_run": true,
  "open_issues_max_pages": 10,
  "open_pages_scanned": 8,
  "open_match_page": 7,
  "open_scan_hit_page_limit": true,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": 6,
  "closed_match_page": 0,
  "closed_scan_hit_page_limit": false,
  "generated_at_utc": "2026-03-03T00:00:03Z"
}
JSON

cat > "${case_one_dir}/run-4.json" <<'JSON'
{
  "kind": "cache_degradation",
  "status": "failure",
  "issue_action": "create",
  "dry_run": false,
  "open_issues_max_pages": 10,
  "open_pages_scanned": 1,
  "open_match_page": 0,
  "open_scan_hit_page_limit": false,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": 10,
  "closed_match_page": 9,
  "closed_scan_hit_page_limit": true,
  "generated_at_utc": "2026-03-04T00:00:04Z"
}
JSON

cat > "${case_one_dir}/not-metrics.json" <<'JSON'
{
  "message": "not a readiness metrics payload"
}
JSON

case_one_summary="${case_one_dir}/summary.json"
run_fixture_case \
  0 \
  "summarizer computes page-depth recommendations and emits JSON summary" \
  env READINESS_ESCALATION_METRICS_SUMMARY_FILE="${case_one_summary}" \
  bash "${SUMMARY_SCRIPT}" "${case_one_dir}"
assert_case_output_contains "Metrics files analyzed:   4"
assert_case_output_contains "Non-metrics skipped:      1"
assert_case_output_contains "set escalation_open_issues_max_pages=9"
assert_case_output_contains "set escalation_closed_issues_max_pages=11"
assert_json_field_equals "${case_one_summary}" '.runs_analyzed' '4'
assert_json_field_equals "${case_one_summary}" '.recommendation.escalation_open_issues_max_pages' '9'
assert_json_field_equals "${case_one_summary}" '.recommendation.escalation_closed_issues_max_pages' '11'
assert_json_field_equals "${case_one_summary}" '.open_pages.limit_hit_count' '1'
assert_json_field_equals "${case_one_summary}" '.closed_pages.limit_hit_count' '1'
assert_json_field_equals "${case_one_summary}" '.kind_counts.auth_fallback' '2'
assert_json_field_equals "${case_one_summary}" '.mode_counts.dry_run' '1'

case_two_dir="${TMP_FIXTURE_DIR}/case-two"
mkdir -p "${case_two_dir}"

cat > "${case_two_dir}/run-1.json" <<'JSON'
{
  "kind": "auth_fallback",
  "status": "failure",
  "issue_action": "create",
  "dry_run": false,
  "open_issues_max_pages": 10,
  "open_pages_scanned": 1,
  "open_match_page": 1,
  "open_scan_hit_page_limit": false,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": 1,
  "closed_match_page": 1,
  "closed_scan_hit_page_limit": false,
  "generated_at_utc": "2026-03-05T00:00:01Z"
}
JSON

cat > "${case_two_dir}/run-2.json" <<'JSON'
{
  "kind": "cache_degradation",
  "status": "failure",
  "issue_action": "comment",
  "dry_run": false,
  "open_issues_max_pages": 10,
  "open_pages_scanned": 2,
  "open_match_page": 2,
  "open_scan_hit_page_limit": false,
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": 2,
  "closed_match_page": 2,
  "closed_scan_hit_page_limit": false,
  "generated_at_utc": "2026-03-06T00:00:02Z"
}
JSON

run_fixture_case \
  0 \
  "minimum recommendation floors are applied when observed depth is low" \
  env READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES="0" \
  MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES="15" \
  MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES="12" \
  bash "${SUMMARY_SCRIPT}" "${case_two_dir}"
assert_case_output_contains "set escalation_open_issues_max_pages=15"
assert_case_output_contains "set escalation_closed_issues_max_pages=12"

run_fixture_case \
  1 \
  "fails fast when no valid readiness escalation metrics payloads are available" \
  bash "${SUMMARY_SCRIPT}" "${TMP_FIXTURE_DIR}/does-not-exist"
assert_case_output_contains "Error: no valid readiness escalation metrics files found."

echo ""
echo "Readiness escalation metrics summary fixture regression suite passed."
