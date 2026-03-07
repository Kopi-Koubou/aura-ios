#!/bin/bash
# Runs fixture-mode regression checks for warm-cache metrics trend summaries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/summarize-warm-cache-metrics.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Warm-cache metrics summary fixture tests failed: could not locate repository root."
  exit 1
fi

SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-warm-cache-metrics.sh"

for dependency in jq mktemp grep; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Warm-cache metrics summary fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${SUMMARY_SCRIPT}" ]; then
  echo "Warm-cache metrics summary fixture tests failed: missing script ${SUMMARY_SCRIPT}."
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

echo "Running warm-cache metrics summary fixture regression suite..."

case_one_dir="${TMP_FIXTURE_DIR}/case-one"
mkdir -p "${case_one_dir}"

cat > "${case_one_dir}/run-1.json" <<'JSON'
{
  "target_date": "2026-03-01",
  "retry_rate_percent": 12,
  "outcome": "success",
  "exit_code": 0,
  "generated_at_utc": "2026-03-01T00:05:10Z"
}
JSON

cat > "${case_one_dir}/run-2.json" <<'JSON'
{
  "target_date": "2026-03-02",
  "retry_rate_percent": 20,
  "outcome": "success",
  "exit_code": 0,
  "generated_at_utc": "2026-03-02T00:05:11Z"
}
JSON

cat > "${case_one_dir}/run-3.json" <<'JSON'
{
  "target_date": "2026-03-03",
  "retry_rate_percent": 5,
  "outcome": "failed_requests",
  "exit_code": 1,
  "generated_at_utc": "2026-03-03T00:05:12Z"
}
JSON

cat > "${case_one_dir}/run-4.json" <<'JSON'
{
  "target_date": "2026-03-04",
  "retry_rate_percent": 35,
  "outcome": "retry_rate_exceeded",
  "exit_code": 2,
  "generated_at_utc": "2026-03-04T00:05:13Z"
}
JSON

cat > "${case_one_dir}/not-metrics.json" <<'JSON'
{
  "message": "not a warm cache metrics file"
}
JSON

case_one_summary="${case_one_dir}/summary.json"
run_fixture_case \
  0 \
  "summarizer computes p50/p95/max and emits JSON summary with recommendation" \
  env WARMUP_METRICS_SUMMARY_FILE="${case_one_summary}" \
  bash "${SUMMARY_SCRIPT}" "${case_one_dir}"
assert_case_output_contains "Metrics files analyzed:  4"
assert_case_output_contains "Non-metrics skipped:     1"
assert_case_output_contains "Retry rate p50/p95/max:  12% / 35% / 35%"
assert_case_output_contains "set WARMUP_MAX_RETRY_RATE_PERCENT=40"
assert_json_field_equals "${case_one_summary}" '.runs_analyzed' '4'
assert_json_field_equals "${case_one_summary}" '.retry_rate_percentiles.p95' '35'
assert_json_field_equals "${case_one_summary}" '.recommendation.max_retry_rate_percent' '40'

case_two_dir="${TMP_FIXTURE_DIR}/case-two"
mkdir -p "${case_two_dir}"

cat > "${case_two_dir}/run-1.json" <<'JSON'
{
  "target_date": "2026-03-10",
  "retry_rate_percent": 4,
  "outcome": "success",
  "exit_code": 0,
  "generated_at_utc": "2026-03-10T00:05:10Z"
}
JSON

cat > "${case_two_dir}/run-2.json" <<'JSON'
{
  "target_date": "2026-03-11",
  "retry_rate_percent": 5,
  "outcome": "success",
  "exit_code": 0,
  "generated_at_utc": "2026-03-11T00:05:10Z"
}
JSON

run_fixture_case \
  0 \
  "recommendation floor is applied when p95 plus buffer is below minimum threshold" \
  env RETRY_RATE_BUFFER_PERCENT="2" MIN_RECOMMENDED_RETRY_RATE_PERCENT="30" \
  bash "${SUMMARY_SCRIPT}" "${case_two_dir}"
assert_case_output_contains "set WARMUP_MAX_RETRY_RATE_PERCENT=30"

run_fixture_case \
  1 \
  "fails fast when no valid metrics payloads are available" \
  bash "${SUMMARY_SCRIPT}" "${TMP_FIXTURE_DIR}/does-not-exist"
assert_case_output_contains "Error: no valid warm-cache metrics files found."

echo ""
echo "Warm-cache metrics summary fixture regression suite passed."
