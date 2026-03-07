#!/bin/bash
# Checks generate-horoscope shared-cache degradation volume to gate rollout risk.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TABLE_NAME="generate_horoscope_shared_cache_degradation_daily"

LOOKBACK_DAYS="${LOOKBACK_DAYS:-2}"
MAX_DEGRADATIONS="${MAX_DEGRADATIONS:-0}"
PREMIUM_FILTER="${PREMIUM_FILTER:-all}"
REASON_FILTER="${REASON_FILTER:-all}"
READINESS_JSON_FILE="${READINESS_JSON_FILE:-}"

if ! [[ "${LOOKBACK_DAYS}" =~ ^[0-9]+$ ]] || [ "${LOOKBACK_DAYS}" -lt 1 ]; then
  echo -e "${RED}Error: LOOKBACK_DAYS must be a positive integer.${NC}"
  exit 1
fi

if ! [[ "${MAX_DEGRADATIONS}" =~ ^[0-9]+$ ]] || [ "${MAX_DEGRADATIONS}" -lt 0 ]; then
  echo -e "${RED}Error: MAX_DEGRADATIONS must be a non-negative integer.${NC}"
  exit 1
fi

if [ "${PREMIUM_FILTER}" != "all" ] && [ "${PREMIUM_FILTER}" != "free" ] && [ "${PREMIUM_FILTER}" != "premium" ]; then
  echo -e "${RED}Error: PREMIUM_FILTER must be one of all|free|premium.${NC}"
  exit 1
fi

if [ "${REASON_FILTER}" != "all" ] \
  && [ "${REASON_FILTER}" != "shared_content_cache_unavailable" ] \
  && [ "${REASON_FILTER}" != "generated_shared_content_cache_persist_failed" ] \
  && [ "${REASON_FILTER}" != "generated_shared_content_cache_temporarily_unavailable" ]; then
  echo -e "${RED}Error: REASON_FILTER is invalid.${NC}"
  exit 1
fi

date_days_ago() {
  local days_ago="$1"
  if date -u -v-"${days_ago}"d +%F >/dev/null 2>&1; then
    date -u -v-"${days_ago}"d +%F
    return
  fi

  if date -u -d "${days_ago} day ago" +%F >/dev/null 2>&1; then
    date -u -d "${days_ago} day ago" +%F
    return
  fi

  echo "Unable to compute date ${days_ago} days ago." >&2
  exit 1
}

lookback_offset=$((LOOKBACK_DAYS - 1))
START_DATE="$(date_days_ago "${lookback_offset}")"

BASE_URL=""
ENDPOINT=""
response_payload=""

if [ -n "${READINESS_JSON_FILE}" ]; then
  if [ "${READINESS_JSON_FILE}" = "-" ]; then
    response_payload="$(cat)"
  elif [ -r "${READINESS_JSON_FILE}" ]; then
    response_payload="$(cat "${READINESS_JSON_FILE}")"
  else
    echo -e "${RED}Error: READINESS_JSON_FILE is not readable: ${READINESS_JSON_FILE}.${NC}"
    exit 1
  fi
  ENDPOINT="local:${READINESS_JSON_FILE}"
else
  if [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
    echo -e "${RED}Error: SUPABASE_SERVICE_ROLE_KEY is required.${NC}"
    exit 1
  fi

  if [ -n "${SUPABASE_BASE_URL:-}" ]; then
    BASE_URL="${SUPABASE_BASE_URL%/}"
  elif [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
    BASE_URL="https://${SUPABASE_PROJECT_REF}.supabase.co"
  else
    echo -e "${RED}Error: set SUPABASE_BASE_URL or SUPABASE_PROJECT_REF.${NC}"
    exit 1
  fi

  QUERY="select=date,category,is_premium,resolution_reason,degradation_count,lookup_failed_count,persist_failed_count,temporarily_unavailable_count,updated_at&date=gte.${START_DATE}&order=date.desc,category.asc,is_premium.asc,resolution_reason.asc"
  ENDPOINT="${BASE_URL%/}/rest/v1/${TABLE_NAME}?${QUERY}"

  curl_response="$(curl -sS -w $'\n%{http_code}' \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "${ENDPOINT}")"
  http_status="${curl_response##*$'\n'}"
  response_payload="${curl_response%$'\n'*}"

  if [[ "${http_status}" != 2* ]]; then
    echo -e "${RED}Failed to query cache degradation audit table (HTTP ${http_status}).${NC}"
    compact_body="$(printf '%s' "${response_payload}" | tr '\n' ' ' | cut -c1-320)"
    echo "${compact_body}"
    echo -e "${YELLOW}Hint: ensure migration 20260305_generate_horoscope_cache_degradation_audit.sql is applied.${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}Generate Horoscope Shared Cache Degradation Readiness${NC}"
echo -e "${BLUE}=================================================${NC}"
if [ -n "${READINESS_JSON_FILE}" ]; then
  echo "Data source:         ${ENDPOINT}"
else
  echo "Endpoint:            ${ENDPOINT}"
fi
echo "Lookback days:       ${LOOKBACK_DAYS}"
echo "Start date (UTC):    ${START_DATE}"
echo "Premium filter:      ${PREMIUM_FILTER}"
echo "Reason filter:       ${REASON_FILTER}"
echo "Allowed degradations:${MAX_DEGRADATIONS}"
echo ""

if ! printf '%s\n' "${response_payload}" | jq -e 'type == "array"' >/dev/null; then
  echo -e "${RED}Unexpected response payload; expected JSON array.${NC}"
  printf '%s\n' "${response_payload}"
  exit 1
fi

filtered_payload="$(printf '%s\n' "${response_payload}" | jq \
  --arg premium_filter "${PREMIUM_FILTER}" \
  --arg reason_filter "${REASON_FILTER}" '
  map(
    select(
      (
        $premium_filter == "all"
        or ($premium_filter == "premium" and .is_premium == true)
        or ($premium_filter == "free" and .is_premium == false)
      )
      and (
        $reason_filter == "all"
        or .resolution_reason == $reason_filter
      )
    )
  )
')"

row_count="$(printf '%s\n' "${filtered_payload}" | jq 'length')"
total_degradations="$(printf '%s\n' "${filtered_payload}" | jq '[.[].degradation_count // 0] | add // 0')"
lookup_total="$(printf '%s\n' "${filtered_payload}" | jq '[.[].lookup_failed_count // 0] | add // 0')"
persist_total="$(printf '%s\n' "${filtered_payload}" | jq '[.[].persist_failed_count // 0] | add // 0')"
temporary_total="$(printf '%s\n' "${filtered_payload}" | jq '[.[].temporarily_unavailable_count // 0] | add // 0')"

echo "Rows returned:       ${row_count}"
echo "Total degradations:  ${total_degradations}"
echo "Lookup failures:     ${lookup_total}"
echo "Persist failures:    ${persist_total}"
echo "Temporary unavail:   ${temporary_total}"
echo ""

if [ "${row_count}" -gt 0 ]; then
  echo "Daily breakdown:"
  printf "  %-10s | %-15s | %-7s | %-46s | %s\n" "Date" "Category" "Premium" "Reason" "Count"
  printf '%s\n' "${filtered_payload}" | jq -r '.[] | "  \(.date) | \(.category) | \(.is_premium) | \(.resolution_reason) | \(.degradation_count)"'
  echo ""
fi

if [ "${total_degradations}" -le "${MAX_DEGRADATIONS}" ]; then
  echo -e "${GREEN}Readiness check passed: cache degradation volume is within threshold.${NC}"
  exit 0
fi

echo -e "${RED}Readiness check failed: cache degradation volume exceeds threshold.${NC}"
echo -e "${YELLOW}Investigate generated_reading_cache availability before tightening rollout policy.${NC}"
exit 2
