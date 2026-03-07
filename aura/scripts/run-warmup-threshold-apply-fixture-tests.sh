#!/bin/bash
# Runs fixture-mode regression checks for threshold application from warm-cache metrics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/apply-warmup-threshold-from-metrics.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Warmup threshold apply fixture tests failed: could not locate repository root."
  exit 1
fi

APPLY_SCRIPT="${REPO_ROOT}/scripts/apply-warmup-threshold-from-metrics.sh"

for dependency in jq mktemp grep sed; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Warmup threshold apply fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${APPLY_SCRIPT}" ]; then
  echo "Warmup threshold apply fixture tests failed: missing script ${APPLY_SCRIPT}."
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
name: Warm Generated Cache

on:
  workflow_dispatch:
    inputs:
      warmup_max_retry_rate_percent:
        description: "Fail run when retried-request rate exceeds this percent"
        required: false
        default: "25"
        type: string

jobs:
  warm-cache:
    steps:
      - name: Resolve defaults
        run: |
          if [ -z "${WARMUP_MAX_RETRY_RATE_PERCENT:-}" ]; then
            WARMUP_MAX_RETRY_RATE_PERCENT="25"
          fi
YAML
}

echo "Running warmup-threshold apply fixture regression suite..."

case_one_dir="${TMP_FIXTURE_DIR}/case-one"
mkdir -p "${case_one_dir}"
case_one_workflow="${case_one_dir}/warm-generated-cache.yml"
case_one_summary="${case_one_dir}/summary.json"

write_workflow_fixture "${case_one_workflow}"
cat > "${case_one_summary}" <<'JSON'
{
  "runs_analyzed": 12,
  "retry_rate_percentiles": {
    "p95": 32
  },
  "recommendation": {
    "max_retry_rate_percent": 37
  }
}
JSON

run_fixture_case \
  0 \
  "applies recommended threshold from summary file" \
  env WARMUP_WORKFLOW_FILE="${case_one_workflow}" WARMUP_METRICS_SUMMARY_INPUT_FILE="${case_one_summary}" \
  bash "${APPLY_SCRIPT}"
assert_case_output_contains "Applied recommended threshold to workflow defaults."
assert_file_contains "${case_one_workflow}" 'default: "37"'
assert_file_contains "${case_one_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="37"'

case_two_dir="${TMP_FIXTURE_DIR}/case-two"
mkdir -p "${case_two_dir}"
case_two_workflow="${case_two_dir}/warm-generated-cache.yml"
case_two_summary="${case_two_dir}/summary.json"

write_workflow_fixture "${case_two_workflow}"
cat > "${case_two_summary}" <<'JSON'
{
  "runs_analyzed": 3,
  "retry_rate_percentiles": {
    "p95": 18
  },
  "recommendation": {
    "max_retry_rate_percent": 24
  }
}
JSON

run_fixture_case \
  2 \
  "fails confidence guard when run count is below minimum" \
  env WARMUP_WORKFLOW_FILE="${case_two_workflow}" WARMUP_METRICS_SUMMARY_INPUT_FILE="${case_two_summary}" \
  bash "${APPLY_SCRIPT}"
assert_case_output_contains "Error: sample size below minimum confidence threshold"
assert_file_contains "${case_two_workflow}" 'default: "25"'
assert_file_contains "${case_two_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'

case_three_dir="${TMP_FIXTURE_DIR}/case-three"
mkdir -p "${case_three_dir}"
case_three_workflow="${case_three_dir}/warm-generated-cache.yml"

write_workflow_fixture "${case_three_workflow}"

run_fixture_case \
  0 \
  "supports low-confidence override in dry-run mode without mutating workflow" \
  env WARMUP_WORKFLOW_FILE="${case_three_workflow}" WARMUP_METRICS_SUMMARY_INPUT_FILE="${case_two_summary}" \
  WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE="true" WARMUP_THRESHOLD_APPLY_DRY_RUN="true" \
  bash "${APPLY_SCRIPT}"
assert_case_output_contains "Confidence guard: bypassed"
assert_case_output_contains "Dry run enabled; workflow file was not modified."
assert_file_contains "${case_three_workflow}" 'default: "25"'
assert_file_contains "${case_three_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'

case_four_dir="${TMP_FIXTURE_DIR}/case-four"
mkdir -p "${case_four_dir}/metrics"
case_four_workflow="${case_four_dir}/warm-generated-cache.yml"

write_workflow_fixture "${case_four_workflow}"

for retry_rate in 5 6 7 8 9 10 11 12 13 14; do
  cat > "${case_four_dir}/metrics/run-${retry_rate}.json" <<JSON
{
  "target_date": "2026-03-01",
  "retry_rate_percent": ${retry_rate},
  "outcome": "success",
  "exit_code": 0,
  "generated_at_utc": "2026-03-01T00:05:10Z"
}
JSON
done

run_fixture_case \
  0 \
  "computes recommendation from raw metrics and applies workflow defaults" \
  env WARMUP_WORKFLOW_FILE="${case_four_workflow}" \
  bash "${APPLY_SCRIPT}" "${case_four_dir}/metrics"
assert_case_output_contains "Recommended max retry rate: 19%"
assert_file_contains "${case_four_workflow}" 'default: "19"'
assert_file_contains "${case_four_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="19"'

echo ""
echo "Warmup-threshold apply fixture regression suite passed."

