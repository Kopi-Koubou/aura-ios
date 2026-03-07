#!/bin/bash
# Rehearses authenticated generate-horoscope behavior before auth-mode enforcement.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VALID_CATEGORY_REGEX='^(Career|Love|Social|Health|Personal Growth)$'
UUID_REGEX='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$'
REHEARSAL_FIXTURE_FILE="${REHEARSAL_FIXTURE_FILE:-}"
REHEARSAL_FIXTURE_JSON="${REHEARSAL_FIXTURE_JSON:-}"
REHEARSAL_FIXTURE_PAYLOAD=""

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/rehearse-auth-rollout.sh

Required environment:
  SUPABASE_ANON_KEY=<supabase-anon-key>
  and one of:
    SUPABASE_PROJECT_REF=<project-ref>
    SUPABASE_BASE_URL=<https://project-ref.supabase.co>
  and one auth source:
    AUTH_TEST_BEARER_TOKEN=<jwt-for-provisioned-user>
    AUTH_TEST_USER_ID=<uuid-of-that-user>
  or:
    AUTH_TEST_USER_EMAIL=<provisioned-user-email>
    AUTH_TEST_USER_PASSWORD=<provisioned-user-password>

Optional environment:
  TARGET_DATE=<YYYY-MM-DD>         # default: current UTC date
  CATEGORY=<Career|Love|Social|Health|Personal Growth>  # default: Career
  EXPECT_AUTH_MODE=<legacy|audit|enforce>               # if set, header must match
  REHEARSAL_FIXTURE_FILE=<path|- > # optional offline fixture JSON file/stdin
  REHEARSAL_FIXTURE_JSON=<json>    # optional inline offline fixture payload

Behavior:
  - Sends two authenticated generate-horoscope requests for the same user/date/category:
    1) lowercase user_id
    2) uppercase user_id
  - Validates both responses are 2xx and authenticated without fallback.
  - Verifies deterministic extras stay identical across user_id casing variants.
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo -e "${RED}Error: ${command_name} is required.${NC}"
    exit 1
  fi
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

extract_header_value_from_text() {
  local headers_text="$1"
  local header_name="$2"
  printf '%s\n' "${headers_text}" | awk -F': *' -v needle="$(to_lower "${header_name}")" '
    tolower($1) == needle {
      value = $2
      sub(/\r$/, "", value)
      print tolower(value)
    }
  ' | tail -n 1
}

print_response_snippet_from_text() {
  local body_text="$1"
  printf '%s' "${body_text}" | tr '\n' ' ' | cut -c1-320
}

is_set() {
  [ -n "${1:-}" ]
}

load_rehearsal_fixture() {
  if [ -n "${REHEARSAL_FIXTURE_FILE}" ] && [ -n "${REHEARSAL_FIXTURE_JSON}" ]; then
    echo -e "${RED}Error: set only one of REHEARSAL_FIXTURE_FILE or REHEARSAL_FIXTURE_JSON.${NC}"
    exit 1
  fi

  if [ -n "${REHEARSAL_FIXTURE_FILE}" ]; then
    if [ "${REHEARSAL_FIXTURE_FILE}" = "-" ]; then
      REHEARSAL_FIXTURE_PAYLOAD="$(cat)"
    elif [ -r "${REHEARSAL_FIXTURE_FILE}" ]; then
      REHEARSAL_FIXTURE_PAYLOAD="$(cat "${REHEARSAL_FIXTURE_FILE}")"
    else
      echo -e "${RED}Error: REHEARSAL_FIXTURE_FILE is not readable: ${REHEARSAL_FIXTURE_FILE}.${NC}"
      exit 1
    fi
  elif [ -n "${REHEARSAL_FIXTURE_JSON}" ]; then
    REHEARSAL_FIXTURE_PAYLOAD="${REHEARSAL_FIXTURE_JSON}"
  fi

  if [ -z "${REHEARSAL_FIXTURE_PAYLOAD}" ]; then
    return
  fi

  if ! printf '%s\n' "${REHEARSAL_FIXTURE_PAYLOAD}" | jq -e 'type == "object"' >/dev/null; then
    echo -e "${RED}Error: rehearsal fixture payload must be a JSON object.${NC}"
    exit 1
  fi
}

fixture_mode_enabled() {
  [ -n "${REHEARSAL_FIXTURE_PAYLOAD}" ]
}

assert_valid_inputs() {
  local has_static_auth=0
  local has_password_auth=0

  if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
    echo -e "${RED}Error: SUPABASE_ANON_KEY is required.${NC}"
    exit 1
  fi

  if is_set "${AUTH_TEST_BEARER_TOKEN:-}" || is_set "${AUTH_TEST_USER_ID:-}"; then
    if ! is_set "${AUTH_TEST_BEARER_TOKEN:-}" || ! is_set "${AUTH_TEST_USER_ID:-}"; then
      echo -e "${RED}Error: set both AUTH_TEST_BEARER_TOKEN and AUTH_TEST_USER_ID, or neither.${NC}"
      exit 1
    fi
    has_static_auth=1
  fi

  if is_set "${AUTH_TEST_USER_EMAIL:-}" || is_set "${AUTH_TEST_USER_PASSWORD:-}"; then
    if ! is_set "${AUTH_TEST_USER_EMAIL:-}" || ! is_set "${AUTH_TEST_USER_PASSWORD:-}"; then
      echo -e "${RED}Error: set both AUTH_TEST_USER_EMAIL and AUTH_TEST_USER_PASSWORD, or neither.${NC}"
      exit 1
    fi
    has_password_auth=1
  fi

  if [ "${has_static_auth}" -eq 0 ] && [ "${has_password_auth}" -eq 0 ]; then
    echo -e "${RED}Error: provide auth source via static token/user-id pair or email/password pair.${NC}"
    exit 1
  fi

  if ! [[ "${CATEGORY}" =~ ${VALID_CATEGORY_REGEX} ]]; then
    echo -e "${RED}Error: CATEGORY must be one of Career|Love|Social|Health|Personal Growth.${NC}"
    exit 1
  fi

  if ! [[ "${TARGET_DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo -e "${RED}Error: TARGET_DATE must be in YYYY-MM-DD format.${NC}"
    exit 1
  fi

  if [ -n "${EXPECT_AUTH_MODE}" ]; then
    case "${EXPECT_AUTH_MODE}" in
      legacy|audit|enforce) ;;
      *)
        echo -e "${RED}Error: EXPECT_AUTH_MODE must be legacy|audit|enforce when set.${NC}"
        exit 1
        ;;
    esac
  fi
}

resolve_base_url() {
  if [ -n "${SUPABASE_BASE_URL:-}" ]; then
    printf '%s' "${SUPABASE_BASE_URL%/}"
    return
  fi

  if [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
    printf 'https://%s.supabase.co' "${SUPABASE_PROJECT_REF}"
    return
  fi

  echo -e "${RED}Error: set SUPABASE_BASE_URL or SUPABASE_PROJECT_REF.${NC}" >&2
  exit 1
}

AUTH_SOURCE_LABEL=""

resolve_auth_inputs() {
  local has_static_auth=0
  local has_password_auth=0

  if is_set "${AUTH_TEST_BEARER_TOKEN:-}" && is_set "${AUTH_TEST_USER_ID:-}"; then
    has_static_auth=1
  fi
  if is_set "${AUTH_TEST_USER_EMAIL:-}" && is_set "${AUTH_TEST_USER_PASSWORD:-}"; then
    has_password_auth=1
  fi

  if [ "${has_static_auth}" -eq 1 ]; then
    AUTH_SOURCE_LABEL="static_token"
    if [ "${has_password_auth}" -eq 1 ]; then
      echo -e "${YELLOW}Warning: both auth sources are configured; using static token/user-id pair.${NC}"
    fi
  else
    local login_endpoint
    local login_status
    local login_body

    AUTH_SOURCE_LABEL="password_login"
    if fixture_mode_enabled; then
      login_status="$(printf '%s\n' "${REHEARSAL_FIXTURE_PAYLOAD}" | jq -r '.login.http_status // 200')"
      login_body="$(printf '%s\n' "${REHEARSAL_FIXTURE_PAYLOAD}" | jq -c '.login.body // {}')"
      if [[ ! "${login_status}" =~ ^2 ]]; then
        echo -e "${RED}Error: fixture login response is non-success (HTTP ${login_status}).${NC}"
        echo "Fixture body: ${login_body}"
        exit 1
      fi
    else
      local login_payload
      local login_response
      login_endpoint="${BASE_URL%/}/auth/v1/token?grant_type=password"
      login_payload="$(jq -nc \
        --arg email "${AUTH_TEST_USER_EMAIL}" \
        --arg password "${AUTH_TEST_USER_PASSWORD}" \
        '{email: $email, password: $password}')"
      login_response="$(mktemp)"

      login_status="$(curl -sS -o "${login_response}" -w "%{http_code}" \
        -X POST "${login_endpoint}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        -d "${login_payload}")"

      if [[ ! "${login_status}" =~ ^2 ]]; then
        echo -e "${RED}Error: failed to obtain auth session from Supabase (HTTP ${login_status}).${NC}"
        echo "Response: $(print_response_snippet "${login_response}")"
        rm -f "${login_response}"
        exit 1
      fi

      login_body="$(cat "${login_response}")"
      rm -f "${login_response}"
    fi

    AUTH_TEST_BEARER_TOKEN="$(printf '%s\n' "${login_body}" | jq -r '.access_token // empty')"
    AUTH_TEST_USER_ID="$(printf '%s\n' "${login_body}" | jq -r '.user.id // empty')"

    if [ -z "${AUTH_TEST_BEARER_TOKEN}" ]; then
      echo -e "${RED}Error: auth response did not include access_token.${NC}"
      exit 1
    fi

    if [ -z "${AUTH_TEST_USER_ID}" ]; then
      echo -e "${RED}Error: auth response did not include user.id.${NC}"
      exit 1
    fi
  fi

  if ! [[ "${AUTH_TEST_USER_ID}" =~ ${UUID_REGEX} ]]; then
    echo -e "${RED}Error: resolved AUTH_TEST_USER_ID must be a valid UUID.${NC}"
    exit 1
  fi
}

LOWER_READING_ID=""
LOWER_FORTUNE_SCORE=""
LOWER_LUCKY_NUMBERS=""
LOWER_POWER_COLORS=""

UPPER_READING_ID=""
UPPER_FORTUNE_SCORE=""
UPPER_LUCKY_NUMBERS=""
UPPER_POWER_COLORS=""

run_case() {
  local case_name="$1"
  local case_user_id="$2"

  local response_headers_file=""
  local response_body_file=""
  local response_headers_text=""
  local response_body_text=""
  local payload
  local status
  local auth_mode
  local auth_context
  local auth_fallback
  local body_auth_context
  local body_auth_fallback
  local reading_user_id
  local reading_id
  local fortune_score
  local lucky_numbers
  local power_colors

  if fixture_mode_enabled; then
    local fixture_case
    fixture_case="$(printf '%s\n' "${REHEARSAL_FIXTURE_PAYLOAD}" | jq -c --arg case_name "${case_name}" '.responses[$case_name] // empty')"
    if [ -z "${fixture_case}" ]; then
      echo -e "${RED}Failure (${case_name} user_id): missing fixture response for case '${case_name}'.${NC}"
      exit 1
    fi

    status="$(printf '%s\n' "${fixture_case}" | jq -r '.http_status // 200')"
    response_headers_text="$(printf '%s\n' "${fixture_case}" | jq -r '.headers // {} | to_entries[]? | "\(.key): \(.value)"')"
    response_body_text="$(printf '%s\n' "${fixture_case}" | jq -c '.body // {}')"
  else
    response_headers_file="$(mktemp)"
    response_body_file="$(mktemp)"
    trap "rm -f '${response_headers_file}' '${response_body_file}'" RETURN

    payload="$(jq -nc \
      --arg user_id "${case_user_id}" \
      --arg category "${CATEGORY}" \
      --arg date "${TARGET_DATE}" \
      '{user_id: $user_id, category: $category, is_premium: false, date: $date}')"

    status="$(curl -sS -o "${response_body_file}" -D "${response_headers_file}" -w "%{http_code}" \
      -X POST "${FUNCTION_URL}" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "apikey: ${SUPABASE_ANON_KEY}" \
      -H "Authorization: Bearer ${AUTH_TEST_BEARER_TOKEN}" \
      -d "${payload}")"

    response_headers_text="$(cat "${response_headers_file}")"
    response_body_text="$(cat "${response_body_file}")"
  fi

  if [[ ! "${status}" =~ ^2 ]]; then
    echo -e "${RED}Failure (${case_name} user_id): HTTP ${status}.${NC}"
    echo "Response: $(print_response_snippet_from_text "${response_body_text}")"
    exit 1
  fi

  auth_mode="$(extract_header_value_from_text "${response_headers_text}" "x-aura-auth-mode")"
  auth_context="$(extract_header_value_from_text "${response_headers_text}" "x-aura-auth-context")"
  auth_fallback="$(extract_header_value_from_text "${response_headers_text}" "x-aura-auth-fallback")"

  if [ "${auth_context}" != "authenticated" ]; then
    echo -e "${RED}Failure (${case_name} user_id): expected x-aura-auth-context=authenticated, got '${auth_context}'.${NC}"
    exit 1
  fi

  if [ "${auth_fallback}" != "0" ]; then
    echo -e "${RED}Failure (${case_name} user_id): expected x-aura-auth-fallback=0, got '${auth_fallback}'.${NC}"
    exit 1
  fi

  if [ -n "${EXPECT_AUTH_MODE}" ] && [ "${auth_mode}" != "${EXPECT_AUTH_MODE}" ]; then
    echo -e "${RED}Failure (${case_name} user_id): expected x-aura-auth-mode=${EXPECT_AUTH_MODE}, got '${auth_mode}'.${NC}"
    exit 1
  fi

  if ! printf '%s\n' "${response_body_text}" | jq -e 'type == "object"' >/dev/null; then
    echo -e "${RED}Failure (${case_name} user_id): expected JSON object response.${NC}"
    echo "Response: $(print_response_snippet_from_text "${response_body_text}")"
    exit 1
  fi

  body_auth_context="$(printf '%s\n' "${response_body_text}" | jq -r '.auth_context // empty')"
  if [ -n "${body_auth_context}" ] && [ "${body_auth_context}" != "authenticated" ]; then
    echo -e "${RED}Failure (${case_name} user_id): body auth_context should be authenticated, got '${body_auth_context}'.${NC}"
    exit 1
  fi

  body_auth_fallback="$(printf '%s\n' "${response_body_text}" | jq -r '.auth_fallback_identity // empty')"
  if [ -n "${body_auth_fallback}" ] && [ "${body_auth_fallback}" != "false" ]; then
    echo -e "${RED}Failure (${case_name} user_id): body auth_fallback_identity should be false, got '${body_auth_fallback}'.${NC}"
    exit 1
  fi

  reading_user_id="$(printf '%s\n' "${response_body_text}" | jq -r '.reading.user_id // empty')"
  if [ -n "${reading_user_id}" ] && [ "$(to_lower "${reading_user_id}")" != "${LOWER_USER_ID}" ]; then
    echo -e "${RED}Failure (${case_name} user_id): reading.user_id does not match AUTH_TEST_USER_ID.${NC}"
    exit 1
  fi

  reading_id="$(printf '%s\n' "${response_body_text}" | jq -r '.reading.id // empty')"
  fortune_score="$(printf '%s\n' "${response_body_text}" | jq -r '.reading.fortune_score // empty')"
  lucky_numbers="$(printf '%s\n' "${response_body_text}" | jq -c '.reading.lucky_numbers // []')"
  power_colors="$(printf '%s\n' "${response_body_text}" | jq -c '.reading.power_colors // []')"

  if [ "${case_name}" = "lower" ]; then
    LOWER_READING_ID="${reading_id}"
    LOWER_FORTUNE_SCORE="${fortune_score}"
    LOWER_LUCKY_NUMBERS="${lucky_numbers}"
    LOWER_POWER_COLORS="${power_colors}"
  else
    UPPER_READING_ID="${reading_id}"
    UPPER_FORTUNE_SCORE="${fortune_score}"
    UPPER_LUCKY_NUMBERS="${lucky_numbers}"
    UPPER_POWER_COLORS="${power_colors}"
  fi

  echo -e "${GREEN}✓ ${case_name}case user_id request passed (HTTP ${status}, auth_mode=${auth_mode:-unknown}).${NC}"
}

require_command "curl"
require_command "jq"
load_rehearsal_fixture

TARGET_DATE="${TARGET_DATE:-$(date -u +%F)}"
CATEGORY="${CATEGORY:-Career}"
EXPECT_AUTH_MODE="$(to_lower "${EXPECT_AUTH_MODE:-}")"

assert_valid_inputs

BASE_URL="$(resolve_base_url)"
resolve_auth_inputs
FUNCTION_URL="${BASE_URL%/}/functions/v1/generate-horoscope"
LOWER_USER_ID="$(to_lower "${AUTH_TEST_USER_ID}")"
UPPER_USER_ID="$(to_upper "${AUTH_TEST_USER_ID}")"

if [ "${LOWER_USER_ID}" = "${UPPER_USER_ID}" ]; then
  echo -e "${YELLOW}Warning: AUTH_TEST_USER_ID has no alphabetic hex characters; casing variance check is limited.${NC}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Generate Horoscope Auth Rollout Rehearsal${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Function URL:      ${FUNCTION_URL}"
echo "Target date (UTC): ${TARGET_DATE}"
echo "Category:          ${CATEGORY}"
echo "Expected auth mode:${EXPECT_AUTH_MODE:-<skip>}"
echo "Auth source:       ${AUTH_SOURCE_LABEL}"
echo "Fixture mode:      $([ -n "${REHEARSAL_FIXTURE_PAYLOAD}" ] && printf "enabled" || printf "disabled")"
echo "Test user (lower): ${LOWER_USER_ID}"
echo "Test user (upper): ${UPPER_USER_ID}"
echo ""

run_case "lower" "${LOWER_USER_ID}"
run_case "upper" "${UPPER_USER_ID}"

if [ -n "${LOWER_READING_ID}" ] && [ -n "${UPPER_READING_ID}" ] && [ "${LOWER_READING_ID}" != "${UPPER_READING_ID}" ]; then
  echo -e "${RED}Failure: reading.id drift detected between lowercase and uppercase user_id requests.${NC}"
  echo "lowercase reading.id: ${LOWER_READING_ID}"
  echo "uppercase reading.id: ${UPPER_READING_ID}"
  exit 1
fi

if [ -n "${LOWER_FORTUNE_SCORE}" ] && [ -n "${UPPER_FORTUNE_SCORE}" ] && [ "${LOWER_FORTUNE_SCORE}" != "${UPPER_FORTUNE_SCORE}" ]; then
  echo -e "${RED}Failure: fortune_score drift detected between casing variants.${NC}"
  echo "lowercase fortune_score: ${LOWER_FORTUNE_SCORE}"
  echo "uppercase fortune_score: ${UPPER_FORTUNE_SCORE}"
  exit 1
fi

if [ "${LOWER_LUCKY_NUMBERS}" != "${UPPER_LUCKY_NUMBERS}" ]; then
  echo -e "${RED}Failure: lucky_numbers drift detected between casing variants.${NC}"
  echo "lowercase lucky_numbers: ${LOWER_LUCKY_NUMBERS}"
  echo "uppercase lucky_numbers: ${UPPER_LUCKY_NUMBERS}"
  exit 1
fi

if [ "${LOWER_POWER_COLORS}" != "${UPPER_POWER_COLORS}" ]; then
  echo -e "${RED}Failure: power_colors drift detected between casing variants.${NC}"
  echo "lowercase power_colors: ${LOWER_POWER_COLORS}"
  echo "uppercase power_colors: ${UPPER_POWER_COLORS}"
  exit 1
fi

echo ""
echo -e "${GREEN}Auth rollout rehearsal passed.${NC}"
echo "Authenticated requests succeeded without fallback and deterministic extras remained stable across user_id casing (auth source: ${AUTH_SOURCE_LABEL})."
