#!/bin/bash
# Purges stale generated_reading_cache rows through a bounded retention RPC.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RPC_PATH="/rest/v1/rpc/purge_generated_reading_cache"

if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}Error: curl is required.${NC}"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo -e "${RED}Error: jq is required.${NC}"
  exit 1
fi

if [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  echo -e "${RED}Error: SUPABASE_SERVICE_ROLE_KEY is required.${NC}"
  exit 1
fi

CACHE_RETENTION_DAYS="${CACHE_RETENTION_DAYS:-3}"
if ! [[ "${CACHE_RETENTION_DAYS}" =~ ^[0-9]+$ ]] || [ "${CACHE_RETENTION_DAYS}" -lt 1 ] || [ "${CACHE_RETENTION_DAYS}" -gt 30 ]; then
  echo -e "${RED}Error: CACHE_RETENTION_DAYS must be an integer between 1 and 30.${NC}"
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

ENDPOINT="${BASE_URL%/}${RPC_PATH}"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Aura Generated Cache Retention Pruner${NC}"
echo -e "${BLUE}======================================${NC}"
echo "Endpoint:          ${ENDPOINT}"
echo "Retention days:    ${CACHE_RETENTION_DAYS}"
echo ""

response_file="$(mktemp)"
row_file="$(mktemp)"
cleanup() {
  rm -f "${response_file}" "${row_file}"
}
trap cleanup EXIT

payload="$(cat <<JSON
{"p_retention_days":${CACHE_RETENTION_DAYS}}
JSON
)"

http_status="$(curl -sS -o "${response_file}" -w "%{http_code}" \
  -X POST "${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -d "${payload}")"

if [[ "${http_status}" != 2* ]]; then
  echo -e "${RED}Failed to invoke purge RPC (HTTP ${http_status}).${NC}"
  compact_body="$(tr '\n' ' ' < "${response_file}" | cut -c1-320)"
  echo "${compact_body}"
  echo -e "${YELLOW}Hint: ensure migration 20260305_generated_reading_cache_retention.sql is applied.${NC}"
  exit 1
fi

if ! jq -e 'type == "array" or type == "object"' "${response_file}" >/dev/null; then
  echo -e "${RED}Unexpected response payload; expected JSON object or array.${NC}"
  cat "${response_file}"
  exit 1
fi

jq 'if type == "array" then .[0] // {} else . end' "${response_file}" > "${row_file}"

if ! jq -e 'type == "object"' "${row_file}" >/dev/null; then
  echo -e "${RED}Unexpected RPC row payload.${NC}"
  cat "${response_file}"
  exit 1
fi

deleted_count="$(jq -r '.deleted_count // 0' "${row_file}")"
retention_days="$(jq -r '.retention_days // empty' "${row_file}")"
cutoff_date="$(jq -r '.cutoff_date // empty' "${row_file}")"
remaining_count="$(jq -r '.remaining_count // 0' "${row_file}")"

echo "Deleted rows:      ${deleted_count}"
echo "Retention days:    ${retention_days:-${CACHE_RETENTION_DAYS}}"
echo "Cutoff date (UTC): ${cutoff_date:-unknown}"
echo "Remaining rows:    ${remaining_count}"
echo ""

if [ "${deleted_count}" = "0" ]; then
  echo -e "${GREEN}Prune completed: no stale rows required deletion.${NC}"
else
  echo -e "${GREEN}Prune completed successfully.${NC}"
fi
