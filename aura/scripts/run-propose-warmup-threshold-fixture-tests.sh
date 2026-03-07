#!/bin/bash
# Runs fixture-mode regression checks for automated warmup threshold calibration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/propose-warmup-threshold-update.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Warmup threshold calibration fixture tests failed: could not locate repository root."
  exit 1
fi

CALIBRATE_SCRIPT="${REPO_ROOT}/scripts/propose-warmup-threshold-update.sh"

for dependency in jq mktemp find grep sed zip unzip cp; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Warmup threshold calibration fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${CALIBRATE_SCRIPT}" ]; then
  echo "Warmup threshold calibration fixture tests failed: missing script ${CALIBRATE_SCRIPT}."
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

write_metrics_fixture() {
  local metrics_dir="$1"
  shift
  local index=0
  local retry_rate

  mkdir -p "${metrics_dir}"
  for retry_rate in "$@"; do
    cat > "${metrics_dir}/run-${index}.json" <<JSON
{
  "target_date": "2026-03-05",
  "retry_rate_percent": ${retry_rate},
  "outcome": "success",
  "exit_code": 0,
  "generated_at_utc": "2026-03-05T00:05:10Z"
}
JSON
    index=$((index + 1))
  done
}

echo "Running warmup threshold calibration fixture regression suite..."

case_one_dir="${TMP_FIXTURE_DIR}/case-one"
mkdir -p "${case_one_dir}"
case_one_workflow="${case_one_dir}/warm-generated-cache.yml"
case_one_metrics="${case_one_dir}/metrics"
case_one_output="${case_one_dir}/output"

write_workflow_fixture "${case_one_workflow}"
write_metrics_fixture "${case_one_metrics}" 5 6 7 8 9 10 11 12 13 14

run_fixture_case \
  0 \
  "detects threshold drift from local metrics without mutating workflow when apply=false" \
  env WARMUP_WORKFLOW_FILE="${case_one_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_one_metrics}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_one_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Drift detected: recommended threshold differs from workflow defaults."
assert_case_output_contains "Drift detected: true"
assert_file_contains "${case_one_workflow}" 'default: "25"'
assert_file_contains "${case_one_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'

case_two_dir="${TMP_FIXTURE_DIR}/case-two"
mkdir -p "${case_two_dir}"
case_two_workflow="${case_two_dir}/warm-generated-cache.yml"
case_two_output="${case_two_dir}/output"

write_workflow_fixture "${case_two_workflow}"

run_fixture_case \
  0 \
  "applies threshold update when drift is detected and apply=true" \
  env WARMUP_WORKFLOW_FILE="${case_two_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_one_metrics}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_two_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Applied recommended threshold to workflow defaults."
assert_case_output_contains "Changes applied: true"
assert_file_contains "${case_two_workflow}" 'default: "19"'
assert_file_contains "${case_two_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="19"'

case_three_dir="${TMP_FIXTURE_DIR}/case-three"
mkdir -p "${case_three_dir}"
case_three_workflow="${case_three_dir}/warm-generated-cache.yml"
case_three_metrics="${case_three_dir}/metrics"
case_three_output="${case_three_dir}/output"

write_workflow_fixture "${case_three_workflow}"
write_metrics_fixture "${case_three_metrics}" 8 9 10

run_fixture_case \
  0 \
  "returns success on low-confidence recommendation when fail-on-low-confidence is false" \
  env WARMUP_WORKFLOW_FILE="${case_three_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_three_metrics}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_three_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  WARMUP_THRESHOLD_MIN_RUNS="10" \
  WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation detected; skipping apply without failing."
assert_file_contains "${case_three_workflow}" 'default: "25"'
assert_file_contains "${case_three_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'
assert_json_expression "${case_three_output}/warmup-threshold-calibration-result.json" '.low_confidence_guard_triggered == true and .low_confidence_reason == "sample size below minimum confidence threshold (3 < 10)."'

run_fixture_case \
  2 \
  "returns exit 2 when low-confidence recommendation is configured as hard failure" \
  env WARMUP_WORKFLOW_FILE="${case_three_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_three_metrics}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_three_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  WARMUP_THRESHOLD_MIN_RUNS="10" \
  WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation triggered hard failure."

case_no_metrics_dir="${TMP_FIXTURE_DIR}/case-no-metrics"
mkdir -p "${case_no_metrics_dir}"
case_no_metrics_workflow="${case_no_metrics_dir}/warm-generated-cache.yml"
case_no_metrics_metrics="${case_no_metrics_dir}/metrics"
case_no_metrics_output="${case_no_metrics_dir}/output"

write_workflow_fixture "${case_no_metrics_workflow}"
mkdir -p "${case_no_metrics_metrics}"

run_fixture_case \
  0 \
  "returns success when no warm-cache metrics are available and fail-on-low-confidence is false" \
  env WARMUP_WORKFLOW_FILE="${case_no_metrics_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_no_metrics_metrics}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_no_metrics_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "No warm-cache metrics were collected; treating calibration as low-confidence."
assert_case_output_contains "Low-confidence recommendation detected; skipping apply without failing."
assert_file_contains "${case_no_metrics_workflow}" 'default: "25"'
assert_file_contains "${case_no_metrics_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'
assert_json_expression "${case_no_metrics_output}/warmup-threshold-summary.json" '.non_metrics_skipped == 0 and (.source_files | length == 0)'
assert_json_expression "${case_no_metrics_output}/warmup-threshold-calibration-result.json" '.low_confidence_reason == "No warm-cache metrics were collected; treating calibration as low-confidence."'

run_fixture_case \
  2 \
  "returns exit 2 when no warm-cache metrics are available and fail-on-low-confidence is true" \
  env WARMUP_WORKFLOW_FILE="${case_no_metrics_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_no_metrics_metrics}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_no_metrics_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation triggered hard failure."

case_invalid_metrics_dir="${TMP_FIXTURE_DIR}/case-invalid-metrics"
mkdir -p "${case_invalid_metrics_dir}"
case_invalid_metrics_workflow="${case_invalid_metrics_dir}/warm-generated-cache.yml"
case_invalid_metrics_payloads="${case_invalid_metrics_dir}/metrics"
case_invalid_metrics_output="${case_invalid_metrics_dir}/output"

write_workflow_fixture "${case_invalid_metrics_workflow}"
mkdir -p "${case_invalid_metrics_payloads}"

cat > "${case_invalid_metrics_payloads}/not-metrics.json" <<'JSON'
{
  "message": "not a warm-cache metrics payload"
}
JSON

run_fixture_case \
  0 \
  "returns success when collected JSON files are non-metrics and fail-on-low-confidence is false" \
  env WARMUP_WORKFLOW_FILE="${case_invalid_metrics_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_invalid_metrics_payloads}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_invalid_metrics_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "No valid warm-cache metrics payloads were found in collected JSON files; treating calibration as low-confidence."
assert_case_output_contains "Low-confidence recommendation detected; skipping apply without failing."
assert_file_contains "${case_invalid_metrics_workflow}" 'default: "25"'
assert_file_contains "${case_invalid_metrics_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'
assert_json_expression "${case_invalid_metrics_output}/warmup-threshold-summary.json" '.non_metrics_skipped == 1 and (.source_files | length == 1) and (.note == "Collected JSON files did not include valid warm-cache metrics payloads.")'
assert_json_expression "${case_invalid_metrics_output}/warmup-threshold-calibration-result.json" '.low_confidence_reason == "No valid warm-cache metrics payloads were found in collected JSON files; treating calibration as low-confidence."'

run_fixture_case \
  2 \
  "returns exit 2 when collected JSON files are non-metrics and fail-on-low-confidence is true" \
  env WARMUP_WORKFLOW_FILE="${case_invalid_metrics_workflow}" \
  WARMUP_THRESHOLD_METRICS_SOURCE_DIR="${case_invalid_metrics_payloads}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_invalid_metrics_output}" \
  WARMUP_THRESHOLD_APPLY_CHANGES="true" \
  WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="true" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Low-confidence recommendation triggered hard failure."

case_four_dir="${TMP_FIXTURE_DIR}/case-four"
mkdir -p "${case_four_dir}/mock-bin" "${case_four_dir}/artifact-payload" "${case_four_dir}/output"
case_four_workflow="${case_four_dir}/warm-generated-cache.yml"
case_four_artifact_payload="${case_four_dir}/artifact-payload"
case_four_artifact_zip="${case_four_dir}/artifact-321.zip"
case_four_mock_gh="${case_four_dir}/mock-bin/gh"

write_workflow_fixture "${case_four_workflow}"
write_metrics_fixture "${case_four_artifact_payload}" 5 6 7 8 9 10 11 12 13 14

(
  cd "${case_four_artifact_payload}"
  zip -q -r "${case_four_artifact_zip}" .
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
  repos/example/aura/actions/artifacts?name=warm-generated-cache-metrics\&per_page=100)
    cat <<'JSON'
{
  "total_count": 1,
  "artifacts": [
    {
      "id": 321,
      "name": "warm-generated-cache-metrics",
      "expired": false,
      "created_at": "2026-03-05T00:05:10Z"
    }
  ]
}
JSON
    ;;
  repos/example/aura/actions/artifacts/321/zip)
    cat "${GH_FIXTURE_ZIP_FILE}"
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
  "downloads metrics artifacts via gh API and runs drift detection" \
  env PATH="${case_four_dir}/mock-bin:${PATH}" \
  GH_TOKEN="fixture-token" \
  WARMUP_THRESHOLD_GITHUB_REPOSITORY="example/aura" \
  GH_FIXTURE_ZIP_FILE="${case_four_artifact_zip}" \
  WARMUP_WORKFLOW_FILE="${case_four_workflow}" \
  WARMUP_THRESHOLD_OUTPUT_DIR="${case_four_dir}/output" \
  WARMUP_THRESHOLD_APPLY_CHANGES="false" \
  bash "${CALIBRATE_SCRIPT}"
assert_case_output_contains "Downloaded artifact 321."
assert_case_output_contains "Collected 10 metric candidate file(s) from GitHub artifacts."
assert_case_output_contains "Drift detected: true"
assert_file_contains "${case_four_workflow}" 'default: "25"'
assert_file_contains "${case_four_workflow}" 'WARMUP_MAX_RETRY_RATE_PERCENT="25"'

echo ""
echo "Warmup threshold calibration fixture regression suite passed."
