#!/bin/bash
# Applies readiness escalation page-limit recommendations to readiness workflows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_SCRIPT="${REPO_ROOT}/scripts/summarize-readiness-escalation-metrics.sh"

READINESS_AUTH_WORKFLOW_FILE="${READINESS_AUTH_WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/auth-fallback-readiness.yml}"
READINESS_CACHE_WORKFLOW_FILE="${READINESS_CACHE_WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/cache-degradation-readiness.yml}"
READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE="${READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE:-}"
READINESS_THRESHOLD_MIN_RUNS="${READINESS_THRESHOLD_MIN_RUNS:-10}"
READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE="${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE:-false}"
READINESS_THRESHOLD_APPLY_DRY_RUN="${READINESS_THRESHOLD_APPLY_DRY_RUN:-false}"

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/apply-readiness-page-limits-from-metrics.sh [metrics-file-or-directory ...]

Environment:
  READINESS_AUTH_WORKFLOW_FILE                    Optional workflow path.
                                                  Default: .github/workflows/auth-fallback-readiness.yml
  READINESS_CACHE_WORKFLOW_FILE                   Optional workflow path.
                                                  Default: .github/workflows/cache-degradation-readiness.yml
  READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE Optional precomputed summary
                                                  JSON from summarize-readiness-escalation-metrics.sh.
  READINESS_THRESHOLD_MIN_RUNS                    Optional integer >=1, default 10.
  READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE        Optional true|false, default false.
  READINESS_THRESHOLD_APPLY_DRY_RUN               Optional true|false, default false.

Notes:
  - If READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE is unset, metrics paths
    are required and the script computes a summary automatically.
  - READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES,
    MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES, and
    MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES are passed through to
    summarize-readiness-escalation-metrics.sh when auto-computing.
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

extract_input_default() {
  local file_path="$1"
  local input_key="$2"
  awk -v key="${input_key}" '
    $0 ~ "^      " key ":" { in_block=1; next }
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
  local variable_name="$2"
  grep -E "${variable_name}=\"[0-9]+\"" "${file_path}" \
    | head -n 1 \
    | sed -E "s/.*${variable_name}=\"([0-9]+)\".*/\\1/"
}

render_updated_workflow() {
  local file_path="$1"
  local new_open="$2"
  local new_closed="$3"
  local output_path="$4"

  awk -v new_open="${new_open}" -v new_closed="${new_closed}" '
    BEGIN {
      in_open_block=0
      in_closed_block=0
    }
    {
      line=$0

      if ($0 ~ /^      escalation_open_issues_max_pages:/) {
        in_open_block=1
        in_closed_block=0
        print line
        next
      }

      if ($0 ~ /^      escalation_closed_issues_max_pages:/) {
        in_closed_block=1
        in_open_block=0
        print line
        next
      }

      if (in_open_block == 1 && $0 ~ /^      [a-z_]+:/) {
        in_open_block=0
      }

      if (in_closed_block == 1 && $0 ~ /^      [a-z_]+:/) {
        in_closed_block=0
      }

      if (in_open_block == 1 && line ~ /default:[[:space:]]*"[0-9]+"/) {
        sub(/default:[[:space:]]*"[0-9]+"/, "default: \"" new_open "\"", line)
        in_open_block=0
      }

      if (in_closed_block == 1 && line ~ /default:[[:space:]]*"[0-9]+"/) {
        sub(/default:[[:space:]]*"[0-9]+"/, "default: \"" new_closed "\"", line)
        in_closed_block=0
      }

      if (line ~ /ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="[0-9]+"/) {
        gsub(/ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT="[0-9]+"/, "ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT=\"" new_open "\"", line)
      }

      if (line ~ /ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="[0-9]+"/) {
        gsub(/ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT="[0-9]+"/, "ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT=\"" new_closed "\"", line)
      }

      print line
    }
  ' "${file_path}" > "${output_path}"
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

ensure_boolean "READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE" "${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE}"
ensure_boolean "READINESS_THRESHOLD_APPLY_DRY_RUN" "${READINESS_THRESHOLD_APPLY_DRY_RUN}"
validate_positive_integer "READINESS_THRESHOLD_MIN_RUNS" "${READINESS_THRESHOLD_MIN_RUNS}"

if [ ! -f "${SUMMARY_SCRIPT}" ]; then
  echo "Error: summary script not found: ${SUMMARY_SCRIPT}"
  exit 1
fi

for workflow_path in "${READINESS_AUTH_WORKFLOW_FILE}" "${READINESS_CACHE_WORKFLOW_FILE}"; do
  if [ ! -f "${workflow_path}" ]; then
    echo "Error: workflow file not found: ${workflow_path}"
    exit 1
  fi
done

summary_file=""
cleanup_file=""

cleanup_summary_file() {
  if [ -n "${cleanup_file}" ]; then
    rm -f "${cleanup_file}"
  fi
}

if [ -n "${READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE}" ]; then
  if [ ! -r "${READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE}" ]; then
    echo "Error: READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE is not readable: ${READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE}"
    exit 1
  fi
  if [ "$#" -gt 0 ]; then
    echo "Warning: metrics paths were provided but ignored because READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE is set."
  fi
  summary_file="${READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE}"
else
  if [ "$#" -eq 0 ]; then
    echo "Error: provide metrics paths or set READINESS_ESCALATION_METRICS_SUMMARY_INPUT_FILE."
    echo "Hint: run with --help for usage."
    exit 1
  fi

  cleanup_file="$(mktemp)"
  summary_file="${cleanup_file}"
  READINESS_ESCALATION_METRICS_SUMMARY_FILE="${summary_file}" \
    bash "${SUMMARY_SCRIPT}" "$@"
fi

if ! jq -e 'type == "object"' "${summary_file}" >/dev/null 2>&1; then
  echo "Error: summary payload must be a JSON object: ${summary_file}"
  cleanup_summary_file
  exit 1
fi

runs_analyzed="$(jq -r '.runs_analyzed // empty' "${summary_file}")"
recommended_open_pages="$(jq -r '.recommendation.escalation_open_issues_max_pages // empty' "${summary_file}")"
recommended_closed_pages="$(jq -r '.recommendation.escalation_closed_issues_max_pages // empty' "${summary_file}")"

if [ -z "${runs_analyzed}" ] || [ -z "${recommended_open_pages}" ] || [ -z "${recommended_closed_pages}" ]; then
  echo "Error: summary is missing required fields (runs_analyzed, recommendation.escalation_open_issues_max_pages, recommendation.escalation_closed_issues_max_pages)."
  cleanup_summary_file
  exit 1
fi

validate_positive_integer "runs_analyzed" "${runs_analyzed}"
validate_positive_integer "recommendation.escalation_open_issues_max_pages" "${recommended_open_pages}"
validate_positive_integer "recommendation.escalation_closed_issues_max_pages" "${recommended_closed_pages}"

echo "Readiness page-limit recommendation"
echo "  Runs analyzed: ${runs_analyzed}"
echo "  Recommended open max pages: ${recommended_open_pages}"
echo "  Recommended closed max pages: ${recommended_closed_pages}"

if [ "${runs_analyzed}" -lt "${READINESS_THRESHOLD_MIN_RUNS}" ]; then
  if [ "${READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE}" = "true" ]; then
    echo "  Confidence guard: bypassed (runs ${runs_analyzed} < minimum ${READINESS_THRESHOLD_MIN_RUNS})."
  else
    echo "Error: sample size below minimum confidence threshold (${runs_analyzed} < ${READINESS_THRESHOLD_MIN_RUNS})."
    echo "Hint: gather more readiness escalation metrics or set READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE=true for explicit override."
    cleanup_summary_file
    exit 2
  fi
fi

workflow_paths=("${READINESS_AUTH_WORKFLOW_FILE}" "${READINESS_CACHE_WORKFLOW_FILE}")
workflow_needs_update=()
tmp_files=()
drift_detected="false"

for workflow_path in "${workflow_paths[@]}"; do
  current_open_input="$(extract_input_default "${workflow_path}" "escalation_open_issues_max_pages")"
  current_closed_input="$(extract_input_default "${workflow_path}" "escalation_closed_issues_max_pages")"
  current_open_resolve="$(extract_resolve_default "${workflow_path}" "ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT")"
  current_closed_resolve="$(extract_resolve_default "${workflow_path}" "ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT")"

  if [ -z "${current_open_input}" ] || [ -z "${current_closed_input}" ] || [ -z "${current_open_resolve}" ] || [ -z "${current_closed_resolve}" ]; then
    echo "Error: could not locate readiness escalation defaults in workflow file: ${workflow_path}"
    cleanup_summary_file
    exit 1
  fi

  validate_positive_integer "current_open_input" "${current_open_input}"
  validate_positive_integer "current_closed_input" "${current_closed_input}"
  validate_positive_integer "current_open_resolve" "${current_open_resolve}"
  validate_positive_integer "current_closed_resolve" "${current_closed_resolve}"

  tmp_workflow="$(mktemp)"
  tmp_files+=("${tmp_workflow}")
  render_updated_workflow "${workflow_path}" "${recommended_open_pages}" "${recommended_closed_pages}" "${tmp_workflow}"

  updated_open_input="$(extract_input_default "${tmp_workflow}" "escalation_open_issues_max_pages")"
  updated_closed_input="$(extract_input_default "${tmp_workflow}" "escalation_closed_issues_max_pages")"
  updated_open_resolve="$(extract_resolve_default "${tmp_workflow}" "ESCALATION_OPEN_ISSUES_MAX_PAGES_INPUT")"
  updated_closed_resolve="$(extract_resolve_default "${tmp_workflow}" "ESCALATION_CLOSED_ISSUES_MAX_PAGES_INPUT")"

  if [ -z "${updated_open_input}" ] || [ -z "${updated_closed_input}" ] || [ -z "${updated_open_resolve}" ] || [ -z "${updated_closed_resolve}" ]; then
    echo "Error: failed to render updated workflow defaults for ${workflow_path}."
    cleanup_summary_file
    exit 1
  fi

  if [ "${updated_open_input}" != "${recommended_open_pages}" ] \
    || [ "${updated_closed_input}" != "${recommended_closed_pages}" ] \
    || [ "${updated_open_resolve}" != "${recommended_open_pages}" ] \
    || [ "${updated_closed_resolve}" != "${recommended_closed_pages}" ]; then
    echo "Error: updated workflow does not contain recommended page limits in all required locations: ${workflow_path}"
    cleanup_summary_file
    exit 1
  fi

  needs_update="false"
  if [ "${current_open_input}" != "${recommended_open_pages}" ] \
    || [ "${current_closed_input}" != "${recommended_closed_pages}" ] \
    || [ "${current_open_resolve}" != "${recommended_open_pages}" ] \
    || [ "${current_closed_resolve}" != "${recommended_closed_pages}" ]; then
    needs_update="true"
    drift_detected="true"
  fi

  workflow_needs_update+=("${needs_update}")

  echo "  Workflow: ${workflow_path}"
  echo "    Existing defaults: input(open=${current_open_input}, closed=${current_closed_input}) resolve(open=${current_open_resolve}, closed=${current_closed_resolve})"
  echo "    Updated defaults:  input(open=${updated_open_input}, closed=${updated_closed_input}) resolve(open=${updated_open_resolve}, closed=${updated_closed_resolve})"
done

if [ "${drift_detected}" != "true" ]; then
  echo "All readiness workflows already use the recommended page limits; no change required."
  for tmp_file in "${tmp_files[@]:-}"; do
    rm -f "${tmp_file}"
  done
  cleanup_summary_file
  exit 0
fi

if [ "${READINESS_THRESHOLD_APPLY_DRY_RUN}" = "true" ]; then
  echo "Dry run enabled; workflow files were not modified."
  if command -v diff >/dev/null 2>&1; then
    index=0
    for workflow_path in "${workflow_paths[@]}"; do
      if [ "${workflow_needs_update[$index]}" = "true" ]; then
        diff -u "${workflow_path}" "${tmp_files[$index]}" || true
      fi
      index=$((index + 1))
    done
  fi
else
  index=0
  for workflow_path in "${workflow_paths[@]}"; do
    if [ "${workflow_needs_update[$index]}" = "true" ]; then
      cp "${tmp_files[$index]}" "${workflow_path}"
    fi
    index=$((index + 1))
  done
  echo "Applied recommended readiness page limits."
fi

for tmp_file in "${tmp_files[@]:-}"; do
  rm -f "${tmp_file}"
done

cleanup_summary_file
