#!/bin/bash
# Pulls readiness-escalation metrics artifacts, calibrates page limits, and optionally applies workflow updates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-readiness-escalation-metrics.sh"
APPLY_SCRIPT="${REPO_ROOT}/scripts/apply-readiness-page-limits-from-metrics.sh"

READINESS_AUTH_WORKFLOW_FILE="${READINESS_AUTH_WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/auth-fallback-readiness.yml}"
READINESS_CACHE_WORKFLOW_FILE="${READINESS_CACHE_WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/cache-degradation-readiness.yml}"
READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR="${READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR:-}"
READINESS_PAGE_LIMIT_AUTH_ARTIFACT_NAME="${READINESS_PAGE_LIMIT_AUTH_ARTIFACT_NAME:-auth-fallback-readiness-escalation-metrics}"
READINESS_PAGE_LIMIT_CACHE_ARTIFACT_NAME="${READINESS_PAGE_LIMIT_CACHE_ARTIFACT_NAME:-cache-degradation-readiness-escalation-metrics}"
READINESS_PAGE_LIMIT_ARTIFACT_LIMIT="${READINESS_PAGE_LIMIT_ARTIFACT_LIMIT:-20}"
READINESS_PAGE_LIMIT_APPLY_CHANGES="${READINESS_PAGE_LIMIT_APPLY_CHANGES:-false}"
READINESS_THRESHOLD_MIN_RUNS="${READINESS_THRESHOLD_MIN_RUNS:-10}"
READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE="${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE:-false}"
READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="${READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE:-false}"
READINESS_PAGE_LIMIT_OUTPUT_DIR="${READINESS_PAGE_LIMIT_OUTPUT_DIR:-${REPO_ROOT}/ops/readiness-page-limit-calibration}"
READINESS_PAGE_LIMIT_GITHUB_REPOSITORY="${READINESS_PAGE_LIMIT_GITHUB_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

METRICS_DIR=""
ARTIFACT_DIR=""
SUMMARY_FILE=""
SUMMARY_LOG=""
DRY_RUN_LOG=""
APPLY_LOG=""
RESULT_FILE=""
LOW_CONFIDENCE_GUARD_TRIGGERED="false"
LOW_CONFIDENCE_REASON=""
DRIFT_DETECTED="false"
CHANGES_APPLIED="false"
METRICS_FILES_ANALYZED="0"
RUNS_ANALYZED="0"
RECOMMENDED_OPEN_ISSUES_MAX_PAGES="0"
RECOMMENDED_CLOSED_ISSUES_MAX_PAGES="0"
GENERATED_AT_UTC=""
AUTH_ARTIFACT_IDS_USED="[]"
CACHE_ARTIFACT_IDS_USED="[]"
FETCHED_ARTIFACT_IDS_JSON="[]"

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/propose-readiness-page-limit-update.sh

Environment:
  READINESS_AUTH_WORKFLOW_FILE                 Optional auth readiness workflow path.
                                               Default: .github/workflows/auth-fallback-readiness.yml
  READINESS_CACHE_WORKFLOW_FILE                Optional cache readiness workflow path.
                                               Default: .github/workflows/cache-degradation-readiness.yml
  READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR      Optional local metrics directory.
                                               If set, artifact download is skipped.
  READINESS_PAGE_LIMIT_AUTH_ARTIFACT_NAME      Auth readiness artifact name.
                                               Default: auth-fallback-readiness-escalation-metrics
  READINESS_PAGE_LIMIT_CACHE_ARTIFACT_NAME     Cache readiness artifact name.
                                               Default: cache-degradation-readiness-escalation-metrics
  READINESS_PAGE_LIMIT_ARTIFACT_LIMIT          Max artifacts per readiness type, default 20.
  READINESS_PAGE_LIMIT_APPLY_CHANGES           Optional true|false, default false.
  READINESS_THRESHOLD_MIN_RUNS                 Optional integer >=1, default 10.
  READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE     Optional true|false, default false.
  READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE   Optional true|false, default false.
  READINESS_PAGE_LIMIT_OUTPUT_DIR              Optional output directory for logs/artifacts.
  READINESS_PAGE_LIMIT_GITHUB_REPOSITORY       Optional owner/repo override.
  GH_TOKEN                                     Required when downloading artifacts.

Notes:
  - Always runs apply script in dry-run mode first to detect drift.
  - Applies workflow changes only when drift is detected and
    READINESS_PAGE_LIMIT_APPLY_CHANGES=true.
  - Pass-through knobs to summary/apply scripts:
    READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES
    MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES
    MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES
EOF
}

require_dependency() {
  local dependency="$1"
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Error: required dependency '${dependency}' is not installed."
    exit 1
  fi
}

ensure_boolean() {
  local var_name="$1"
  local value="$2"
  if [ "${value}" != "true" ] && [ "${value}" != "false" ]; then
    echo "Error: ${var_name} must be true or false."
    exit 1
  fi
}

validate_positive_integer() {
  local var_name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -lt 1 ]; then
    echo "Error: ${var_name} must be an integer >= 1."
    exit 1
  fi
}

write_output() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
  fi
}

write_common_outputs() {
  write_output "drift_detected" "${DRIFT_DETECTED}"
  write_output "changes_applied" "${CHANGES_APPLIED}"
  write_output "low_confidence_guard_triggered" "${LOW_CONFIDENCE_GUARD_TRIGGERED}"
  write_output "low_confidence_reason" "${LOW_CONFIDENCE_REASON}"
  write_output "metrics_files_analyzed" "${METRICS_FILES_ANALYZED}"
  write_output "runs_analyzed" "${RUNS_ANALYZED}"
  write_output "recommended_open_issues_max_pages" "${RECOMMENDED_OPEN_ISSUES_MAX_PAGES}"
  write_output "recommended_closed_issues_max_pages" "${RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}"
  write_output "generated_at_utc" "${GENERATED_AT_UTC}"
  write_output "summary_file" "${SUMMARY_FILE}"
  write_output "result_file" "${RESULT_FILE}"
}

copy_metrics_files_from_directory() {
  local source_dir="$1"
  local copied=0
  local source_file
  local destination_file

  if [ ! -d "${source_dir}" ]; then
    echo "Error: metrics source directory not found: ${source_dir}"
    exit 1
  fi

  while IFS= read -r source_file; do
    [ -z "${source_file}" ] && continue
    destination_file="${METRICS_DIR}/local-${copied}-$(basename "${source_file}")"
    cp "${source_file}" "${destination_file}"
    copied=$((copied + 1))
  done < <(find "${source_dir}" -type f -name '*.json' | sort)

  if [ "${copied}" -eq 0 ]; then
    echo "Warning: no JSON files found in metrics source directory: ${source_dir}"
    return 0
  fi

  echo "Copied ${copied} metric candidate file(s) from ${source_dir}."
}

fetch_recent_artifacts_for_name() {
  local artifact_name="$1"
  local label="$2"
  local artifacts_payload
  local artifact_ids=()
  local artifact_id
  local artifact_zip
  local artifact_extract_dir
  local copied=0
  local extracted_metrics_file

  FETCHED_ARTIFACT_IDS_JSON="[]"

  if [ -z "${GH_TOKEN}" ]; then
    echo "Error: GH_TOKEN (or GITHUB_TOKEN) is required to download artifacts."
    exit 1
  fi

  if [ -z "${READINESS_PAGE_LIMIT_GITHUB_REPOSITORY}" ]; then
    echo "Error: READINESS_PAGE_LIMIT_GITHUB_REPOSITORY (or GITHUB_REPOSITORY) is required to download artifacts."
    exit 1
  fi

  artifacts_payload="$(
    GH_TOKEN="${GH_TOKEN}" gh api \
      "repos/${READINESS_PAGE_LIMIT_GITHUB_REPOSITORY}/actions/artifacts?name=${artifact_name}&per_page=100"
  )"

  if ! printf '%s\n' "${artifacts_payload}" | jq -e 'type == "object" and (.artifacts | type == "array")' >/dev/null; then
    echo "Error: unexpected artifact payload shape from GitHub API for '${artifact_name}'."
    exit 1
  fi

  while IFS= read -r artifact_id; do
    [ -z "${artifact_id}" ] && continue
    artifact_ids+=("${artifact_id}")
  done < <(
    printf '%s\n' "${artifacts_payload}" | jq -r \
      --argjson limit "${READINESS_PAGE_LIMIT_ARTIFACT_LIMIT}" '
        .artifacts
        | map(select(.expired == false))
        | sort_by(.created_at) | reverse
        | .[:$limit]
        | .[].id
      '
  )

  if [ "${#artifact_ids[@]}" -eq 0 ]; then
    echo "Warning: no non-expired '${artifact_name}' artifacts found in ${READINESS_PAGE_LIMIT_GITHUB_REPOSITORY}."
    return 0
  fi

  FETCHED_ARTIFACT_IDS_JSON="$(printf '%s\n' "${artifact_ids[@]}" | jq -R . | jq -s .)"

  for artifact_id in "${artifact_ids[@]}"; do
    artifact_zip="${ARTIFACT_DIR}/${label}-artifact-${artifact_id}.zip"
    artifact_extract_dir="${ARTIFACT_DIR}/${label}-artifact-${artifact_id}"
    mkdir -p "${artifact_extract_dir}"

    GH_TOKEN="${GH_TOKEN}" gh api \
      "repos/${READINESS_PAGE_LIMIT_GITHUB_REPOSITORY}/actions/artifacts/${artifact_id}/zip" > "${artifact_zip}"

    unzip -qq -o "${artifact_zip}" -d "${artifact_extract_dir}"

    while IFS= read -r extracted_metrics_file; do
      [ -z "${extracted_metrics_file}" ] && continue
      cp "${extracted_metrics_file}" "${METRICS_DIR}/${label}-artifact-${artifact_id}-${copied}.json"
      copied=$((copied + 1))
    done < <(find "${artifact_extract_dir}" -type f -name '*.json' | sort)

    echo "Downloaded ${label} metrics artifact ${artifact_id}."
  done

  if [ "${copied}" -eq 0 ]; then
    echo "Warning: no JSON files were extracted from '${artifact_name}' artifacts."
  fi
}

emit_result_json() {
  jq -n \
    --arg generated_at_utc "${GENERATED_AT_UTC}" \
    --arg auth_workflow_file "${READINESS_AUTH_WORKFLOW_FILE}" \
    --arg cache_workflow_file "${READINESS_CACHE_WORKFLOW_FILE}" \
    --arg output_dir "${READINESS_PAGE_LIMIT_OUTPUT_DIR}" \
    --argjson drift_detected "$( [ "${DRIFT_DETECTED}" = "true" ] && echo true || echo false )" \
    --argjson changes_applied "$( [ "${CHANGES_APPLIED}" = "true" ] && echo true || echo false )" \
    --argjson low_confidence_guard_triggered "$( [ "${LOW_CONFIDENCE_GUARD_TRIGGERED}" = "true" ] && echo true || echo false )" \
    --arg low_confidence_reason "${LOW_CONFIDENCE_REASON}" \
    --argjson metrics_files_analyzed "${METRICS_FILES_ANALYZED}" \
    --argjson runs_analyzed "${RUNS_ANALYZED}" \
    --argjson recommended_open_issues_max_pages "${RECOMMENDED_OPEN_ISSUES_MAX_PAGES}" \
    --argjson recommended_closed_issues_max_pages "${RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}" \
    --argjson auth_artifact_ids_used "${AUTH_ARTIFACT_IDS_USED}" \
    --argjson cache_artifact_ids_used "${CACHE_ARTIFACT_IDS_USED}" \
    --arg summary_file "${SUMMARY_FILE}" \
    --arg dry_run_log "${DRY_RUN_LOG}" \
    --arg apply_log "${APPLY_LOG}" \
    '{
      generated_at_utc: $generated_at_utc,
      auth_workflow_file: $auth_workflow_file,
      cache_workflow_file: $cache_workflow_file,
      output_dir: $output_dir,
      drift_detected: $drift_detected,
      changes_applied: $changes_applied,
      low_confidence_guard_triggered: $low_confidence_guard_triggered,
      low_confidence_reason: $low_confidence_reason,
      metrics_files_analyzed: $metrics_files_analyzed,
      runs_analyzed: $runs_analyzed,
      recommendation: {
        escalation_open_issues_max_pages: $recommended_open_issues_max_pages,
        escalation_closed_issues_max_pages: $recommended_closed_issues_max_pages
      },
      artifact_ids_used: {
        auth_fallback: $auth_artifact_ids_used,
        cache_degradation: $cache_artifact_ids_used
      },
      summary_file: $summary_file,
      dry_run_log: $dry_run_log,
      apply_log: $apply_log
    }' > "${RESULT_FILE}"
}

emit_low_confidence_summary_and_exit() {
  local summary_note="$1"
  local reason_message="$2"
  local source_files_json
  source_files_json="$(find "${METRICS_DIR}" -type f -name '*.json' | sort | jq -R . | jq -s .)"

  RUNS_ANALYZED="0"
  RECOMMENDED_OPEN_ISSUES_MAX_PAGES="0"
  RECOMMENDED_CLOSED_ISSUES_MAX_PAGES="0"
  GENERATED_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  LOW_CONFIDENCE_GUARD_TRIGGERED="true"
  LOW_CONFIDENCE_REASON="${reason_message}"

  jq -n \
    --arg generated_at_utc "${GENERATED_AT_UTC}" \
    --argjson source_files "${source_files_json}" \
    --argjson non_metrics_skipped "${METRICS_FILES_ANALYZED}" \
    --arg note "${summary_note}" \
    '{
      generated_at_utc: $generated_at_utc,
      metrics_window: {
        start_utc: "(unavailable)",
        end_utc: "(unavailable)"
      },
      runs_analyzed: 0,
      non_metrics_skipped: $non_metrics_skipped,
      kind_counts: {
        auth_fallback: 0,
        cache_degradation: 0,
        other: 0
      },
      status_counts: {
        failure: 0,
        recovered: 0,
        other: 0
      },
      mode_counts: {
        dry_run: 0,
        live: 0
      },
      open_pages: {
        scanned_percentiles: {
          p50: 0,
          p95: 0,
          max: 0
        },
        match_percentiles: {
          p50: 0,
          p95: 0,
          max: 0
        },
        limit_hit_count: 0,
        limit_hit_rate_percent: 0
      },
      closed_pages: {
        scanned_percentiles: {
          p50: 0,
          p95: 0,
          max: 0
        },
        match_percentiles: {
          p50: 0,
          p95: 0,
          max: 0
        },
        limit_hit_count: 0,
        limit_hit_rate_percent: 0
      },
      recommendation: {
        escalation_open_issues_max_pages: 0,
        escalation_closed_issues_max_pages: 0,
        buffer_pages: 0,
        min_open_pages: 0,
        min_closed_pages: 0
      },
      source_files: $source_files,
      note: $note
    }' > "${SUMMARY_FILE}"

  echo "${reason_message}"
  emit_result_json
  write_common_outputs

  if [ "${READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE}" = "true" ]; then
    echo "Low-confidence recommendation triggered hard failure."
    exit 2
  fi

  echo "Low-confidence recommendation detected; skipping apply without failing."
  exit 0
}

resolve_low_confidence_reason_from_dry_run_log() {
  local reason
  if [ -f "${DRY_RUN_LOG}" ]; then
    reason="$(
      grep -F "Error: sample size below minimum confidence threshold" "${DRY_RUN_LOG}" \
        | head -n 1 \
        | sed -E 's/^Error:[[:space:]]*//'
    )"

    if [ -z "${reason}" ]; then
      reason="$(
        grep -F "Error:" "${DRY_RUN_LOG}" \
          | head -n 1 \
          | sed -E 's/^Error:[[:space:]]*//'
      )"
    fi
  fi

  if [ -z "${reason}" ]; then
    reason="Low-confidence recommendation triggered by confidence guard."
  fi

  echo "${reason}"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_dependency "jq"
require_dependency "find"
require_dependency "mktemp"
require_dependency "cp"
require_dependency "bash"
require_dependency "grep"
if [ -z "${READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR}" ]; then
  require_dependency "gh"
  require_dependency "unzip"
fi

ensure_boolean "READINESS_PAGE_LIMIT_APPLY_CHANGES" "${READINESS_PAGE_LIMIT_APPLY_CHANGES}"
ensure_boolean "READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE" "${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE}"
ensure_boolean "READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE" "${READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE}"
validate_positive_integer "READINESS_PAGE_LIMIT_ARTIFACT_LIMIT" "${READINESS_PAGE_LIMIT_ARTIFACT_LIMIT}"
validate_positive_integer "READINESS_THRESHOLD_MIN_RUNS" "${READINESS_THRESHOLD_MIN_RUNS}"

if [ ! -f "${SUMMARY_SCRIPT}" ]; then
  echo "Error: summary script not found: ${SUMMARY_SCRIPT}"
  exit 1
fi

if [ ! -f "${APPLY_SCRIPT}" ]; then
  echo "Error: apply script not found: ${APPLY_SCRIPT}"
  exit 1
fi

if [ ! -f "${READINESS_AUTH_WORKFLOW_FILE}" ]; then
  echo "Error: auth readiness workflow file not found: ${READINESS_AUTH_WORKFLOW_FILE}"
  exit 1
fi

if [ ! -f "${READINESS_CACHE_WORKFLOW_FILE}" ]; then
  echo "Error: cache readiness workflow file not found: ${READINESS_CACHE_WORKFLOW_FILE}"
  exit 1
fi

mkdir -p "${READINESS_PAGE_LIMIT_OUTPUT_DIR}"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

METRICS_DIR="${TMP_ROOT}/metrics"
ARTIFACT_DIR="${TMP_ROOT}/artifacts"
mkdir -p "${METRICS_DIR}" "${ARTIFACT_DIR}"

SUMMARY_FILE="${READINESS_PAGE_LIMIT_OUTPUT_DIR}/readiness-page-limit-summary.json"
SUMMARY_LOG="${READINESS_PAGE_LIMIT_OUTPUT_DIR}/readiness-page-limit-summary.log"
DRY_RUN_LOG="${READINESS_PAGE_LIMIT_OUTPUT_DIR}/readiness-page-limit-apply-dry-run.log"
APPLY_LOG="${READINESS_PAGE_LIMIT_OUTPUT_DIR}/readiness-page-limit-apply.log"
RESULT_FILE="${READINESS_PAGE_LIMIT_OUTPUT_DIR}/readiness-page-limit-calibration-result.json"

echo "Readiness page-limit calibration"
echo "  Auth workflow file: ${READINESS_AUTH_WORKFLOW_FILE}"
echo "  Cache workflow file: ${READINESS_CACHE_WORKFLOW_FILE}"
echo "  Apply changes: ${READINESS_PAGE_LIMIT_APPLY_CHANGES}"
echo "  Min runs: ${READINESS_THRESHOLD_MIN_RUNS}"
echo "  Allow low confidence: ${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE}"
echo "  Fail on low confidence: ${READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE}"
echo "  Output dir: ${READINESS_PAGE_LIMIT_OUTPUT_DIR}"

if [ -n "${READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR}" ]; then
  echo "  Metrics source: local directory (${READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR})"
  copy_metrics_files_from_directory "${READINESS_PAGE_LIMIT_METRICS_SOURCE_DIR}"
else
  echo "  Metrics source: GitHub artifacts (${READINESS_PAGE_LIMIT_AUTH_ARTIFACT_NAME}, ${READINESS_PAGE_LIMIT_CACHE_ARTIFACT_NAME})"
  fetch_recent_artifacts_for_name "${READINESS_PAGE_LIMIT_AUTH_ARTIFACT_NAME}" "auth"
  AUTH_ARTIFACT_IDS_USED="${FETCHED_ARTIFACT_IDS_JSON}"
  fetch_recent_artifacts_for_name "${READINESS_PAGE_LIMIT_CACHE_ARTIFACT_NAME}" "cache"
  CACHE_ARTIFACT_IDS_USED="${FETCHED_ARTIFACT_IDS_JSON}"
fi

METRICS_FILES_ANALYZED="$(find "${METRICS_DIR}" -type f -name '*.json' | wc -l | tr -d ' ')"
if [ "${METRICS_FILES_ANALYZED}" -eq 0 ]; then
  emit_low_confidence_summary_and_exit \
    "No readiness metrics files were collected." \
    "No readiness metrics were collected; treating calibration as low-confidence."
fi

echo "Collected ${METRICS_FILES_ANALYZED} metric candidate file(s) for readiness calibration."

set +e
READINESS_ESCALATION_METRICS_SUMMARY_FILE="${SUMMARY_FILE}" \
  bash "${SUMMARY_SCRIPT}" "${METRICS_DIR}" | tee "${SUMMARY_LOG}"
SUMMARY_EXIT=$?
set -e

if [ "${SUMMARY_EXIT}" -ne 0 ]; then
  if grep -Fq "Error: no valid readiness escalation metrics files found." "${SUMMARY_LOG}"; then
    emit_low_confidence_summary_and_exit \
      "Collected JSON files did not include valid readiness metrics payloads." \
      "No valid readiness metrics payloads were found in collected JSON files; treating calibration as low-confidence."
  fi

  echo "Error: readiness metrics summarization failed."
  exit "${SUMMARY_EXIT}"
fi

RUNS_ANALYZED="$(jq -r '.runs_analyzed // 0' "${SUMMARY_FILE}")"
RECOMMENDED_OPEN_ISSUES_MAX_PAGES="$(jq -r '.recommendation.escalation_open_issues_max_pages // 0' "${SUMMARY_FILE}")"
RECOMMENDED_CLOSED_ISSUES_MAX_PAGES="$(jq -r '.recommendation.escalation_closed_issues_max_pages // 0' "${SUMMARY_FILE}")"
GENERATED_AT_UTC="$(jq -r '.generated_at_utc // empty' "${SUMMARY_FILE}")"

set +e
READINESS_AUTH_WORKFLOW_FILE="${READINESS_AUTH_WORKFLOW_FILE}" \
READINESS_CACHE_WORKFLOW_FILE="${READINESS_CACHE_WORKFLOW_FILE}" \
READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE="${SUMMARY_FILE}" \
READINESS_THRESHOLD_MIN_RUNS="${READINESS_THRESHOLD_MIN_RUNS}" \
READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE="${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE}" \
READINESS_THRESHOLD_APPLY_DRY_RUN="true" \
  bash "${APPLY_SCRIPT}" > "${DRY_RUN_LOG}" 2>&1
DRY_RUN_EXIT=$?
set -e

cat "${DRY_RUN_LOG}"

if [ "${DRY_RUN_EXIT}" -eq 2 ]; then
  LOW_CONFIDENCE_GUARD_TRIGGERED="true"
  LOW_CONFIDENCE_REASON="$(resolve_low_confidence_reason_from_dry_run_log)"
  if [ "${READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE}" = "true" ]; then
    echo "Low-confidence recommendation triggered hard failure."
    emit_result_json
    write_common_outputs
    exit 2
  fi

  echo "Low-confidence recommendation detected; skipping apply without failing."
  emit_result_json
  write_common_outputs
  exit 0
fi

if [ "${DRY_RUN_EXIT}" -ne 0 ]; then
  echo "Error: dry-run readiness page-limit apply failed."
  emit_result_json
  write_common_outputs
  exit "${DRY_RUN_EXIT}"
fi

if grep -Fq "All readiness workflows already use the recommended page limits; no change required." "${DRY_RUN_LOG}"; then
  DRIFT_DETECTED="false"
  echo "No drift detected."
else
  DRIFT_DETECTED="true"
  echo "Drift detected: recommended page limits differ from workflow defaults."
fi

if [ "${DRIFT_DETECTED}" = "true" ] && [ "${READINESS_PAGE_LIMIT_APPLY_CHANGES}" = "true" ]; then
  READINESS_AUTH_WORKFLOW_FILE="${READINESS_AUTH_WORKFLOW_FILE}" \
  READINESS_CACHE_WORKFLOW_FILE="${READINESS_CACHE_WORKFLOW_FILE}" \
  READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE="${SUMMARY_FILE}" \
  READINESS_THRESHOLD_MIN_RUNS="${READINESS_THRESHOLD_MIN_RUNS}" \
  READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE="${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE}" \
  READINESS_THRESHOLD_APPLY_DRY_RUN="false" \
    bash "${APPLY_SCRIPT}" | tee "${APPLY_LOG}"
  CHANGES_APPLIED="true"
else
  CHANGES_APPLIED="false"
fi

emit_result_json
write_common_outputs

echo "Calibration complete."
echo "  Drift detected: ${DRIFT_DETECTED}"
echo "  Changes applied: ${CHANGES_APPLIED}"
echo "  Runs analyzed: ${RUNS_ANALYZED}"
echo "  Recommended open max pages: ${RECOMMENDED_OPEN_ISSUES_MAX_PAGES}"
echo "  Recommended closed max pages: ${RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}"
echo "  Result file: ${RESULT_FILE}"
