#!/bin/bash
# Runs fixture-mode regression checks for automated readiness page-limit calibration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/propose-readiness-page-limit-update.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Readiness page-limit calibration fixture tests failed: could not locate repository root."
  exit 1
fi

CALIBRATE_SCRIPT="${REPO_ROOT}/scripts/propose-readiness-page-limit-update.sh"

for dependency in jq mktemp find grep sed zip unzip cp; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Readiness page-limit calibration fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${CALIBRATE_SCRIPT}" ]; then
  echo "Readiness page-limit calibration fixture tests failed: missing script ${CALIBRATE_SCRIPT}."
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

assert_json_expression() {
  local file_path="$1"
  local expression="$2"
  if ! jq -e "${expression}" "${file_path}" >/dev/null 2>&1; then
    echo "Case failed: expected JSON expression '${expression}' to pass for ${file_path}."
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

write_metric_payload() {
  local output_file="$1"
  local kind="$2"
  local status="$3"
  local issue_action="$4"
  local dry_run="$5"
  local open_pages_scanned="$6"
  local open_match_page="$7"
  local open_scan_hit_page_limit="$8"
  local closed_pages_scanned="$9"
  local closed_match_page="${10}"
  local closed_scan_hit_page_limit="${11}"
  local generated_at_utc="${12}"

  cat > "${output_file}" <<JSON
{
  "kind": "${kind}",
  "status": "${status}",
  "issue_action": "${issue_action}",
  "dry_run": ${dry_run},
  "open_issues_max_pages": 10,
  "open_pages_scanned": ${open_pages_scanned},
  "open_match_page": ${open_match_page},
  "open_scan_hit_page_limit": ${open_scan_hit_page_limit},
  "closed_issues_max_pages": 10,
  "closed_pages_scanned": ${closed_pages_scanned},
  "closed_match_page": ${closed_match_page},
  "closed_scan_hit_page_limit": ${closed_scan_hit_page_limit},
  "generated_at_utc": "${generated_at_utc}"
}
JSON
}

write_mixed_metrics_fixture() {
  local metrics_dir="$1"
  local count="$2"
  local index
  local second
  local kind
  local issue_action

  mkdir -p "${metrics_dir}"

  for index in $(seq 1 "${count}"); do
    printf -v second "%02d" "${index}"
    if [ $((index % 2)) -eq 0 ]; then
      kind="cache_degradation"
      issue_action="comment"
    else
      kind="auth_fallback"
      issue_action="create"
    fi

    write_metric_payload \
      "${metrics_dir}/run-${index}.json" \
      "${kind}" \
      "failure" \
      "${issue_action}" \
      "false" \
      "$((index + 1))" \
      "${index}" \
      "false" \
      "${index}" \
      "${index}" \
      "false" \
      "2026-03-10T00:00:${second}Z"
  done
}

write_kind_metrics_fixture() {
  local metrics_dir="$1"
  local kind="$2"
  local start="$3"
  local end="$4"
  local index
  local second
  local issue_action

  mkdir -p "${metrics_dir}"

  if [ "${kind}" = "auth_fallback" ]; then
    issue_action="create"
  else
    issue_action="comment"
  fi

  for index in $(seq "${start}" "${end}"); do
    printf -v second "%02d" "${index}"
    write_metric_payload \
      "${metrics_dir}/run-${index}.json" \
      "${kind}" \
      "failure" \
      "${issue_action}" \
      "false" \
      "$((index + 1))" \
      "${index}" \
      "false" \
      "${index}" \
      "${index}" \
      "false" \
      "2026-03-10T00:00:${second}Z"
  done
}

echo "Running readiness page-limit calibration fixture regression suite..."

case_one_dir="${TMP_FIXTURE_DIR}/case-one"
mkdir -p "${case_one_dir}"
case_one_auth_workflow="${case_one_dir}/auth.yml"
case_one_cache_workflow="${case_one_dir}/cache.yml"
case_one_metrics="${case_one_dir}/metrics"
case_one_output="${case_one_dir}/output"

write_workflow_fixture "${case_one_auth_workflow}"
write_workflow_fixture "${case_one_cache_workflow}"
write_mixed_metrics_fixture "${case_one_metrics}" 10

run_fixture_case \
  0 \
  "detects readiness page-limit drift from local metrics without mutating workflows when apply=false" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_one_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_one_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_one_metrics}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_one_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Drift detected: recommended page limits differ from workflow defaults."
assert_case_output_contains "Drift detected: true"
assert_file_contains "${case_one_auth_workflow}" 'default: "10"'
assert_file_contains "${case_one_auth_workflow}" 'ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="10"'
assert_file_contains "${case_one_cache_workflow}" 'default: "10"'
assert_file_contains "${case_one_cache_workflow}" 'ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="10"'

case_two_dir="${TMP_FIXTURE_DIR}/case-two"
mkdir -p "${case_two_dir}"
case_two_auth_workflow="${case_two_dir}/auth.yml"
case_two_cache_workflow="${case_two_dir}/cache.yml"
case_two_output="${case_two_dir}/output"

write_workflow_fixture "${case_two_auth_workflow}"
write_workflow_fixture "${case_two_cache_workflow}"

run_fixture_case \
  0 \
  "applies readiness page-limit update when drift is detected and apply=true" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_two_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_two_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_one_metrics}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_two_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Applied recommended readiness page limits."
assert_case_output_contains "Changes applied: true"
assert_file_contains "${case_two_auth_workflow}" 'default: "12"'
assert_file_contains "${case_two_auth_workflow}" 'default: "11"'
assert_file_contains "${case_two_auth_workflow}" 'ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="12"'
assert_file_contains "${case_two_auth_workflow}" 'ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="11"'
assert_file_contains "${case_two_cache_workflow}" 'default: "12"'
assert_file_contains "${case_two_cache_workflow}" 'default: "11"'
assert_file_contains "${case_two_cache_workflow}" 'ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="12"'
assert_file_contains "${case_two_cache_workflow}" 'ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="11"'

case_three_dir="${TMP_FIXTURE_DIR}/case-three"
mkdir -p "${case_three_dir}"
case_three_auth_workflow="${case_three_dir}/auth.yml"
case_three_cache_workflow="${case_three_dir}/cache.yml"
case_three_metrics="${case_three_dir}/metrics"
case_three_output="${case_three_dir}/output"

write_workflow_fixture "${case_three_auth_workflow}"
write_workflow_fixture "${case_three_cache_workflow}"
write_mixed_metrics_fixture "${case_three_metrics}" 3

run_fixture_case \
  0 \
  "returns success on low-confidence recommendation when fail-on-low-confidence is false" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_three_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_three_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_three_metrics}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_three_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  READINESS_THRESHOLD_MIN_RUNS="10" \
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation detected; skipping apply without failing."
assert_file_contains "${case_three_auth_workflow}" 'default: "10"'
assert_file_contains "${case_three_cache_workflow}" 'default: "10"'
assert_json_expression "${case_three_output}/readiness-page-limit-calibration-result.json" '.low_confidence_guard_triggered == true and .low_confidence_reason == "sample size below minimum confidence threshold (3 < 10)."'

run_fixture_case \
  2 \
  "returns exit 2 when low-confidence recommendation is configured as hard failure" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_three_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_three_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_three_metrics}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_three_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  READINESS_THRESHOLD_MIN_RUNS="10" \
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation triggered hard failure."

case_no_metrics_dir="${TMP_FIXTURE_DIR}/case-no-metrics"
mkdir -p "${case_no_metrics_dir}"
case_no_metrics_auth_workflow="${case_no_metrics_dir}/auth.yml"
case_no_metrics_cache_workflow="${case_no_metrics_dir}/cache.yml"
case_no_metrics_metrics="${case_no_metrics_dir}/metrics"
case_no_metrics_output="${case_no_metrics_dir}/output"

write_workflow_fixture "${case_no_metrics_auth_workflow}"
write_workflow_fixture "${case_no_metrics_cache_workflow}"
mkdir -p "${case_no_metrics_metrics}"

run_fixture_case \
  0 \
  "returns success when no readiness metrics are available and fail-on-low-confidence is false" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_no_metrics_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_no_metrics_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_no_metrics_metrics}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_no_metrics_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "No readiness metrics were collected; treating calibration as low-confidence."
assert_case_output_contains "Low-confidence recommendation detected; skipping apply without failing."
assert_file_contains "${case_no_metrics_auth_workflow}" 'default: "10"'
assert_file_contains "${case_no_metrics_cache_workflow}" 'default: "10"'
assert_json_expression "${case_no_metrics_output}/readiness-page-limit-summary.json" '.non_metrics_skipped == 0 and (.source_files | length == 0) and (.metrics_window.start_utc == "(unavailable)") and (.metrics_window.end_utc == "(unavailable)")'
assert_json_expression "${case_no_metrics_output}/readiness-page-limit-calibration-result.json" '.low_confidence_reason == "No readiness metrics were collected; treating calibration as low-confidence."'

run_fixture_case \
  2 \
  "returns exit 2 when no readiness metrics are available and fail-on-low-confidence is true" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_no_metrics_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_no_metrics_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_no_metrics_metrics}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_no_metrics_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation triggered hard failure."

case_invalid_metrics_dir="${TMP_FIXTURE_DIR}/case-invalid-metrics"
mkdir -p "${case_invalid_metrics_dir}"
case_invalid_metrics_auth_workflow="${case_invalid_metrics_dir}/auth.yml"
case_invalid_metrics_cache_workflow="${case_invalid_metrics_dir}/cache.yml"
case_invalid_metrics_payloads="${case_invalid_metrics_dir}/metrics"
case_invalid_metrics_output="${case_invalid_metrics_dir}/output"

write_workflow_fixture "${case_invalid_metrics_auth_workflow}"
write_workflow_fixture "${case_invalid_metrics_cache_workflow}"
mkdir -p "${case_invalid_metrics_payloads}"

cat > "${case_invalid_metrics_payloads}/not-metrics.json" <<'JSON'
{
  "message": "not a readiness metrics payload"
}
JSON

run_fixture_case \
  0 \
  "returns success when collected JSON files are non-metrics and fail-on-low-confidence is false" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_invalid_metrics_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_invalid_metrics_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_invalid_metrics_payloads}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_invalid_metrics_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "No valid readiness metrics payloads were found in collected JSON files; treating calibration as low-confidence."
assert_case_output_contains "Low-confidence recommendation detected; skipping apply without failing."
assert_file_contains "${case_invalid_metrics_auth_workflow}" 'default: "10"'
assert_file_contains "${case_invalid_metrics_cache_workflow}" 'default: "10"'
assert_json_expression "${case_invalid_metrics_output}/readiness-page-limit-summary.json" '.non_metrics_skipped == 1 and (.source_files | length == 1) and (.metrics_window.start_utc == "(unavailable)") and (.metrics_window.end_utc == "(unavailable)") and (.note == "Collected JSON files did not include valid readiness metrics payloads.")'
assert_json_expression "${case_invalid_metrics_output}/readiness-page-limit-calibration-result.json" '.low_confidence_reason == "No valid readiness metrics payloads were found in collected JSON files; treating calibration as low-confidence."'

run_fixture_case \
  2 \
  "returns exit 2 when collected JSON files are non-metrics and fail-on-low-confidence is true" \
  env READINESS_AUTH_WORKFLOW_FILE="${case_invalid_metrics_auth_workflow}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_invalid_metrics_cache_workflow}" \
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${case_invalid_metrics_payloads}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_invalid_metrics_output}" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="true" \
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation triggered hard failure."

case_four_dir="${TMP_FIXTURE_DIR}/case-four"
mkdir -p "${case_four_dir}/mock-bin" "${case_four_dir}/auth-artifact" "${case_four_dir}/cache-artifact" "${case_four_dir}/output"
case_four_workflow_auth="${case_four_dir}/auth.yml"
case_four_workflow_cache="${case_four_dir}/cache.yml"
case_four_auth_zip="${case_four_dir}/auth-artifact-321.zip"
case_four_cache_zip="${case_four_dir}/cache-artifact-654.zip"
case_four_mock_gh="${case_four_dir}/mock-bin/gh"

write_workflow_fixture "${case_four_workflow_auth}"
write_workflow_fixture "${case_four_workflow_cache}"
write_kind_metrics_fixture "${case_four_dir}/auth-artifact" "auth_fallback" 1 5
write_kind_metrics_fixture "${case_four_dir}/cache-artifact" "cache_degradation" 6 10

(
  cd "${case_four_dir}/auth-artifact"
  zip -q -r "${case_four_auth_zip}" .
)

(
  cd "${case_four_dir}/cache-artifact"
  zip -q -r "${case_four_cache_zip}" .
)

cat > "${case_four_mock_gh}" <<'SH'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" != "api" ]; then
  echo "mock gh only supports 'api'." >&2
  exit 1
fi

endpoint="${2:-}"
case "${endpoint}" in
  repos/example/aura/actions/artifacts?name=auth-fallback-readiness-escalation-metrics\&per_page=100)
    cat <<'JSON'
{
  "total_count": 1,
  "artifacts": [
    {
      "id": 321,
      "name": "auth-fallback-readiness-escalation-metrics",
      "expired": false,
      "created_at": "2026-03-10T00:05:10Z"
    }
  ]
}
JSON
    ;;
  repos/example/aura/actions/artifacts?name=cache-degradation-readiness-escalation-metrics\&per_page=100)
    cat <<'JSON'
{
  "total_count": 1,
  "artifacts": [
    {
      "id": 654,
      "name": "cache-degradation-readiness-escalation-metrics",
      "expired": false,
      "created_at": "2026-03-10T00:06:10Z"
    }
  ]
}
JSON
    ;;
  repos/example/aura/actions/artifacts/321/zip)
    cat "${GH_FIXTURE_AUTH_ZIP_FILE}"
    ;;
  repos/example/aura/actions/artifacts/654/zip)
    cat "${GH_FIXTURE_CACHE_ZIP_FILE}"
    ;;
  *)
    echo "unexpected gh endpoint: ${endpoint}" >&2
    exit 1
    ;;
esac
SH
chmod +x "${case_four_mock_gh}"

run_fixture_case \
  0 \
  "downloads readiness metrics artifacts via gh API and runs drift detection" \
  env PATH="${case_four_dir}/mock-bin:${PATH}" \
  GH_TOKEN="fixture-token" \
  READINESS_PAGE_LIMIT_GITHUB_REPOSITORY="example/aura" \
  GH_FIXTURE_AUTH_ZIP_FILE="${case_four_auth_zip}" \
  GH_FIXTURE_CACHE_ZIP_FILE="${case_four_cache_zip}" \
  READINESS_AUTH_WORKFLOW_FILE="${case_four_workflow_auth}" \
  READINESS_CACHE_WORKFLOW_FILE="${case_four_workflow_cache}" \
  READINESS_PAGE_LIMIT_OUTPUT_DIR="${case_four_dir}/output" \
  READINESS_PAGE_LIMIT_APPLY_CHANGES="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Downloaded auth metrics artifact 321."
assert_case_output_contains "Downloaded cache metrics artifact 654."
assert_case_output_contains "Collected 10 metric candidate file(s) for readiness calibration."
assert_case_output_contains "Drift detected: true"
assert_file_contains "${case_four_workflow_auth}" 'default: "10"'
assert_file_contains "${case_four_workflow_cache}" 'default: "10"'

echo ""
echo "Readiness page-limit calibration fixture regression suite passed."
