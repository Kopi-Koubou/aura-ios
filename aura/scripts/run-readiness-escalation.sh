#!/bin/bash
# Handles readiness gate escalation and recovery with optional webhook alert and GitHub issue upsert/close.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

READINESS_ESCALATION_KIND="${READINESS_ESCALATION_KIND:-}"
READINESS_ESCALATION_STATUS="${READINESS_ESCALATION_STATUS:-failure}"
READINESS_LOG_FILE="${READINESS_LOG_FILE:-}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
READINESS_ESCALATION_DRY_RUN="${READINESS_ESCALATION_DRY_RUN:-false}"
READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS="${READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS:-false}"
READINESS_ESCALATION_DRY_WEBHOOK_RESULT="${READINESS_ESCALATION_DRY_WEBHOOK_RESULT:-success}"
READINESS_ESCALATION_OPEN_ISSUES_FILE="${READINESS_ESCALATION_OPEN_ISSUES_FILE:-}"
READINESS_ESCALATION_OPEN_ISSUES_JSON="${READINESS_ESCALATION_OPEN_ISSUES_JSON:-}"
READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES="${READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES:-10}"
READINESS_ESCALATION_CLOSED_ISSUES_FILE="${READINESS_ESCALATION_CLOSED_ISSUES_FILE:-}"
READINESS_ESCALATION_CLOSED_ISSUES_JSON="${READINESS_ESCALATION_CLOSED_ISSUES_JSON:-}"
READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES="${READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES:-10}"
READINESS_ESCALATION_METRICS_FILE="${READINESS_ESCALATION_METRICS_FILE:-}"

ISSUE_TITLE=""
ISSUE_OPENING_LINE=""
SETTINGS_BLOCK=""
WEBHOOK_TEXT_TEMPLATE=""
RUN_URL=""
SUPABASE_TARGET=""
ISSUE_BODY=""
RECOVERY_COMMENT=""
OPEN_ISSUES_PAYLOAD="[]"
CLOSED_ISSUES_PAYLOAD="[]"
ISSUE_ACTION=""
ISSUE_NUMBER=""
ISSUE_TRACKING_LABEL="ops-readiness"
ISSUE_KIND_LABEL=""
ISSUE_LABELS_JSON="[]"
ISSUE_MARKER=""
ISSUE_LEGACY_BODY_PREFIX=""

GH_HTTP_STATUS=""
GH_RESPONSE_BODY=""
OPEN_PAGES_SCANNED=0
OPEN_MATCH_PAGE=0
CLOSED_PAGES_SCANNED=0
CLOSED_MATCH_PAGE=0
MATCHED_OPEN_ISSUE_NUMBER=""
MATCHED_CLOSED_ISSUE_NUMBER=""

usage() {
  cat <<'EOF'
Usage:
  READINESS_ESCALATION_KIND=<auth_fallback|cache_degradation|warmup_threshold_calibration|readiness_page_limit_calibration> \
  READINESS_ESCALATION_STATUS=<failure|recovered> \
  READINESS_LOG_FILE=<path-to-readiness-log> \
  ALERT_WEBHOOK_URL=<optional-webhook-url> \
  bash ./scripts/run-readiness-escalation.sh

Environment:
  READINESS_ESCALATION_KIND                Required:
                                           auth_fallback|cache_degradation|
                                           warmup_threshold_calibration|readiness_page_limit_calibration
  READINESS_ESCALATION_STATUS              Optional: failure|recovered (default failure)
  READINESS_LOG_FILE                       Optional: log file used for issue log tail
  ALERT_WEBHOOK_URL                        Optional: webhook URL for failure alerts
  READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS  Optional: true|false (default false)
  READINESS_ESCALATION_DRY_RUN             Optional: true|false (default false)
  READINESS_ESCALATION_DRY_WEBHOOK_RESULT  Optional (dry-run only): success|failure
  READINESS_ESCALATION_OPEN_ISSUES_FILE    Optional (dry-run only): fixture JSON file
  READINESS_ESCALATION_OPEN_ISSUES_JSON    Optional (dry-run only): fixture JSON payload
  READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES Optional (live mode): max open-issue pages to scan (default 10)
  READINESS_ESCALATION_CLOSED_ISSUES_FILE  Optional (dry-run only): closed issue fixture JSON file
  READINESS_ESCALATION_CLOSED_ISSUES_JSON  Optional (dry-run only): closed issue fixture JSON payload
  READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES Optional (live mode): max closed-issue pages to scan (default 10)
  READINESS_ESCALATION_METRICS_FILE        Optional: write structured escalation metrics JSON to this path
  READINESS_RUN_URL                        Optional: explicit workflow run URL

GitHub API inputs for live mode:
  GITHUB_TOKEN
  GITHUB_REPOSITORY                        owner/repo
  GITHUB_SERVER_URL                        Used to build run URL
  GITHUB_RUN_ID                            Used to build run URL
  GITHUB_API_URL                           Optional, defaults to https://api.github.com
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo -e "${RED}Error: ${command_name} is required.${NC}"
    exit 1
  fi
}

ensure_boolean() {
  local var_name="$1"
  local value="$2"
  if [ "${value}" != "true" ] && [ "${value}" != "false" ]; then
    echo -e "${RED}Error: ${var_name} must be true or false.${NC}"
    exit 1
  fi
}

ensure_escalation_status() {
  local value="$1"
  if [ "${value}" != "failure" ] && [ "${value}" != "recovered" ]; then
    echo -e "${RED}Error: READINESS_ESCALATION_STATUS must be failure or recovered.${NC}"
    exit 1
  fi
}

ensure_positive_integer() {
  local var_name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo -e "${RED}Error: ${var_name} must be a positive integer.${NC}"
    exit 1
  fi
}

print_snippet() {
  local text="$1"
  printf '%s' "${text}" | tr '\n' ' ' | cut -c1-320
}

resolve_run_url() {
  if [ -n "${READINESS_RUN_URL:-}" ]; then
    printf '%s' "${READINESS_RUN_URL}"
    return
  fi

  if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
    printf '%s/%s/actions/runs/%s' "${GITHUB_SERVER_URL%/}" "${GITHUB_REPOSITORY}" "${GITHUB_RUN_ID}"
    return
  fi

  printf '%s' "unknown"
}

load_open_issues_fixture() {
  if [ -n "${READINESS_ESCALATION_OPEN_ISSUES_FILE}" ] && [ -n "${READINESS_ESCALATION_OPEN_ISSUES_JSON}" ]; then
    echo -e "${RED}Error: set only one of READINESS_ESCALATION_OPEN_ISSUES_FILE or READINESS_ESCALATION_OPEN_ISSUES_JSON.${NC}"
    exit 1
  fi

  if [ -n "${READINESS_ESCALATION_OPEN_ISSUES_FILE}" ]; then
    if [ "${READINESS_ESCALATION_OPEN_ISSUES_FILE}" = "-" ]; then
      OPEN_ISSUES_PAYLOAD="$(cat)"
    elif [ -r "${READINESS_ESCALATION_OPEN_ISSUES_FILE}" ]; then
      OPEN_ISSUES_PAYLOAD="$(cat "${READINESS_ESCALATION_OPEN_ISSUES_FILE}")"
    else
      echo -e "${RED}Error: READINESS_ESCALATION_OPEN_ISSUES_FILE is not readable: ${READINESS_ESCALATION_OPEN_ISSUES_FILE}.${NC}"
      exit 1
    fi
  elif [ -n "${READINESS_ESCALATION_OPEN_ISSUES_JSON}" ]; then
    OPEN_ISSUES_PAYLOAD="${READINESS_ESCALATION_OPEN_ISSUES_JSON}"
  else
    OPEN_ISSUES_PAYLOAD="[]"
  fi

  if ! printf '%s\n' "${OPEN_ISSUES_PAYLOAD}" | jq -e 'type == "array"' >/dev/null; then
    echo -e "${RED}Error: open issue fixture payload must be a JSON array.${NC}"
    exit 1
  fi
}

load_closed_issues_fixture() {
  if [ -n "${READINESS_ESCALATION_CLOSED_ISSUES_FILE}" ] && [ -n "${READINESS_ESCALATION_CLOSED_ISSUES_JSON}" ]; then
    echo -e "${RED}Error: set only one of READINESS_ESCALATION_CLOSED_ISSUES_FILE or READINESS_ESCALATION_CLOSED_ISSUES_JSON.${NC}"
    exit 1
  fi

  if [ -n "${READINESS_ESCALATION_CLOSED_ISSUES_FILE}" ]; then
    if [ "${READINESS_ESCALATION_CLOSED_ISSUES_FILE}" = "-" ]; then
      CLOSED_ISSUES_PAYLOAD="$(cat)"
    elif [ -r "${READINESS_ESCALATION_CLOSED_ISSUES_FILE}" ]; then
      CLOSED_ISSUES_PAYLOAD="$(cat "${READINESS_ESCALATION_CLOSED_ISSUES_FILE}")"
    else
      echo -e "${RED}Error: READINESS_ESCALATION_CLOSED_ISSUES_FILE is not readable: ${READINESS_ESCALATION_CLOSED_ISSUES_FILE}.${NC}"
      exit 1
    fi
  elif [ -n "${READINESS_ESCALATION_CLOSED_ISSUES_JSON}" ]; then
    CLOSED_ISSUES_PAYLOAD="${READINESS_ESCALATION_CLOSED_ISSUES_JSON}"
  else
    CLOSED_ISSUES_PAYLOAD="[]"
  fi

  if ! printf '%s\n' "${CLOSED_ISSUES_PAYLOAD}" | jq -e 'type == "array"' >/dev/null; then
    echo -e "${RED}Error: closed issue fixture payload must be a JSON array.${NC}"
    exit 1
  fi
}

load_log_tail() {
  local log_tail=""
  if [ -n "${READINESS_LOG_FILE}" ] && [ -f "${READINESS_LOG_FILE}" ]; then
    log_tail="$(tail -n 80 "${READINESS_LOG_FILE}")"
  else
    log_tail="No log file captured."
  fi

  if [ "${#log_tail}" -gt 6000 ]; then
    log_tail="$(printf '%s' "${log_tail}" | tail -c 6000)"
  fi

  printf '%s' "${log_tail}"
}

github_api_request() {
  local method="$1"
  local api_path="$2"
  local payload="${3:-}"
  local api_url="${GITHUB_API_URL:-https://api.github.com}${api_path}"
  local response=""

  if [ -n "${payload}" ]; then
    response="$(curl -sS -w $'\n%{http_code}' \
      -X "${method}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      "${api_url}" \
      -d "${payload}")"
  else
    response="$(curl -sS -w $'\n%{http_code}' \
      -X "${method}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api_url}")"
  fi

  GH_HTTP_STATUS="${response##*$'\n'}"
  GH_RESPONSE_BODY="${response%$'\n'*}"
}

configure_kind() {
  case "${READINESS_ESCALATION_KIND}" in
    auth_fallback)
      ISSUE_TITLE="Auth fallback readiness gate failing"
      ISSUE_OPENING_LINE="Automated auth fallback readiness gate failed on $(date -u +%F)."
      ISSUE_LEGACY_BODY_PREFIX="Automated auth fallback readiness gate failed on "
      ISSUE_KIND_LABEL="ops-readiness-auth-fallback"
      ISSUE_LABELS_JSON='["ops-readiness","ops-readiness-auth-fallback"]'
      ISSUE_MARKER="<!-- aura-readiness-escalation:auth_fallback -->"
      SETTINGS_BLOCK="$(printf '%s\n' \
        "- Lookback days: ${LOOKBACK_DAYS:-2}" \
        "- Max fallbacks: ${MAX_FALLBACKS:-0}" \
        "- Context filter: ${AUTH_CONTEXT_FILTER:-all}")"
      WEBHOOK_TEXT_TEMPLATE="[Aura] Auth fallback readiness check failed for %s. Run: %s"
      ;;
    cache_degradation)
      ISSUE_TITLE="Shared cache degradation readiness gate failing"
      ISSUE_OPENING_LINE="Automated shared cache degradation readiness gate failed on $(date -u +%F)."
      ISSUE_LEGACY_BODY_PREFIX="Automated shared cache degradation readiness gate failed on "
      ISSUE_KIND_LABEL="ops-readiness-cache-degradation"
      ISSUE_LABELS_JSON='["ops-readiness","ops-readiness-cache-degradation"]'
      ISSUE_MARKER="<!-- aura-readiness-escalation:cache_degradation -->"
      SETTINGS_BLOCK="$(printf '%s\n' \
        "- Lookback days: ${LOOKBACK_DAYS:-2}" \
        "- Max degradations: ${MAX_DEGRADATIONS:-0}" \
        "- Premium filter: ${PREMIUM_FILTER:-all}" \
        "- Reason filter: ${REASON_FILTER:-all}")"
      WEBHOOK_TEXT_TEMPLATE="[Aura] Shared cache degradation readiness check failed for %s. Run: %s"
      ;;
    warmup_threshold_calibration)
      ISSUE_TITLE="Warmup threshold calibration low-confidence streak"
      ISSUE_OPENING_LINE="Automated warmup threshold calibration remained low-confidence on $(date -u +%F)."
      ISSUE_LEGACY_BODY_PREFIX="Automated warmup threshold calibration remained low-confidence on "
      ISSUE_KIND_LABEL="ops-calibration-warmup-threshold"
      ISSUE_LABELS_JSON='["ops-calibration","ops-calibration-warmup-threshold"]'
      ISSUE_MARKER="<!-- aura-calibration-escalation:warmup_threshold -->"
      SETTINGS_BLOCK="$(printf '%s\n' \
        "- Workflow file: ${CALIBRATION_WORKFLOW_FILE:-warmup-threshold-calibration.yml}" \
        "- Event name: ${CALIBRATION_ESCALATION_EVENT_NAME:-unknown}" \
        "- Streak threshold: ${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD:-3}" \
        "- Observed streak: ${CALIBRATION_CURRENT_LOW_CONFIDENCE_STREAK:-0}" \
        "- Low-confidence reason: ${CALIBRATION_LOW_CONFIDENCE_REASON:-unknown}" \
        "- Fail on low confidence: ${CALIBRATION_FAIL_ON_LOW_CONFIDENCE:-false}")"
      WEBHOOK_TEXT_TEMPLATE="[Aura] Warmup threshold calibration low-confidence streak for %s. Run: %s"
      ;;
    readiness_page_limit_calibration)
      ISSUE_TITLE="Readiness page-limit calibration low-confidence streak"
      ISSUE_OPENING_LINE="Automated readiness page-limit calibration remained low-confidence on $(date -u +%F)."
      ISSUE_LEGACY_BODY_PREFIX="Automated readiness page-limit calibration remained low-confidence on "
      ISSUE_KIND_LABEL="ops-calibration-readiness-page-limit"
      ISSUE_LABELS_JSON='["ops-calibration","ops-calibration-readiness-page-limit"]'
      ISSUE_MARKER="<!-- aura-calibration-escalation:readiness_page_limit -->"
      SETTINGS_BLOCK="$(printf '%s\n' \
        "- Workflow file: ${CALIBRATION_WORKFLOW_FILE:-readiness-page-limit-calibration.yml}" \
        "- Event name: ${CALIBRATION_ESCALATION_EVENT_NAME:-unknown}" \
        "- Streak threshold: ${CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD:-3}" \
        "- Observed streak: ${CALIBRATION_CURRENT_LOW_CONFIDENCE_STREAK:-0}" \
        "- Low-confidence reason: ${CALIBRATION_LOW_CONFIDENCE_REASON:-unknown}" \
        "- Fail on low confidence: ${CALIBRATION_FAIL_ON_LOW_CONFIDENCE:-false}")"
      WEBHOOK_TEXT_TEMPLATE="[Aura] Readiness page-limit calibration low-confidence streak for %s. Run: %s"
      ;;
    *)
      echo -e "${RED}Error: READINESS_ESCALATION_KIND must be auth_fallback, cache_degradation, warmup_threshold_calibration, or readiness_page_limit_calibration.${NC}"
      exit 1
      ;;
  esac
}

build_issue_body() {
  local log_tail="$1"
  ISSUE_BODY="$(printf '%s\n%s\n\n%s\n%s\n- Supabase target: %s\n\n<details><summary>Log tail</summary>\n\n```text\n%s\n```\n</details>\n' \
    "${ISSUE_MARKER}" \
    "${ISSUE_OPENING_LINE}" \
    "- Workflow run: ${RUN_URL}" \
    "${SETTINGS_BLOCK}" \
    "${SUPABASE_TARGET}" \
    "${log_tail}")"
}

build_recovery_comment() {
  RECOVERY_COMMENT="$(printf '%s\n\n%s\n%s\n- Supabase target: %s\n' \
    "Readiness gate recovered on $(date -u +%F); closing this incident." \
    "- Workflow run: ${RUN_URL}" \
    "${SETTINGS_BLOCK}" \
    "${SUPABASE_TARGET}")"
}

write_github_output() {
  local webhook_attempted="$1"
  local webhook_success="$2"
  local issue_action="$3"
  local issue_number="$4"
  local open_pages_scanned="$5"
  local open_match_page="$6"
  local closed_pages_scanned="$7"
  local closed_match_page="$8"

  if [ -z "${GITHUB_OUTPUT:-}" ]; then
    return
  fi

  {
    echo "webhook_attempted=${webhook_attempted}"
    echo "webhook_success=${webhook_success}"
    echo "issue_action=${issue_action}"
    echo "issue_number=${issue_number}"
    echo "open_pages_scanned=${open_pages_scanned}"
    echo "open_match_page=${open_match_page}"
    echo "closed_pages_scanned=${closed_pages_scanned}"
    echo "closed_match_page=${closed_match_page}"
  } >> "${GITHUB_OUTPUT}"
}

write_metrics_file() {
  local webhook_attempted="$1"
  local webhook_success="$2"
  local issue_action="$3"
  local issue_number="$4"
  local strict_webhook_requirement_failed="$5"
  local metrics_file="${READINESS_ESCALATION_METRICS_FILE:-}"
  local issue_number_json="null"
  local open_scan_hit_page_limit="false"
  local closed_scan_hit_page_limit="false"

  if [ -z "${metrics_file}" ]; then
    return
  fi

  if [[ "${issue_number}" =~ ^[0-9]+$ ]]; then
    issue_number_json="${issue_number}"
  fi

  if [ "${OPEN_MATCH_PAGE}" -eq 0 ] && [ "${OPEN_PAGES_SCANNED}" -ge "${READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES}" ]; then
    open_scan_hit_page_limit="true"
  fi

  if [ "${CLOSED_MATCH_PAGE}" -eq 0 ] && [ "${CLOSED_PAGES_SCANNED}" -ge "${READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES}" ]; then
    closed_scan_hit_page_limit="true"
  fi

  mkdir -p "$(dirname "${metrics_file}")"

  jq -n \
    --arg generated_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg kind "${READINESS_ESCALATION_KIND}" \
    --arg status "${READINESS_ESCALATION_STATUS}" \
    --arg run_url "${RUN_URL}" \
    --arg supabase_target "${SUPABASE_TARGET}" \
    --arg issue_action "${issue_action}" \
    --arg issue_number_raw "${issue_number}" \
    --argjson issue_number "${issue_number_json}" \
    --argjson dry_run "$( [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ] && echo true || echo false )" \
    --argjson webhook_attempted "$( [ "${webhook_attempted}" = "true" ] && echo true || echo false )" \
    --argjson webhook_success "$( [ "${webhook_success}" = "true" ] && echo true || echo false )" \
    --argjson strict_webhook_required "$( [ "${READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS}" = "true" ] && echo true || echo false )" \
    --argjson strict_webhook_requirement_failed "$( [ "${strict_webhook_requirement_failed}" = "true" ] && echo true || echo false )" \
    --argjson open_issues_max_pages "${READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES}" \
    --argjson open_pages_scanned "${OPEN_PAGES_SCANNED}" \
    --argjson open_match_page "${OPEN_MATCH_PAGE}" \
    --argjson open_scan_hit_page_limit "$( [ "${open_scan_hit_page_limit}" = "true" ] && echo true || echo false )" \
    --argjson closed_issues_max_pages "${READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES}" \
    --argjson closed_pages_scanned "${CLOSED_PAGES_SCANNED}" \
    --argjson closed_match_page "${CLOSED_MATCH_PAGE}" \
    --argjson closed_scan_hit_page_limit "$( [ "${closed_scan_hit_page_limit}" = "true" ] && echo true || echo false )" \
    '{
      generated_at_utc: $generated_at_utc,
      kind: $kind,
      status: $status,
      dry_run: $dry_run,
      run_url: $run_url,
      supabase_target: $supabase_target,
      issue_action: $issue_action,
      issue_number: $issue_number,
      issue_number_raw: $issue_number_raw,
      webhook_attempted: $webhook_attempted,
      webhook_success: $webhook_success,
      strict_webhook_required: $strict_webhook_required,
      strict_webhook_requirement_failed: $strict_webhook_requirement_failed,
      open_issues_max_pages: $open_issues_max_pages,
      open_pages_scanned: $open_pages_scanned,
      open_match_page: $open_match_page,
      open_scan_hit_page_limit: $open_scan_hit_page_limit,
      closed_issues_max_pages: $closed_issues_max_pages,
      closed_pages_scanned: $closed_pages_scanned,
      closed_match_page: $closed_match_page,
      closed_scan_hit_page_limit: $closed_scan_hit_page_limit
    }' > "${metrics_file}"

  echo "Metrics file:      ${metrics_file}"
}

ensure_issue_payload_array() {
  local payload_label="$1"
  local payload="$2"

  if ! printf '%s\n' "${payload}" | jq -e 'type == "array"' >/dev/null; then
    echo -e "${RED}Error: ${payload_label} must be a JSON array.${NC}" >&2
    printf '%s\n' "${payload}" >&2
    exit 1
  fi
}

find_matching_issue_number() {
  local payload="$1"
  printf '%s\n' "${payload}" | jq -r \
    --arg title "${ISSUE_TITLE}" \
    --arg tracking_label "${ISSUE_TRACKING_LABEL}" \
    --arg kind_label "${ISSUE_KIND_LABEL}" \
    --arg marker "${ISSUE_MARKER}" \
    --arg legacy_prefix "${ISSUE_LEGACY_BODY_PREFIX}" '
    def issue_labels: [(.labels // [])[] | .name];
    def issue_body: (.body // "");
    (
      [.[] | select((.pull_request // null) == null)
        | select((issue_labels | index($tracking_label)) and (issue_labels | index($kind_label)))
        | .number] | first
    ) // (
      [.[] | select((.pull_request // null) == null)
        | select((issue_body | contains($marker)) or (issue_body | startswith($legacy_prefix)))
        | .number] | first
    ) // (
      [.[] | select((.pull_request // null) == null and .title == $title) | .number] | first
    ) // empty
  '
}

find_matching_closed_issue_number_live() {
  local max_pages="$1"
  local page=1
  local page_payload="[]"
  MATCHED_CLOSED_ISSUE_NUMBER=""
  CLOSED_PAGES_SCANNED=0
  CLOSED_MATCH_PAGE=0

  while [ "${page}" -le "${max_pages}" ]; do
    github_api_request "GET" "/repos/${GITHUB_REPOSITORY}/issues?state=closed&per_page=100&page=${page}"
    if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
      echo -e "${RED}Failed to list closed issues page ${page} (HTTP ${GH_HTTP_STATUS}).${NC}" >&2
      echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")" >&2
      exit 1
    fi

    page_payload="${GH_RESPONSE_BODY}"
    ensure_issue_payload_array "closed issue payload (page ${page})" "${page_payload}"
    CLOSED_PAGES_SCANNED=$((CLOSED_PAGES_SCANNED + 1))

    if [ "$(printf '%s\n' "${page_payload}" | jq 'length')" -eq 0 ]; then
      break
    fi

    MATCHED_CLOSED_ISSUE_NUMBER="$(find_matching_issue_number "${page_payload}")"
    if [ -n "${MATCHED_CLOSED_ISSUE_NUMBER}" ]; then
      CLOSED_MATCH_PAGE="${page}"
      return
    fi

    page=$((page + 1))
  done
}

find_matching_open_issue_number_live() {
  local max_pages="$1"
  local page=1
  local page_payload="[]"
  MATCHED_OPEN_ISSUE_NUMBER=""
  OPEN_PAGES_SCANNED=0
  OPEN_MATCH_PAGE=0

  while [ "${page}" -le "${max_pages}" ]; do
    github_api_request "GET" "/repos/${GITHUB_REPOSITORY}/issues?state=open&per_page=100&page=${page}"
    if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
      echo -e "${RED}Failed to list open issues page ${page} (HTTP ${GH_HTTP_STATUS}).${NC}" >&2
      echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")" >&2
      exit 1
    fi

    page_payload="${GH_RESPONSE_BODY}"
    ensure_issue_payload_array "open issue payload (page ${page})" "${page_payload}"
    OPEN_PAGES_SCANNED=$((OPEN_PAGES_SCANNED + 1))

    if [ "$(printf '%s\n' "${page_payload}" | jq 'length')" -eq 0 ]; then
      break
    fi

    MATCHED_OPEN_ISSUE_NUMBER="$(find_matching_issue_number "${page_payload}")"
    if [ -n "${MATCHED_OPEN_ISSUE_NUMBER}" ]; then
      OPEN_MATCH_PAGE="${page}"
      return
    fi

    page=$((page + 1))
  done
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

ensure_boolean "READINESS_ESCALATION_DRY_RUN" "${READINESS_ESCALATION_DRY_RUN}"
ensure_boolean "READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS" "${READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS}"
ensure_escalation_status "${READINESS_ESCALATION_STATUS}"
ensure_positive_integer "READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES" "${READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES}"
ensure_positive_integer "READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES" "${READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES}"

if [ "${READINESS_ESCALATION_DRY_WEBHOOK_RESULT}" != "success" ] && [ "${READINESS_ESCALATION_DRY_WEBHOOK_RESULT}" != "failure" ]; then
  echo -e "${RED}Error: READINESS_ESCALATION_DRY_WEBHOOK_RESULT must be success or failure.${NC}"
  exit 1
fi

require_command "jq"
if [ "${READINESS_ESCALATION_DRY_RUN}" != "true" ]; then
  require_command "curl"
fi

configure_kind

RUN_URL="$(resolve_run_url)"
SUPABASE_TARGET="${SUPABASE_PROJECT_REF:-${SUPABASE_BASE_URL:-unknown}}"
LOG_TAIL="$(load_log_tail)"
if [ "${READINESS_ESCALATION_STATUS}" = "failure" ]; then
  build_issue_body "${LOG_TAIL}"
else
  build_recovery_comment
fi

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Readiness Escalation Handler${NC}"
echo -e "${BLUE}=====================================${NC}"
echo "Kind:             ${READINESS_ESCALATION_KIND}"
echo "Status:           ${READINESS_ESCALATION_STATUS}"
echo "Dry run:          ${READINESS_ESCALATION_DRY_RUN}"
echo "Issue title:      ${ISSUE_TITLE}"
echo "Issue labels:     ${ISSUE_TRACKING_LABEL}, ${ISSUE_KIND_LABEL}"
echo "Open pages max:   ${READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES}"
echo "Closed pages max: ${READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES}"
echo "Run URL:          ${RUN_URL}"
echo "Supabase target:  ${SUPABASE_TARGET}"
echo "Log file:         ${READINESS_LOG_FILE:-<not-set>}"
echo ""

webhook_attempted="false"
webhook_success="false"
webhook_requirement_failed=0
existing_issue_number=""

if [ "${READINESS_ESCALATION_STATUS}" = "failure" ]; then
  if [ -n "${ALERT_WEBHOOK_URL}" ]; then
    webhook_attempted="true"
    webhook_text="$(printf "${WEBHOOK_TEXT_TEMPLATE}" "${SUPABASE_TARGET}" "${RUN_URL}")"
    webhook_payload="$(jq -nc --arg text "${webhook_text}" '{text: $text}')"

    if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
      if [ "${READINESS_ESCALATION_DRY_WEBHOOK_RESULT}" = "success" ]; then
        webhook_success="true"
        echo -e "${GREEN}Dry-run webhook check: success.${NC}"
      else
        echo -e "${YELLOW}Dry-run webhook check: simulated failure.${NC}"
      fi
    else
      set +e
      webhook_status="$(curl -sS -o /dev/null -w "%{http_code}" \
        -X POST "${ALERT_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "${webhook_payload}")"
      webhook_exit=$?
      set -e

      if [ "${webhook_exit}" -eq 0 ] && [[ "${webhook_status}" =~ ^2 ]]; then
        webhook_success="true"
        echo -e "${GREEN}Webhook sent successfully (HTTP ${webhook_status}).${NC}"
      else
        echo -e "${YELLOW}Webhook send failed (curl exit ${webhook_exit}, HTTP ${webhook_status:-unknown}).${NC}"
      fi
    fi
  else
    if [ "${READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS}" = "true" ]; then
      echo -e "${YELLOW}Webhook success was required but ALERT_WEBHOOK_URL is unset.${NC}"
      webhook_requirement_failed=1
    else
      echo "Webhook URL not configured; skipping optional webhook alert."
    fi
  fi
else
  if [ "${READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS}" = "true" ]; then
    echo -e "${YELLOW}READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS is ignored in recovered mode.${NC}"
  fi
  echo "Recovery mode: skipping webhook alert."
fi

if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
  load_open_issues_fixture
  load_closed_issues_fixture
  ensure_issue_payload_array "open issue payload" "${OPEN_ISSUES_PAYLOAD}"
  ensure_issue_payload_array "closed issue payload" "${CLOSED_ISSUES_PAYLOAD}"
  OPEN_PAGES_SCANNED=0
  OPEN_MATCH_PAGE=0
  CLOSED_PAGES_SCANNED=0
  CLOSED_MATCH_PAGE=0
  existing_issue_number="$(find_matching_issue_number "${OPEN_ISSUES_PAYLOAD}")"
else
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo -e "${RED}Error: GITHUB_TOKEN is required in live mode.${NC}"
    exit 1
  fi

  if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo -e "${RED}Error: GITHUB_REPOSITORY is required in live mode.${NC}"
    exit 1
  fi
  find_matching_open_issue_number_live "${READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES}"
  existing_issue_number="${MATCHED_OPEN_ISSUE_NUMBER}"
fi

if [ "${READINESS_ESCALATION_STATUS}" = "recovered" ]; then
  if [ -n "${existing_issue_number}" ]; then
    ISSUE_ACTION="close"
    ISSUE_NUMBER="${existing_issue_number}"
    issue_payload="$(jq -nc --arg body "${RECOVERY_COMMENT}" '{body: $body}')"

    if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
      echo -e "${GREEN}Dry-run issue action: would comment and close issue #${ISSUE_NUMBER}.${NC}"
    else
      github_api_request "POST" "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/comments" "${issue_payload}"
      if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
        echo -e "${RED}Failed to comment on issue #${ISSUE_NUMBER} (HTTP ${GH_HTTP_STATUS}).${NC}"
        echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")"
        exit 1
      fi

      close_payload='{"state":"closed"}'
      github_api_request "PATCH" "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}" "${close_payload}"
      if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
        echo -e "${RED}Failed to close issue #${ISSUE_NUMBER} (HTTP ${GH_HTTP_STATUS}).${NC}"
        echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")"
        exit 1
      fi
      echo -e "${GREEN}Closed issue #${ISSUE_NUMBER}.${NC}"
    fi
  else
    ISSUE_ACTION="noop"
    ISSUE_NUMBER="none"
    echo "No matching open readiness escalation issue found; nothing to close."
  fi
else
  if [ -n "${existing_issue_number}" ]; then
    ISSUE_ACTION="comment"
    ISSUE_NUMBER="${existing_issue_number}"
    issue_payload="$(jq -nc --arg body "${ISSUE_BODY}" '{body: $body}')"

    if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
      echo -e "${GREEN}Dry-run issue action: would comment on issue #${ISSUE_NUMBER}.${NC}"
    else
      github_api_request "POST" "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/comments" "${issue_payload}"
      if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
        echo -e "${RED}Failed to comment on issue #${ISSUE_NUMBER} (HTTP ${GH_HTTP_STATUS}).${NC}"
        echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")"
        exit 1
      fi
      echo -e "${GREEN}Updated issue #${ISSUE_NUMBER}.${NC}"
    fi
  else
    closed_issue_number=""
    if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
      closed_issue_number="$(find_matching_issue_number "${CLOSED_ISSUES_PAYLOAD}")"
    else
      find_matching_closed_issue_number_live "${READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES}"
      closed_issue_number="${MATCHED_CLOSED_ISSUE_NUMBER}"
    fi

    if [ -n "${closed_issue_number}" ]; then
      ISSUE_ACTION="reopen"
      ISSUE_NUMBER="${closed_issue_number}"
      issue_payload="$(jq -nc --arg body "${ISSUE_BODY}" '{body: $body}')"

      if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
        echo -e "${GREEN}Dry-run issue action: would reopen and comment on issue #${ISSUE_NUMBER}.${NC}"
      else
        reopen_payload='{"state":"open"}'
        github_api_request "PATCH" "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}" "${reopen_payload}"
        if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
          echo -e "${RED}Failed to reopen issue #${ISSUE_NUMBER} (HTTP ${GH_HTTP_STATUS}).${NC}"
          echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")"
          exit 1
        fi

        github_api_request "POST" "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/comments" "${issue_payload}"
        if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
          echo -e "${RED}Failed to comment on reopened issue #${ISSUE_NUMBER} (HTTP ${GH_HTTP_STATUS}).${NC}"
          echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")"
          exit 1
        fi
        echo -e "${GREEN}Reopened issue #${ISSUE_NUMBER}.${NC}"
      fi
    else
      ISSUE_ACTION="create"

      if [ "${READINESS_ESCALATION_DRY_RUN}" = "true" ]; then
        ISSUE_NUMBER="new"
        echo -e "${GREEN}Dry-run issue action: would create a new issue.${NC}"
      else
        issue_payload="$(jq -nc \
          --arg title "${ISSUE_TITLE}" \
          --arg body "${ISSUE_BODY}" \
          --argjson labels "${ISSUE_LABELS_JSON}" \
          '{title: $title, body: $body, labels: $labels}')"
        github_api_request "POST" "/repos/${GITHUB_REPOSITORY}/issues" "${issue_payload}"
        if [[ ! "${GH_HTTP_STATUS}" =~ ^2 ]]; then
          echo -e "${RED}Failed to create issue (HTTP ${GH_HTTP_STATUS}).${NC}"
          echo "Response: $(print_snippet "${GH_RESPONSE_BODY}")"
          exit 1
        fi
        ISSUE_NUMBER="$(printf '%s\n' "${GH_RESPONSE_BODY}" | jq -r '.number // empty')"
        if [ -z "${ISSUE_NUMBER}" ]; then
          echo -e "${RED}Failed to parse created issue number from GitHub response.${NC}"
          exit 1
        fi
        echo -e "${GREEN}Created issue #${ISSUE_NUMBER}.${NC}"
      fi
    fi
  fi
fi

echo ""
echo "Webhook attempted: ${webhook_attempted}"
echo "Webhook success:   ${webhook_success}"
echo "Issue action:      ${ISSUE_ACTION}"
echo "Issue number:      ${ISSUE_NUMBER}"
echo "Open pages scanned: ${OPEN_PAGES_SCANNED}"
echo "Open match page:   ${OPEN_MATCH_PAGE}"
echo "Closed pages scanned: ${CLOSED_PAGES_SCANNED}"
echo "Closed match page: ${CLOSED_MATCH_PAGE}"

write_github_output \
  "${webhook_attempted}" \
  "${webhook_success}" \
  "${ISSUE_ACTION}" \
  "${ISSUE_NUMBER}" \
  "${OPEN_PAGES_SCANNED}" \
  "${OPEN_MATCH_PAGE}" \
  "${CLOSED_PAGES_SCANNED}" \
  "${CLOSED_MATCH_PAGE}"

strict_webhook_requirement_failed="false"
if [ "${READINESS_ESCALATION_STATUS}" = "failure" ] && [ "${READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS}" = "true" ]; then
  if [ "${webhook_attempted}" != "true" ] || [ "${webhook_success}" != "true" ] || [ "${webhook_requirement_failed}" -ne 0 ]; then
    strict_webhook_requirement_failed="true"
  fi
fi

write_metrics_file \
  "${webhook_attempted}" \
  "${webhook_success}" \
  "${ISSUE_ACTION}" \
  "${ISSUE_NUMBER}" \
  "${strict_webhook_requirement_failed}"

if [ "${strict_webhook_requirement_failed}" = "true" ]; then
    echo -e "${RED}Escalation failed strict webhook requirement.${NC}"
    exit 1
fi

echo -e "${GREEN}Readiness escalation handling complete.${NC}"
