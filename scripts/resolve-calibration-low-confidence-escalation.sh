#!/bin/bash
# Resolves calibration low-confidence escalation status from consecutive scheduled-run history.

set -euo pipefail

CALIBRATION_ESCALATION_KIND="${CALIBRATION_ESCALATION_KIND:-}"
CALIBRATION_LOW_CONFIDENCE_TRIGGERED="${CALIBRATION_LOW_CONFIDENCE_TRIGGERED:-false}"
CALIBRATION_LOW_CONFIDENCE_REASON="${CALIBRATION_LOW_CONFIDENCE_REASON:-}"
CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD="${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD:-3}"
CALIBRATION_LOW_CONFIDENCE_HISTORY_LOOKBACK_RUNS="${CALIBRATION_LOW_CONFIDENCE_HISTORY_LOOKBACK_RUNS:-10}"
CALIBRATION_ESCALATION_EVENT_NAME="${CALIBRATION_ESCALATION_EVENT_NAME:-${GITHUB_EVENT_NAME:-}}"
CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE="${CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE:-false}"
CALIBRATION_ESCALATION_DRY_RUN="${CALIBRATION_ESCALATION_DRY_RUN:-false}"
CALIBRATION_ESCALATION_HISTORY_FILE="${CALIBRATION_ESCALATION_HISTORY_FILE:-}"
CALIBRATION_ESCALATION_HISTORY_JSON="${CALIBRATION_ESCALATION_HISTORY_JSON:-}"
CALIBRATION_ESCALATION_WORKFLOW_FILE="${CALIBRATION_ESCALATION_WORKFLOW_FILE:-}"
CALIBRATION_ESCALATION_ARTIFACT_NAME="${CALIBRATION_ESCALATION_ARTIFACT_NAME:-}"
CALIBRATION_ESCALATION_RESULT_FILE_BASENAME="${CALIBRATION_ESCALATION_RESULT_FILE_BASENAME:-}"
CALIBRATION_ESCALATION_GITHUB_REPOSITORY="${CALIBRATION_ESCALATION_GITHUB_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

EVENT_ELIGIBLE="false"
ESCALATION_KIND=""
ESCALATION_STATUS="skip_event"
ESCALATION_NEEDED="false"
HISTORY_SOURCE="none"
HISTORY_RUNS_CHECKED="0"
PREVIOUS_LOW_CONFIDENCE_STREAK="0"
CURRENT_LOW_CONFIDENCE_STREAK="0"
TMP_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/resolve-calibration-low-confidence-escalation.sh

Environment:
  CALIBRATION_ESCALATION_KIND                     Required: warmup_threshold|readiness_page_limit
  CALIBRATION_LOW_CONFIDENCE_TRIGGERED            Optional true|false, default false
  CALIBRATION_LOW_CONFIDENCE_REASON               Optional reason text
  CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD     Optional integer >=1, default 3
  CALIBRATION_LOW_CONFIDENCE_HISTORY_LOOKBACK_RUNS Optional integer >=1, default 10
  CALIBRATION_ESCALATION_EVENT_NAME               Optional event name, defaults to GITHUB_EVENT_NAME
  CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE       Optional true|false, default false
  CALIBRATION_ESCALATION_DRY_RUN                  Optional true|false, default false

History source (mutually exclusive):
  CALIBRATION_ESCALATION_HISTORY_FILE             Optional fixture JSON file (array, most-recent first)
  CALIBRATION_ESCALATION_HISTORY_JSON             Optional fixture JSON payload

Live history source (used when no fixture source is provided):
  CALIBRATION_ESCALATION_WORKFLOW_FILE            Optional workflow file name override
  CALIBRATION_ESCALATION_ARTIFACT_NAME            Optional artifact name override
  CALIBRATION_ESCALATION_RESULT_FILE_BASENAME     Optional result filename override
  CALIBRATION_ESCALATION_GITHUB_REPOSITORY        Optional owner/repo override
  GH_TOKEN                                        Required for live GitHub API history lookup

Outputs:
  escalation_kind
  escalation_status                                failure|recovered|below_threshold|skip_event
  escalation_needed                                true when status is failure or recovered
  event_eligible                                   true|false
  history_source                                   fixture|github|none
  history_runs_checked                             prior runs evaluated for streak
  previous_low_confidence_streak                   consecutive prior low-confidence runs
  current_low_confidence_streak                    prior streak + current run when triggered
  low_confidence_streak_threshold
  low_confidence_reason
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

configure_kind_defaults() {
  case "${CALIBRATION_ESCALATION_KIND}" in
    warmup_threshold)
      ESCALATION_KIND="warmup_threshold_calibration"
      if [ -z "${CALIBRATION_ESCALATION_WORKFLOW_FILE}" ]; then
        CALIBRATION_ESCALATION_WORKFLOW_FILE="warmup-threshold-calibration.yml"
      fi
      if [ -z "${CALIBRATION_ESCALATION_ARTIFACT_NAME}" ]; then
        CALIBRATION_ESCALATION_ARTIFACT_NAME="warmup-threshold-calibration"
      fi
      if [ -z "${CALIBRATION_ESCALATION_RESULT_FILE_BASENAME}" ]; then
        CALIBRATION_ESCALATION_RESULT_FILE_BASENAME="warmup-threshold-calibration-result.json"
      fi
      ;;
    readiness_page_limit)
      ESCALATION_KIND="readiness_page_limit_calibration"
      if [ -z "${CALIBRATION_ESCALATION_WORKFLOW_FILE}" ]; then
        CALIBRATION_ESCALATION_WORKFLOW_FILE="readiness-page-limit-calibration.yml"
      fi
      if [ -z "${CALIBRATION_ESCALATION_ARTIFACT_NAME}" ]; then
        CALIBRATION_ESCALATION_ARTIFACT_NAME="readiness-page-limit-calibration"
      fi
      if [ -z "${CALIBRATION_ESCALATION_RESULT_FILE_BASENAME}" ]; then
        CALIBRATION_ESCALATION_RESULT_FILE_BASENAME="readiness-page-limit-calibration-result.json"
      fi
      ;;
    *)
      echo "Error: CALIBRATION_ESCALATION_KIND must be warmup_threshold or readiness_page_limit."
      exit 1
      ;;
  esac
}

resolve_event_eligibility() {
  if [ "${CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE}" = "true" ]; then
    EVENT_ELIGIBLE="true"
    return
  fi

  if [ "${CALIBRATION_ESCALATION_EVENT_NAME}" = "schedule" ]; then
    EVENT_ELIGIBLE="true"
  else
    EVENT_ELIGIBLE="false"
  fi
}

load_fixture_history_payload() {
  if [ -n "${CALIBRATION_ESCALATION_HISTORY_FILE}" ] && [ -n "${CALIBRATION_ESCALATION_HISTORY_JSON}" ]; then
    echo "Error: set only one of CALIBRATION_ESCALATION_HISTORY_FILE or CALIBRATION_ESCALATION_HISTORY_JSON."
    exit 1
  fi

  if [ -n "${CALIBRATION_ESCALATION_HISTORY_FILE}" ]; then
    if [ "${CALIBRATION_ESCALATION_HISTORY_FILE}" = "-" ]; then
      cat
      return
    fi

    if [ ! -r "${CALIBRATION_ESCALATION_HISTORY_FILE}" ]; then
      echo "Error: CALIBRATION_ESCALATION_HISTORY_FILE is not readable: ${CALIBRATION_ESCALATION_HISTORY_FILE}"
      exit 1
    fi

    cat "${CALIBRATION_ESCALATION_HISTORY_FILE}"
    return
  fi

  if [ -n "${CALIBRATION_ESCALATION_HISTORY_JSON}" ]; then
    printf '%s' "${CALIBRATION_ESCALATION_HISTORY_JSON}"
    return
  fi

  printf '%s' ""
}

count_streak_from_history_payload() {
  local payload="$1"
  local parsed_flags=""
  local streak=0
  local checked=0
  local flag

  if ! parsed_flags="$(
    printf '%s\n' "${payload}" | jq -r '
      if type != "array" then
        error("history payload must be a JSON array")
      else
        .[]
        | (
            if type == "boolean" then
              .
            elif type == "object" then
              (.low_confidence_guard_triggered // .low_confidence // false)
            else
              false
            end
          )
        | if . then "true" else "false" end
      end
    ' 2>/dev/null
  )"; then
    echo "Error: calibration low-confidence history payload must be a JSON array."
    exit 1
  fi

  while IFS= read -r flag; do
    [ -z "${flag}" ] && continue
    checked=$((checked + 1))
    if [ "${flag}" = "true" ]; then
      streak=$((streak + 1))
    else
      break
    fi
  done <<< "${parsed_flags}"

  PREVIOUS_LOW_CONFIDENCE_STREAK="${streak}"
  HISTORY_RUNS_CHECKED="${checked}"
}

lookup_artifact_low_confidence_flag() {
  local run_id="$1"
  local artifacts_payload=""
  local artifact_id=""
  local artifact_zip=""
  local artifact_extract_dir=""
  local result_file=""
  local low_confidence_flag=""

  artifacts_payload="$(
    GH_TOKEN="${GH_TOKEN}" gh api \
      "repos/${CALIBRATION_ESCALATION_GITHUB_REPOSITORY}/actions/runs/${run_id}/artifacts?per_page=100"
  )"

  if ! printf '%s\n' "${artifacts_payload}" | jq -e 'type == "object" and (.artifacts | type == "array")' >/dev/null; then
    return 1
  fi

  artifact_id="$(
    printf '%s\n' "${artifacts_payload}" | jq -r \
      --arg artifact_name "${CALIBRATION_ESCALATION_ARTIFACT_NAME}" '
        .artifacts
        | map(select(.expired == false and .name == $artifact_name))
        | sort_by(.created_at) | reverse
        | .[0].id // empty
      '
  )"

  if [ -z "${artifact_id}" ]; then
    return 1
  fi

  artifact_zip="${TMP_ROOT}/artifact-${run_id}-${artifact_id}.zip"
  artifact_extract_dir="${TMP_ROOT}/artifact-${run_id}-${artifact_id}"
  mkdir -p "${artifact_extract_dir}"

  GH_TOKEN="${GH_TOKEN}" gh api \
    "repos/${CALIBRATION_ESCALATION_GITHUB_REPOSITORY}/actions/artifacts/${artifact_id}/zip" > "${artifact_zip}"
  unzip -qq -o "${artifact_zip}" -d "${artifact_extract_dir}"

  result_file="$(find "${artifact_extract_dir}" -type f -name "${CALIBRATION_ESCALATION_RESULT_FILE_BASENAME}" | head -n 1)"
  if [ -z "${result_file}" ]; then
    return 1
  fi

  low_confidence_flag="$(
    jq -r 'if (.low_confidence_guard_triggered // false) then "true" else "false" end' "${result_file}" 2>/dev/null || true
  )"
  if [ -z "${low_confidence_flag}" ]; then
    return 1
  fi

  printf '%s' "${low_confidence_flag}"
}

count_streak_from_github_history() {
  local runs_payload=""
  local run_id=""
  local low_confidence_flag=""
  local streak=0
  local checked=0

  if [ -z "${GH_TOKEN}" ]; then
    echo "Error: GH_TOKEN (or GITHUB_TOKEN) is required for live history lookup."
    exit 1
  fi

  if [ -z "${CALIBRATION_ESCALATION_GITHUB_REPOSITORY}" ]; then
    echo "Error: CALIBRATION_ESCALATION_GITHUB_REPOSITORY (or GITHUB_REPOSITORY) is required for live history lookup."
    exit 1
  fi

  runs_payload="$(
    GH_TOKEN="${GH_TOKEN}" gh api \
      "repos/${CALIBRATION_ESCALATION_GITHUB_REPOSITORY}/actions/workflows/${CALIBRATION_ESCALATION_WORKFLOW_FILE}/runs?event=schedule&status=completed&per_page=${CALIBRATION_LOW_CONFIDENCE_HISTORY_LOOKBACK_RUNS}"
  )"

  if ! printf '%s\n' "${runs_payload}" | jq -e 'type == "object" and (.workflow_runs | type == "array")' >/dev/null; then
    echo "Error: unexpected workflow runs payload shape while resolving low-confidence history."
    exit 1
  fi

  while IFS= read -r run_id; do
    [ -z "${run_id}" ] && continue
    low_confidence_flag="$(lookup_artifact_low_confidence_flag "${run_id}" || true)"
    if [ -z "${low_confidence_flag}" ]; then
      break
    fi

    checked=$((checked + 1))
    if [ "${low_confidence_flag}" = "true" ]; then
      streak=$((streak + 1))
    else
      break
    fi
  done < <(printf '%s\n' "${runs_payload}" | jq -r '.workflow_runs[].id')

  PREVIOUS_LOW_CONFIDENCE_STREAK="${streak}"
  HISTORY_RUNS_CHECKED="${checked}"
}

write_outputs() {
  write_output "escalation_kind" "${ESCALATION_KIND}"
  write_output "escalation_status" "${ESCALATION_STATUS}"
  write_output "escalation_needed" "${ESCALATION_NEEDED}"
  write_output "event_eligible" "${EVENT_ELIGIBLE}"
  write_output "history_source" "${HISTORY_SOURCE}"
  write_output "history_runs_checked" "${HISTORY_RUNS_CHECKED}"
  write_output "previous_low_confidence_streak" "${PREVIOUS_LOW_CONFIDENCE_STREAK}"
  write_output "current_low_confidence_streak" "${CURRENT_LOW_CONFIDENCE_STREAK}"
  write_output "low_confidence_streak_threshold" "${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD}"
  write_output "low_confidence_reason" "${CALIBRATION_LOW_CONFIDENCE_REASON}"
  write_output "workflow_file" "${CALIBRATION_ESCALATION_WORKFLOW_FILE}"
  write_output "artifact_name" "${CALIBRATION_ESCALATION_ARTIFACT_NAME}"
  write_output "result_file_basename" "${CALIBRATION_ESCALATION_RESULT_FILE_BASENAME}"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_dependency "jq"
ensure_boolean "CALIBRATION_LOW_CONFIDENCE_TRIGGERED" "${CALIBRATION_LOW_CONFIDENCE_TRIGGERED}"
ensure_boolean "CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE" "${CALIBRATION_ESCALATION_ALLOW_NON_SCHEDULE}"
ensure_boolean "CALIBRATION_ESCALATION_DRY_RUN" "${CALIBRATION_ESCALATION_DRY_RUN}"
validate_positive_integer "CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD" "${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD}"
validate_positive_integer "CALIBRATION_LOW_CONFIDENCE_HISTORY_LOOKBACK_RUNS" "${CALIBRATION_LOW_CONFIDENCE_HISTORY_LOOKBACK_RUNS}"

configure_kind_defaults
resolve_event_eligibility

if [ -z "${CALIBRATION_LOW_CONFIDENCE_REASON}" ]; then
  CALIBRATION_LOW_CONFIDENCE_REASON="Low-confidence recommendation triggered by confidence guard."
fi

if [ "${CALIBRATION_LOW_CONFIDENCE_TRIGGERED}" = "true" ] && [ "${EVENT_ELIGIBLE}" = "true" ]; then
  fixture_payload="$(load_fixture_history_payload)"
  if [ -n "${fixture_payload}" ]; then
    HISTORY_SOURCE="fixture"
    count_streak_from_history_payload "${fixture_payload}"
  elif [ "${CALIBRATION_ESCALATION_DRY_RUN}" = "true" ]; then
    HISTORY_SOURCE="none"
    PREVIOUS_LOW_CONFIDENCE_STREAK="0"
    HISTORY_RUNS_CHECKED="0"
  else
    HISTORY_SOURCE="github"
    require_dependency "gh"
    require_dependency "unzip"
    require_dependency "find"
    require_dependency "mktemp"
    TMP_ROOT="$(mktemp -d)"
    trap 'rm -rf "${TMP_ROOT}"' EXIT
    count_streak_from_github_history
  fi
fi

if [ "${CALIBRATION_LOW_CONFIDENCE_TRIGGERED}" = "true" ]; then
  CURRENT_LOW_CONFIDENCE_STREAK="$((PREVIOUS_LOW_CONFIDENCE_STREAK + 1))"
else
  CURRENT_LOW_CONFIDENCE_STREAK="0"
fi

if [ "${EVENT_ELIGIBLE}" != "true" ]; then
  ESCALATION_STATUS="skip_event"
  ESCALATION_NEEDED="false"
elif [ "${CALIBRATION_LOW_CONFIDENCE_TRIGGERED}" = "true" ]; then
  if [ "${CURRENT_LOW_CONFIDENCE_STREAK}" -ge "${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD}" ]; then
    ESCALATION_STATUS="failure"
    ESCALATION_NEEDED="true"
  else
    ESCALATION_STATUS="below_threshold"
    ESCALATION_NEEDED="false"
  fi
else
  ESCALATION_STATUS="recovered"
  ESCALATION_NEEDED="true"
fi

write_outputs

echo "Calibration low-confidence escalation resolution"
echo "  Kind: ${CALIBRATION_ESCALATION_KIND}"
echo "  Escalation kind: ${ESCALATION_KIND}"
echo "  Event: ${CALIBRATION_ESCALATION_EVENT_NAME:-unknown}"
echo "  Event eligible: ${EVENT_ELIGIBLE}"
echo "  Low-confidence triggered: ${CALIBRATION_LOW_CONFIDENCE_TRIGGERED}"
echo "  History source: ${HISTORY_SOURCE}"
echo "  History runs checked: ${HISTORY_RUNS_CHECKED}"
echo "  Previous low-confidence streak: ${PREVIOUS_LOW_CONFIDENCE_STREAK}"
echo "  Current low-confidence streak: ${CURRENT_LOW_CONFIDENCE_STREAK}"
echo "  Streak threshold: ${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD}"
echo "  Escalation status: ${ESCALATION_STATUS}"
echo "  Escalation needed: ${ESCALATION_NEEDED}"
