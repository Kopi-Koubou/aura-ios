#!/bin/bash
# Checks generate-horoscope auth fallback volume to gate audit -> enforce rollout.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TABLE_NAME="generate_horoscope_auth_fallback_daily"

LOOKBACK_DAYS="${LOOKBACK_DAYS:-2}"
MAX_FALLBACKS="${MAX_FALLBACKS:-0}"
AUTH_CONTEXT_FILTER="${AUTH_CONTEXT_FILTER:-all}"
READINESS_JSON_FILE="${READINESS_JSON_FILE:-}"

if ! [[ "${LOOKBACK_DAYS}" =~ ^[0-9]+$ ]] || [ "${LOOKBACK_DAYS}" -lt 1 ]; then
  echo -e "${RED}Error: LOOKBACK_DAYS must be a positive integer.${NC}"
  exit 1
fi

if ! [[ "${MAX_FALLBACKS}" =~ ^[0-9]+$ ]] || [ "${MAX_FALLBACKS}" -lt 0 ]; then
  echo -e "${RED}Error: MAX_FALLBACKS must be a non-negative integer.${NC}"
  exit 1
fi

if [ "${AUTH_CONTEXT_FILTER}" != "all" ] && [ "${AUTH_CONTEXT_FILTER}" != "missing" ] && [ "${AUTH_CONTEXT_FILTER}" != "invalid" ]; then
  echo -e "${RED}Error: AUTH_CONTEXT_FILTER must be one of all|missing|invalid.${NC}"
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

  QUERY="select=date,category,auth_context,fallback_count,updated_at&date=gte.${START_DATE}&order=date.desc,category.asc,auth_context.asc"
  ENDPOINT="${BASE_URL%/}/rest/v1/${TABLE_NAME}?${QUERY}"

  curl_response="$(curl -sS -w $'\n%{http_code}' \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "${ENDPOINT}")"
  http_status="${curl_response##*$'\n'}"
  response_payload="${curl_response%$'\n'*}"

  if [[ "${http_status}" != 2* ]]; then
    echo -e "${RED}Failed to query fallback audit table (HTTP ${http_status}).${NC}"
    compact_body="$(printf '%s' "${response_payload}" | tr '\n' ' ' | cut -c1-320)"
    echo "${compact_body}"
    echo -e "${YELLOW}Hint: ensure migration 20260304_generate_horoscope_auth_fallback_audit.sql is applied.${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Generate Horoscope Auth Fallback Readiness${NC}"
echo -e "${BLUE}==========================================${NC}"
if [ -n "${READINESS_JSON_FILE}" ]; then
  echo "Data source:         ${ENDPOINT}"
else
  echo "Endpoint:            ${ENDPOINT}"
fi
echo "Lookback days:       ${LOOKBACK_DAYS}"
echo "Start date (UTC):    ${START_DATE}"
echo "Auth context filter: ${AUTH_CONTEXT_FILTER}"
echo "Allowed fallbacks:   ${MAX_FALLBACKS}"
echo ""

if ! printf '%s\n' "${response_payload}" | jq -e 'type == "array"' >/dev/null; then
  echo -e "${RED}Unexpected response payload; expected JSON array.${NC}"
  printf '%s\n' "${response_payload}"
  exit 1
fi

filtered_payload="$(printf '%s\n' "${response_payload}" | jq --arg context "${AUTH_CONTEXT_FILTER}" '
  if $context == "all" then
    .
  else
    map(select(.auth_context == $context))
  end
')"

row_count="$(printf '%s\n' "${filtered_payload}" | jq 'length')"
total_fallbacks="$(printf '%s\n' "${filtered_payload}" | jq '[.[].fallback_count // 0] | add // 0')"
missing_total="$(printf '%s\n' "${filtered_payload}" | jq '[.[] | select(.auth_context == "missing") | .fallback_count // 0] | add // 0')"
invalid_total="$(printf '%s\n' "${filtered_payload}" | jq '[.[] | select(.auth_context == "invalid") | .fallback_count // 0] | add // 0')"

echo "Rows returned:       ${row_count}"
echo "Total fallbacks:     ${total_fallbacks}"
echo "Missing context:     ${missing_total}"
echo "Invalid context:     ${invalid_total}"
echo ""

if [ "${row_count}" -gt 0 ]; then
  echo "Daily breakdown:"
  printf "  %-10s | %-15s | %-7s | %s\n" "Date" "Category" "Context" "Count"
  printf '%s\n' "${filtered_payload}" | jq -r '.[] | "  \(.date) | \(.category) | \(.auth_context) | \(.fallback_count)"'
  echo ""
fi

if [ "${total_fallbacks}" -le "${MAX_FALLBACKS}" ]; then
  echo -e "${GREEN}Readiness check passed: fallback volume is within threshold.${NC}"
  exit 0
fi

echo -e "${RED}Readiness check failed: fallback volume exceeds threshold.${NC}"
echo -e "${YELLOW}Keep auth mode at 'audit' and continue client JWT rollout before switching to 'enforce'.${NC}"
exit 2
