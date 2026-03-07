#!/bin/bash
# Pre-generates shared horoscope cache rows for popular zodiac/MBTI combinations.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WARM_SECRET_HEADER="x-cache-warm-secret"
FUNCTION_PATH="/functions/v1/generate-horoscope"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_COMBOS_FILE_PATH="${REPO_ROOT}/ops/warmup-combos.txt"

DEFAULT_COMBOS=(
  "Aries|INTJ"
  "Aries|ENFP"
  "Taurus|ISFJ"
  "Gemini|ENTP"
  "Cancer|INFJ"
  "Leo|ENTJ"
  "Virgo|ISTJ"
  "Libra|ENFJ"
  "Scorpio|INTP"
  "Sagittarius|ESTP"
  "Capricorn|ISTJ"
  "Aquarius|INTJ"
  "Pisces|INFP"
  "Aries|ESTP"
  "Taurus|ISFP"
  "Gemini|ENFP"
  "Cancer|ISFJ"
  "Leo|ESFP"
  "Virgo|INTJ"
  "Libra|INFP"
)

DEFAULT_CATEGORIES=(
  "Career"
  "Love"
  "Social"
  "Health"
  "Personal Growth"
)

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_retryable_http_status() {
  local status="$1"
  case "${status}" in
    408|409|425|429|500|502|503|504)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

retry_delay_for_attempt() {
  local attempt="$1"
  if [ "${WARMUP_RETRY_DELAY_SECONDS}" -le 0 ]; then
    printf '0'
    return
  fi

  printf '%s' "$((WARMUP_RETRY_DELAY_SECONDS * attempt))"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

write_warmup_metrics() {
  local exit_code="$1"
  local outcome="$2"

  if [ -z "${WARMUP_METRICS_FILE}" ]; then
    return
  fi

  local metrics_dir
  metrics_dir="$(dirname "${WARMUP_METRICS_FILE}")"
  if [ -n "${metrics_dir}" ] && [ "${metrics_dir}" != "." ]; then
    mkdir -p "${metrics_dir}" 2>/dev/null || true
  fi

  local include_premium_bool="false"
  if [ "${INCLUDE_PREMIUM}" = "true" ]; then
    include_premium_bool="true"
  fi

  local max_retry_rate_json="null"
  if [ -n "${WARMUP_MAX_RETRY_RATE_PERCENT}" ]; then
    max_retry_rate_json="${WARMUP_MAX_RETRY_RATE_PERCENT}"
  fi

  local generated_at_utc
  generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cat > "${WARMUP_METRICS_FILE}" <<JSON
{
  "target_date": "$(json_escape "${TARGET_DATE}")",
  "function_url": "$(json_escape "${FUNCTION_URL}")",
  "combos_source": "$(json_escape "${combos_source}")",
  "combos_configured": ${#combos[@]},
  "combos_used": ${used_combos},
  "category_count": ${#categories[@]},
  "include_premium": ${include_premium_bool},
  "total_requests": ${total},
  "successful_requests": ${successful},
  "failed_requests": ${failed},
  "cache_hits": ${cache_hits},
  "newly_generated": ${newly_generated},
  "requests_retried": ${requests_retried},
  "retry_attempts": ${retry_attempts},
  "retry_rate_percent": ${retry_rate_percent},
  "max_retry_rate_percent": ${max_retry_rate_json},
  "outcome": "$(json_escape "${outcome}")",
  "exit_code": ${exit_code},
  "generated_at_utc": "$(json_escape "${generated_at_utc}")"
}
JSON
}

if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo -e "${RED}Error: SUPABASE_ANON_KEY is required.${NC}"
  exit 1
fi

if [ -z "${CACHE_WARM_SECRET:-}" ]; then
  echo -e "${RED}Error: CACHE_WARM_SECRET is required.${NC}"
  exit 1
fi

TARGET_DATE="${TARGET_DATE:-$(date -u +%F)}"
WARMUP_LIMIT="${WARMUP_LIMIT:-20}"
INCLUDE_PREMIUM="${INCLUDE_PREMIUM:-true}"
WARMUP_REQUEST_RETRIES="${WARMUP_REQUEST_RETRIES:-1}"
WARMUP_RETRY_DELAY_SECONDS="${WARMUP_RETRY_DELAY_SECONDS:-1}"
WARMUP_MAX_RETRY_RATE_PERCENT="${WARMUP_MAX_RETRY_RATE_PERCENT:-}"
WARMUP_METRICS_FILE="${WARMUP_METRICS_FILE:-}"

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
  echo -e "${RED}Error: set SUPABASE_BASE_URL or SUPABASE_PROJECT_REF.${NC}"
  exit 1
fi

FUNCTION_URL="${BASE_URL%/}${FUNCTION_PATH}"

if ! [[ "${WARMUP_LIMIT}" =~ ^[0-9]+$ ]] || [ "${WARMUP_LIMIT}" -lt 1 ]; then
  echo -e "${RED}Error: WARMUP_LIMIT must be a positive integer.${NC}"
  exit 1
fi

if ! [[ "${WARMUP_REQUEST_RETRIES}" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Error: WARMUP_REQUEST_RETRIES must be a non-negative integer.${NC}"
  exit 1
fi

if ! [[ "${WARMUP_RETRY_DELAY_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Error: WARMUP_RETRY_DELAY_SECONDS must be a non-negative integer.${NC}"
  exit 1
fi

if [ -n "${WARMUP_MAX_RETRY_RATE_PERCENT}" ]; then
  if ! [[ "${WARMUP_MAX_RETRY_RATE_PERCENT}" =~ ^[0-9]+$ ]] || [ "${WARMUP_MAX_RETRY_RATE_PERCENT}" -gt 100 ]; then
    echo -e "${RED}Error: WARMUP_MAX_RETRY_RATE_PERCENT must be an integer between 0 and 100 when set.${NC}"
    exit 1
  fi
fi

combos=()
combos_source="built-in defaults"
resolved_combos_file="${WARMUP_COMBOS_FILE:-}"

if [ -z "${resolved_combos_file}" ] && [ -f "${DEFAULT_COMBOS_FILE_PATH}" ]; then
  resolved_combos_file="${DEFAULT_COMBOS_FILE_PATH}"
fi

if [ -n "${resolved_combos_file}" ]; then
  if [ ! -f "${resolved_combos_file}" ]; then
    echo -e "${RED}Error: WARMUP_COMBOS_FILE does not exist: ${resolved_combos_file}${NC}"
    exit 1
  fi

  while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
    line="${raw_line%%#*}"
    line="$(trim "${line}")"
    if [ -n "${line}" ]; then
      combos+=("${line}")
    fi
  done < "${resolved_combos_file}"
  combos_source="${resolved_combos_file}"
else
  combos=("${DEFAULT_COMBOS[@]}")
fi

if [ "${#combos[@]}" -eq 0 ]; then
  echo -e "${RED}Error: no warmup combinations resolved.${NC}"
  exit 1
fi

categories=()
if [ -n "${WARMUP_CATEGORIES:-}" ]; then
  IFS=',' read -r -a raw_categories <<< "${WARMUP_CATEGORIES}"
  for raw_category in "${raw_categories[@]}"; do
    category="$(trim "${raw_category}")"
    if [ -n "${category}" ]; then
      categories+=("${category}")
    fi
  done
else
  categories=("${DEFAULT_CATEGORIES[@]}")
fi

if [ "${#categories[@]}" -eq 0 ]; then
  echo -e "${RED}Error: no categories resolved for warmup.${NC}"
  exit 1
fi

tiers=("false")
if [ "${INCLUDE_PREMIUM}" = "true" ]; then
  tiers=("false" "true")
fi

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Aura Generated Cache Warmup${NC}"
echo -e "${BLUE}==========================================${NC}"
echo "Function URL: ${FUNCTION_URL}"
echo "Target date:  ${TARGET_DATE}"
echo "Combos limit: ${WARMUP_LIMIT} (from ${#combos[@]} configured)"
echo "Combos source: ${combos_source}"
echo "Categories:   ${categories[*]}"
echo "Premium tier: ${INCLUDE_PREMIUM}"
echo "Retries/request: ${WARMUP_REQUEST_RETRIES}"
echo "Retry delay(s): ${WARMUP_RETRY_DELAY_SECONDS}"
if [ -n "${WARMUP_MAX_RETRY_RATE_PERCENT}" ]; then
  echo "Max retry rate: ${WARMUP_MAX_RETRY_RATE_PERCENT}%"
else
  echo "Max retry rate: (disabled)"
fi
echo ""

successful=0
failed=0
cache_hits=0
total=0
used_combos=0
requests_retried=0
retry_attempts=0

for combo in "${combos[@]}"; do
  if [ "${used_combos}" -ge "${WARMUP_LIMIT}" ]; then
    break
  fi

  zodiac_sign="${combo%%|*}"
  mbti_type="${combo##*|}"

  if [ "${zodiac_sign}" = "${combo}" ] || [ -z "${zodiac_sign}" ] || [ -z "${mbti_type}" ]; then
    echo -e "${YELLOW}Skipping invalid combo format (expected Zodiac|MBTI): ${combo}${NC}"
    continue
  fi

  used_combos=$((used_combos + 1))
  echo -e "${YELLOW}Warming combo ${used_combos}/${WARMUP_LIMIT}: ${zodiac_sign} ${mbti_type}${NC}"

  for category in "${categories[@]}"; do
    for is_premium in "${tiers[@]}"; do
      total=$((total + 1))
      payload="$(cat <<JSON
{"warm_cache":true,"zodiac_sign":"${zodiac_sign}","mbti_type":"${mbti_type}","category":"${category}","is_premium":${is_premium},"date":"${TARGET_DATE}"}
JSON
)"
      max_attempts=$((WARMUP_REQUEST_RETRIES + 1))
      attempt=1
      request_retry_used=0

      while [ "${attempt}" -le "${max_attempts}" ]; do
        response_file="$(mktemp)"

        if http_status="$(curl -sS -o "${response_file}" -w "%{http_code}" \
          -X POST "${FUNCTION_URL}" \
          -H "Content-Type: application/json" \
          -H "apikey: ${SUPABASE_ANON_KEY}" \
          -H "${WARM_SECRET_HEADER}: ${CACHE_WARM_SECRET}" \
          -d "${payload}")"; then
          if [[ "${http_status}" == 2* ]]; then
            successful=$((successful + 1))
            if grep -Eq '"cached"[[:space:]]*:[[:space:]]*true' "${response_file}"; then
              cache_hits=$((cache_hits + 1))
              echo "  ✓ ${category} premium=${is_premium} (cache hit)"
            else
              echo "  ✓ ${category} premium=${is_premium} (generated)"
            fi
            rm -f "${response_file}"
            if [ "${request_retry_used}" -eq 1 ]; then
              requests_retried=$((requests_retried + 1))
            fi
            break
          fi

          if is_retryable_http_status "${http_status}" && [ "${attempt}" -lt "${max_attempts}" ]; then
            delay_seconds="$(retry_delay_for_attempt "${attempt}")"
            compact_body="$(tr '\n' ' ' < "${response_file}" | cut -c1-220)"
            retry_attempts=$((retry_attempts + 1))
            request_retry_used=1
            echo -e "  ${YELLOW}! ${category} premium=${is_premium} (HTTP ${http_status}) retrying attempt $((attempt + 1))/${max_attempts} after ${delay_seconds}s${NC}"
            echo "    ${compact_body}"
            rm -f "${response_file}"
            if [ "${delay_seconds}" -gt 0 ]; then
              sleep "${delay_seconds}"
            fi
            attempt=$((attempt + 1))
            continue
          fi

          failed=$((failed + 1))
          compact_body="$(tr '\n' ' ' < "${response_file}" | cut -c1-220)"
          echo -e "  ${RED}✗ ${category} premium=${is_premium} (HTTP ${http_status})${NC}"
          echo "    ${compact_body}"
          rm -f "${response_file}"
          if [ "${request_retry_used}" -eq 1 ]; then
            requests_retried=$((requests_retried + 1))
          fi
          break
        else
          curl_exit=$?
          if [ "${attempt}" -lt "${max_attempts}" ]; then
            delay_seconds="$(retry_delay_for_attempt "${attempt}")"
            retry_attempts=$((retry_attempts + 1))
            request_retry_used=1
            echo -e "  ${YELLOW}! ${category} premium=${is_premium} (curl transport error ${curl_exit}) retrying attempt $((attempt + 1))/${max_attempts} after ${delay_seconds}s${NC}"
            rm -f "${response_file}"
            if [ "${delay_seconds}" -gt 0 ]; then
              sleep "${delay_seconds}"
            fi
            attempt=$((attempt + 1))
            continue
          fi

          failed=$((failed + 1))
          echo -e "  ${RED}✗ ${category} premium=${is_premium} (curl transport error ${curl_exit})${NC}"
          rm -f "${response_file}"
          if [ "${request_retry_used}" -eq 1 ]; then
            requests_retried=$((requests_retried + 1))
          fi
          break
        fi
      done
    done
  done
done

echo ""
echo -e "${BLUE}Warmup Summary${NC}"
echo "  Total requests: ${total}"
echo "  Successful:     ${successful}"
echo "  Failed:         ${failed}"
echo "  Cache hits:     ${cache_hits}"
newly_generated=$((successful - cache_hits))
if [ "${newly_generated}" -lt 0 ]; then
  newly_generated=0
fi
echo "  Newly generated:${newly_generated}"
echo "  Requests retried: ${requests_retried}"
echo "  Retry attempts:   ${retry_attempts}"
retry_rate_percent=0
if [ "${total}" -gt 0 ]; then
  retry_rate_percent=$((requests_retried * 100 / total))
fi
echo "  Retry rate:       ${retry_rate_percent}%"
if [ -n "${WARMUP_METRICS_FILE}" ]; then
  echo "  Metrics file:     ${WARMUP_METRICS_FILE}"
fi

run_outcome="success"
run_exit_code=0

if [ "${failed}" -gt 0 ]; then
  run_outcome="failed_requests"
  run_exit_code=1
elif [ -n "${WARMUP_MAX_RETRY_RATE_PERCENT}" ] && [ "${retry_rate_percent}" -gt "${WARMUP_MAX_RETRY_RATE_PERCENT}" ]; then
  run_outcome="retry_rate_exceeded"
  run_exit_code=2
fi

write_warmup_metrics "${run_exit_code}" "${run_outcome}"

if [ "${failed}" -gt 0 ]; then
  echo -e "${RED}Cache warmup completed with failures.${NC}"
  exit 1
fi

if [ -n "${WARMUP_MAX_RETRY_RATE_PERCENT}" ] && [ "${retry_rate_percent}" -gt "${WARMUP_MAX_RETRY_RATE_PERCENT}" ]; then
  echo -e "${RED}Cache warmup completed with elevated retry rate (${retry_rate_percent}% > ${WARMUP_MAX_RETRY_RATE_PERCENT}%).${NC}"
  exit 2
fi

echo -e "${GREEN}Cache warmup completed successfully.${NC}"
