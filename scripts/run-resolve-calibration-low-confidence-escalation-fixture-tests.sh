#!/bin/bash
# Runs fixture-mode regression checks for calibration low-confidence escalation resolution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""
LAST_OUTPUT_FILE=""
TEMP_PATHS=()

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/resolve-calibration-low-confidence-escalation.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Calibration escalation fixture tests failed: could not locate repository root."
  exit 1
fi

RESOLVE_SCRIPT="${REPO_ROOT}/scripts/resolve-calibration-low-confidence-escalation.sh"

for dependency in jq; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Calibration escalation fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${RESOLVE_SCRIPT}" ]; then
  echo "Calibration escalation fixture tests failed: missing script ${RESOLVE_SCRIPT}."
  exit 1
fi

register_temp_path() {
  local temp_path="$1"
  TEMP_PATHS+=("${temp_path}")
}

cleanup_temp_paths() {
  local temp_path=""
  for temp_path in "${TEMP_PATHS[@]-}"; do
    [ -n "${temp_path}" ] && rm -rf "${temp_path}"
  done
}
trap cleanup_temp_paths EXIT

run_fixture_case() {
  local expected_exit="$1"
  local label="$2"
  shift 2

  local case_dir=""
  local case_output_file=""
  if ! case_dir="$(mktemp -d)"; then
    echo "Calibration escalation fixture tests failed: unable to allocate temp directory."
    exit 1
  fi
  register_temp_path "${case_dir}"
  case_output_file="${case_dir}/github-output.txt"
  LAST_OUTPUT_FILE="${case_output_file}"

  echo ""
  echo "Case: ${label}"

  set +e
  CASE_OUTPUT="$(env GITHUB_OUTPUT="${case_output_file}" "$@" 2>&1)"
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

read_output_value() {
  local key="$1"
  local value=""
  value="$(awk -F= -v lookup_key="${key}" '$1 == lookup_key { print substr($0, length($1) + 2); found = 1 } END { if (!found) exit 1 }' "${LAST_OUTPUT_FILE}")" || {
    echo "Case failed: missing output key '${key}' in ${LAST_OUTPUT_FILE}."
    [ -f "${LAST_OUTPUT_FILE}" ] && cat "${LAST_OUTPUT_FILE}"
    exit 1
  }
  printf '%s' "${value}"
}

assert_output_equals() {
  local key="$1"
  local expected="$2"
  local actual=""
  actual="$(read_output_value "${key}")"
  if [ "${actual}" != "${expected}" ]; then
    echo "Case failed: expected output '${key}' to be '${expected}', got '${actual}'."
    [ -f "${LAST_OUTPUT_FILE}" ] && cat "${LAST_OUTPUT_FILE}"
    exit 1
  fi
}

echo "Running calibration low-confidence escalation fixture regression suite..."

run_fixture_case \
  0 \
  "warmup schedule low-confidence reaches threshold and escalates" \
  env CALIBRATION_ESCALATION_KIND="warmup_threshold" \
  CALIBRATION_ESCALATION_EVENT_NAME="schedule" \
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED="true" \
  CALIBRATION_LOW_CONFIDENCE_REASON="sample size below minimum confidence threshold (3 < 10)." \
  CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD="3" \
  CALIBRATION_ESCALATION_HISTORY_JSON='[true,true,false,true]' \
  bash "${RESOLVE_SCRIPT}"
assert_output_equals "escalation_kind" "warmup_threshold_calibration"
assert_output_equals "history_source" "fixture"
assert_output_equals "history_runs_checked" "3"
assert_output_equals "previous_low_confidence_streak" "2"
assert_output_equals "current_low_confidence_streak" "3"
assert_output_equals "escalation_status" "failure"
assert_output_equals "escalation_needed" "true"

run_fixture_case \
  0 \
  "readiness schedule low-confidence remains below threshold" \
  env CALIBRATION_ESCALATION_KIND="readiness_page_limit" \
  CALIBRATION_ESCALATION_EVENT_NAME="schedule" \
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED="true" \
  CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD="4" \
  CALIBRATION_ESCALATION_HISTORY_JSON='[{"low_confidence_guard_triggered":true},{"low_confidence_guard_triggered":false}]' \
  bash "${RESOLVE_SCRIPT}"
assert_output_equals "escalation_kind" "readiness_page_limit_calibration"
assert_output_equals "history_source" "fixture"
assert_output_equals "history_runs_checked" "2"
assert_output_equals "previous_low_confidence_streak" "1"
assert_output_equals "current_low_confidence_streak" "2"
assert_output_equals "escalation_status" "below_threshold"
assert_output_equals "escalation_needed" "false"

run_fixture_case \
  0 \
  "schedule run with no low-confidence marks recovery" \
  env CALIBRATION_ESCALATION_KIND="warmup_threshold" \
  CALIBRATION_ESCALATION_EVENT_NAME="schedule" \
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED="false" \
  bash "${RESOLVE_SCRIPT}"
assert_output_equals "history_source" "none"
assert_output_equals "history_runs_checked" "0"
assert_output_equals "previous_low_confidence_streak" "0"
assert_output_equals "current_low_confidence_streak" "0"
assert_output_equals "escalation_status" "recovered"
assert_output_equals "escalation_needed" "true"

run_fixture_case \
  0 \
  "non-schedule event skips escalation by default" \
  env CALIBRATION_ESCALATION_KIND="warmup_threshold" \
  CALIBRATION_ESCALATION_EVENT_NAME="workflow_dispatch" \
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED="true" \
  CALIBRATION_ESCALATION_HISTORY_JSON='[true,true,true]' \
  bash "${RESOLVE_SCRIPT}"
assert_output_equals "event_eligible" "false"
assert_output_equals "history_source" "none"
assert_output_equals "previous_low_confidence_streak" "0"
assert_output_equals "current_low_confidence_streak" "1"
assert_output_equals "escalation_status" "skip_event"
assert_output_equals "escalation_needed" "false"

run_fixture_case \
  0 \
  "non-schedule event can be explicitly enabled" \
  env CALIBRATION_ESCALATION_KIND="readiness_page_limit" \
  CALIBRATION_ESCALATION_EVENT_NAME="workflow_dispatch" \
  CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE="true" \
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED="true" \
  CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD="2" \
  CALIBRATION_ESCALATION_HISTORY_JSON='[true,false]' \
  bash "${RESOLVE_SCRIPT}"
assert_output_equals "event_eligible" "true"
assert_output_equals "history_source" "fixture"
assert_output_equals "previous_low_confidence_streak" "1"
assert_output_equals "current_low_confidence_streak" "2"
assert_output_equals "escalation_status" "failure"
assert_output_equals "escalation_needed" "true"

run_fixture_case \
  1 \
  "fixture history payload must be a JSON array" \
  env CALIBRATION_ESCALATION_KIND="warmup_threshold" \
  CALIBRATION_ESCALATION_EVENT_NAME="schedule" \
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED="true" \
  CALIBRATION_ESCALATION_HISTORY_JSON='{"not":"an array"}' \
  bash "${RESOLVE_SCRIPT}"
assert_case_output_contains "history payload must be a JSON array"

echo ""
echo "Calibration low-confidence escalation fixture regression suite passed."
