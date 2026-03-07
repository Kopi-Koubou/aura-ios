#!/bin/bash
# Builds warmup zodiac/MBTI combinations from production demand signals.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "${SCRIPT_DIR}/../ops" ]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [ -d "${SCRIPT_DIR}/../../ops" ]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  echo -e "${RED}Error: could not resolve repository root from ${SCRIPT_DIR}.${NC}"
  exit 1
fi
LEGACY_RPC_PATH="/rest/v1/rpc/get_popular_warmup_combos"
TIERED_RPC_PATH="/rest/v1/rpc/get_popular_warmup_combos_by_tier"

OUTPUT_FILE="${WARMUP_COMBOS_GENERATED_FILE:-${REPO_ROOT}/ops/warmup-combos.generated.txt}"
WARMUP_LIMIT="${WARMUP_LIMIT:-20}"
WARMUP_LOOKBACK_DAYS="${WARMUP_LOOKBACK_DAYS:-30}"
INCLUDE_PREMIUM="${INCLUDE_PREMIUM:-true}"

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

if ! [[ "${WARMUP_LIMIT}" =~ ^[0-9]+$ ]] || [ "${WARMUP_LIMIT}" -lt 1 ]; then
  echo -e "${RED}Error: WARMUP_LIMIT must be a positive integer.${NC}"
  exit 1
fi

if ! [[ "${WARMUP_LOOKBACK_DAYS}" =~ ^[0-9]+$ ]] || [ "${WARMUP_LOOKBACK_DAYS}" -lt 1 ]; then
  echo -e "${RED}Error: WARMUP_LOOKBACK_DAYS must be a positive integer.${NC}"
  exit 1
fi

INCLUDE_PREMIUM="$(printf '%s' "${INCLUDE_PREMIUM}" | tr '[:upper:]' '[:lower:]')"
if [[ "${INCLUDE_PREMIUM}" != "true" && "${INCLUDE_PREMIUM}" != "false" ]]; then
  echo -e "${RED}Error: INCLUDE_PREMIUM must be 'true' or 'false'.${NC}"
  exit 1
fi

if [ -n "${SUPABASE_BASE_URL:-}" ]; then
  BASE_URL="${SUPABASE_BASE_URL%/}"
elif [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
  BASE_URL="https://${SUPABASE_PROJECT_REF}.supabase.co"
else
  echo -e "${RED}Error: either SUPABASE_BASE_URL or SUPABASE_PROJECT_REF is required.${NC}"
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"

output_tmp="$(mktemp)"
free_tmp="$(mktemp)"
premium_tmp="$(mktemp)"
combined_tmp="$(mktemp)"
cleanup() {
  rm -f "${output_tmp}" "${free_tmp}" "${premium_tmp}" "${combined_tmp}"
}
trap cleanup EXIT

call_combo_rpc() {
  local rpc_path="$1"
  local payload="$2"
  local destination="$3"
  local response_file
  local http_status
  local compact_body

  response_file="$(mktemp)"
  http_status="$(curl -sS -o "${response_file}" -w "%{http_code}" \
    -X POST "${BASE_URL}${rpc_path}" \
    -H "Content-Type: application/json" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -d "${payload}")"

  if [[ ! "${http_status}" =~ ^2 ]]; then
    compact_body="$(tr '\n' ' ' < "${response_file}" | cut -c1-240)"
    echo -e "${YELLOW}Warning: combo RPC ${rpc_path} failed with HTTP ${http_status}.${NC}"
    echo "Response: ${compact_body}"
    rm -f "${response_file}"
    return 1
  fi

  jq -r '
    if type == "array" then
      .[]
      | select(.zodiac_sign != null and .mbti_type != null)
      | "\(.zodiac_sign)|\(.mbti_type)"
    else
      empty
    end
  ' "${response_file}" | awk '!seen[$0]++' > "${destination}"

  rm -f "${response_file}"
  return 0
}

fetch_tier_combos() {
  local is_premium="$1"
  local destination="$2"
  local payload

  payload="$(cat <<JSON
{"p_limit":${WARMUP_LIMIT},"p_lookback_days":${WARMUP_LOOKBACK_DAYS},"p_is_premium":${is_premium}}
JSON
)"

  call_combo_rpc "${TIERED_RPC_PATH}" "${payload}" "${destination}"
}

fetch_legacy_combos() {
  local destination="$1"
  local payload

  payload="$(cat <<JSON
{"p_limit":${WARMUP_LIMIT},"p_lookback_days":${WARMUP_LOOKBACK_DAYS}}
JSON
)"

  call_combo_rpc "${LEGACY_RPC_PATH}" "${payload}" "${destination}"
}

interleave_unique() {
  local first="$1"
  local second="$2"
  local destination="$3"

  awk '
    NR == FNR { first[++first_count] = $0; next }
    { second[++second_count] = $0 }
    END {
      row_idx = 1
      while (row_idx <= first_count || row_idx <= second_count) {
        if (row_idx <= first_count && first[row_idx] != "" && !seen[first[row_idx]]++) {
          print first[row_idx]
        }
        if (row_idx <= second_count && second[row_idx] != "" && !seen[second[row_idx]]++) {
          print second[row_idx]
        }
        row_idx++
      }
    }
  ' "${first}" "${second}" > "${destination}"
}

source_description=""
echo -e "${BLUE}Resolving dynamic warmup combinations (include_premium=${INCLUDE_PREMIUM})${NC}"

if fetch_tier_combos "false" "${free_tmp}"; then
  if [ "${INCLUDE_PREMIUM}" = "true" ]; then
    if fetch_tier_combos "true" "${premium_tmp}"; then
      interleave_unique "${free_tmp}" "${premium_tmp}" "${combined_tmp}"
      source_description="get_popular_warmup_combos_by_tier (free+premium interleaved)"
    else
      cp "${free_tmp}" "${combined_tmp}"
      source_description="get_popular_warmup_combos_by_tier (free only; premium RPC unavailable)"
    fi
  else
    cp "${free_tmp}" "${combined_tmp}"
    source_description="get_popular_warmup_combos_by_tier (free only)"
  fi
fi

if [ ! -s "${combined_tmp}" ]; then
  echo -e "${YELLOW}Falling back to legacy combo RPC.${NC}"
  if ! fetch_legacy_combos "${combined_tmp}"; then
    echo -e "${RED}Error: unable to resolve warmup combos from tiered or legacy RPC.${NC}"
    exit 1
  fi
  source_description="get_popular_warmup_combos (legacy fallback)"
fi

{
  echo "# Auto-generated by scripts/build-warmup-combos.sh"
  echo "# Source: ${source_description}; limit=${WARMUP_LIMIT}; lookback_days=${WARMUP_LOOKBACK_DAYS}; include_premium=${INCLUDE_PREMIUM}"
  awk -v max="${WARMUP_LIMIT}" '
    !seen[$0]++ {
      print $0
      count++
      if (count >= max) {
        exit
      }
    }
  ' "${combined_tmp}"
} > "${output_tmp}"

combo_count="$(grep -Evc '^[[:space:]]*(#|$)' "${output_tmp}" || true)"

if [ "${combo_count}" -eq 0 ]; then
  rm -f "${OUTPUT_FILE}"
  echo -e "${YELLOW}No combo rows returned by RPC; fallback static list will be used.${NC}"
  exit 0
fi

mv "${output_tmp}" "${OUTPUT_FILE}"
echo -e "${GREEN}Wrote ${combo_count} combo(s) to ${OUTPUT_FILE}.${NC}"
