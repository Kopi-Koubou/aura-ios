#!/bin/bash
# Applies warm-cache retry-rate threshold recommendations to workflow defaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-warm-cache-metrics.sh"

WARMUP_WORKFLOW_FILE="${WARMUP_WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/warm-generated-cache.yml}"
WARMUP_METRICS_SUMMARY_INPUT_FILE="${WARMUP_METRICS_SUMMARY_INPUT_FILE:-}"
WARMUP_THRESHOLD_MIN_RUNS="${WARMUP_THRESHOLD_MIN_RUNS:-10}"
WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE="${WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE:-false}"
WARMUP_THRESHOLD_APPLY_DRY_RUN="${WARMUP_THRESHOLD_APPLY_DRY_RUN:-false}"

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/apply-warmup-threshold-from-metrics.sh [metrics-file-or-directory ...]

Environment:
  WARMUP_WORKFLOW_FILE                   Optional workflow path to update.
                                         Default: .github/workflows/warm-generated-cache.yml
  WARMUP_METRICS_SUMMARY_INPUT_FILE      Optional precomputed summary JSON from
                                         summarize-warm-cache-metrics.sh.
  WARMUP_THRESHOLD_MIN_RUNS              Optional integer >=1, default 10.
  WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE  Optional true|false, default false.
  WARMUP_THRESHOLD_APPLY_DRY_RUN         Optional true|false, default false.

Notes:
  - If WARMUP_METRICS_SUMMARY_INPUT_FILE is unset, metrics paths are required
    and the script computes the summary automatically.
  - RETRY_RATE_BUFFER_PERCENT and MIN_RECOMMENDED_RETRY_RATE_PERCENT are passed
    through to summarize-warm-cache-metrics.sh when auto-computing.
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

validate_percent() {
  local var_name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -gt 100 ]; then
    echo "Error: ${var_name} must be an integer between 0 and 100."
    exit 1
  fi
}

extract_input_default() {
  local file_path="$1"
  awk '
    /^      warmup_max_retry_rate_percent:/ { in_block=1; next }
    in_block && /^      [a-z_]+:/ { in_block=0 }
    in_block && /default:[[:space:]]*"[0-9]+"/ {
      value=$0
      sub(/^.*default:[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      print value
      exit
    }
  ' "${file_path}"
}

extract_resolve_default() {
  local file_path="$1"
  grep -E 'WARMUP_MAX_RETRY_RATE_PERCENT="[0-9]+"' "${file_path}" \
    | head -n 1 \
    | sed -E 's/.*WARMUP_MAX_RETRY_RATE_PERCENT="([0-9]+)".*/\1/'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_dependency "jq"
require_dependency "awk"
require_dependency "grep"
require_dependency "sed"
require_dependency "mktemp"
require_dependency "bash"
require_dependency "cp"

ensure_boolean "WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE" "${WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE}"
ensure_boolean "WARMUP_THRESHOLD_APPLY_DRY_RUN" "${WARMUP_THRESHOLD_APPLY_DRY_RUN}"
validate_positive_integer "WARMUP_THRESHOLD_MIN_RUNS" "${WARMUP_THRESHOLD_MIN_RUNS}"

if [ ! -f "${SUMMARY_SCRIPT}" ]; then
  echo "Error: summary script not found: ${SUMMARY_SCRIPT}"
  exit 1
fi

if [ ! -f "${WARMUP_WORKFLOW_FILE}" ]; then
  echo "Error: workflow file not found: ${WARMUP_WORKFLOW_FILE}"
  exit 1
fi

summary_file=""
cleanup_file=""

cleanup_summary_file() {
  if [ -n "${cleanup_file}" ]; then
    rm -f "${cleanup_file}"
  fi
}

if [ -n "${WARMUP_METRICS_SUMMARY_INPUT_FILE}" ]; then
  if [ ! -r "${WARMUP_METRICS_SUMMARY_INPUT_FILE}" ]; then
    echo "Error: WARMUP_METRICS_SUMMARY_INPUT_FILE is not readable: ${WARMUP_METRICS_SUMMARY_INPUT_FILE}"
    exit 1
  fi
  if [ "$#" -gt 0 ]; then
    echo "Warning: metrics paths were provided but ignored because WARMUP_METRICS_SUMMARY_INPUT_FILE is set."
  fi
  summary_file="${WARMUP_METRICS_SUMMARY_INPUT_FILE}"
else
  if [ "$#" -eq 0 ]; then
    echo "Error: provide metrics paths or set WARMUP_METRICS_SUMMARY_INPUT_FILE."
    echo "Hint: run with --help for usage."
    exit 1
  fi

  cleanup_file="$(mktemp)"
  summary_file="${cleanup_file}"
  WARMUP_METRICS_SUMMARY_FILE="${summary_file}" bash "${SUMMARY_SCRIPT}" "$@"
fi

if ! jq -e 'type == "object"' "${summary_file}" >/dev/null 2>&1; then
  echo "Error: summary payload must be a JSON object: ${summary_file}"
  cleanup_summary_file
  exit 1
fi

runs_analyzed="$(jq -r '.runs_analyzed // empty' "${summary_file}")"
recommended_threshold="$(jq -r '.recommendation.max_retry_rate_percent // empty' "${summary_file}")"
p95_retry_rate="$(jq -r '.retry_rate_percentiles.p95 // empty' "${summary_file}")"

if [ -z "${runs_analyzed}" ] || [ -z "${recommended_threshold}" ] || [ -z "${p95_retry_rate}" ]; then
  echo "Error: summary is missing required fields (runs_analyzed, recommendation.max_retry_rate_percent, retry_rate_percentiles.p95)."
  cleanup_summary_file
  exit 1
fi

validate_positive_integer "runs_analyzed" "${runs_analyzed}"
validate_percent "recommended max retry rate" "${recommended_threshold}"
validate_percent "p95 retry rate" "${p95_retry_rate}"

echo "Warmup threshold recommendation"
echo "  Workflow file: ${WARMUP_WORKFLOW_FILE}"
echo "  Runs analyzed: ${runs_analyzed}"
echo "  Retry rate p95: ${p95_retry_rate}%"
echo "  Recommended max retry rate: ${recommended_threshold}%"

if [ "${runs_analyzed}" -lt "${WARMUP_THRESHOLD_MIN_RUNS}" ]; then
  if [ "${WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE}" = "true" ]; then
    echo "  Confidence guard: bypassed (runs ${runs_analyzed} < minimum ${WARMUP_THRESHOLD_MIN_RUNS})."
  else
    echo "Error: sample size below minimum confidence threshold (${runs_analyzed} < ${WARMUP_THRESHOLD_MIN_RUNS})."
    echo "Hint: gather more warm-cache runs or set WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE=true for explicit override."
    cleanup_summary_file
    exit 2
  fi
fi

current_input_default="$(extract_input_default "${WARMUP_WORKFLOW_FILE}")"
current_resolve_default="$(extract_resolve_default "${WARMUP_WORKFLOW_FILE}")"

if [ -z "${current_input_default}" ] || [ -z "${current_resolve_default}" ]; then
  echo "Error: could not locate warmup threshold defaults in workflow file."
  cleanup_summary_file
  exit 1
fi

tmp_workflow="$(mktemp)"

awk -v new_value="${recommended_threshold}" '
  BEGIN { in_block=0 }
  {
    line=$0

    if ($0 ~ /^      warmup_max_retry_rate_percent:/) {
      in_block=1
      print line
      next
    }

    if (in_block == 1 && $0 ~ /^      [a-z_]+:/) {
      in_block=0
    }

    if (in_block == 1 && line ~ /default:[[:space:]]*"[0-9]+"/) {
      sub(/default:[[:space:]]*"[0-9]+"/, "default: \"" new_value "\"", line)
      in_block=0
    }

    if (line ~ /WARMUP_MAX_RETRY_RATE_PERCENT="[0-9]+"/) {
      gsub(/WARMUP_MAX_RETRY_RATE_PERCENT="[0-9]+"/, "WARMUP_MAX_RETRY_RATE_PERCENT=\"" new_value "\"", line)
    }

    print line
  }
' "${WARMUP_WORKFLOW_FILE}" > "${tmp_workflow}"

updated_input_default="$(extract_input_default "${tmp_workflow}")"
updated_resolve_default="$(extract_resolve_default "${tmp_workflow}")"

if [ -z "${updated_input_default}" ] || [ -z "${updated_resolve_default}" ]; then
  echo "Error: failed to render updated workflow defaults."
  rm -f "${tmp_workflow}"
  cleanup_summary_file
  exit 1
fi

if [ "${updated_input_default}" != "${recommended_threshold}" ] || [ "${updated_resolve_default}" != "${recommended_threshold}" ]; then
  echo "Error: updated workflow does not contain the recommended threshold in all required locations."
  rm -f "${tmp_workflow}"
  cleanup_summary_file
  exit 1
fi

if [ "${current_input_default}" = "${recommended_threshold}" ] \
  && [ "${current_resolve_default}" = "${recommended_threshold}" ]; then
  echo "Workflow already uses the recommended threshold; no change required."
  rm -f "${tmp_workflow}"
  cleanup_summary_file
  exit 0
fi

echo "  Existing defaults: input=${current_input_default}% resolve=${current_resolve_default}%"
echo "  Updated defaults:  input=${updated_input_default}% resolve=${updated_resolve_default}%"

if [ "${WARMUP_THRESHOLD_APPLY_DRY_RUN}" = "true" ]; then
  echo "Dry run enabled; workflow file was not modified."
  if command -v diff >/dev/null 2>&1; then
    diff -u "${WARMUP_WORKFLOW_FILE}" "${tmp_workflow}" || true
  fi
else
  cp "${tmp_workflow}" "${WARMUP_WORKFLOW_FILE}"
  echo "Applied recommended threshold to workflow defaults."
fi

rm -f "${tmp_workflow}"
cleanup_summary_file
