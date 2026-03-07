#!/bin/bash
# Runs fixture-mode regression checks for dynamic warmup combo resolution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/build-warmup-combos.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Warmup combo fixture tests failed: could not locate repository root."
  exit 1
fi

BUILD_SCRIPT="${REPO_ROOT}/scripts/build-warmup-combos.sh"

for dependency in jq mktemp awk grep; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Warmup combo fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${BUILD_SCRIPT}" ]; then
  echo "Warmup combo fixture tests failed: missing script ${BUILD_SCRIPT}."
  exit 1
fi

MOCK_BIN_DIR="$(mktemp -d)"
TMP_OUTPUT_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${MOCK_BIN_DIR}" "${TMP_OUTPUT_DIR}"
}
trap cleanup EXIT

cat > "${MOCK_BIN_DIR}/curl" <<'MOCK_CURL'
#!/bin/bash
set -euo pipefail

output_file=""
payload="{}"
url=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output_file="${2:-}"
      shift 2
      ;;
    -d)
      payload="${2:-}"
      shift 2
      ;;
    -X|-H|-w)
      shift 2
      ;;
    -s|-S|-sS|--silent|--show-error)
      shift
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "${output_file}" ]; then
  echo "mock curl: missing -o destination" >&2
  exit 1
fi

status="500"
body='{"error":"mock_not_configured"}'

case "${url}" in
  */rpc/get_popular_warmup_combos_by_tier)
    is_premium="$(printf '%s\n' "${payload}" | jq -r '.p_is_premium // empty')"
    if [ "${is_premium}" = "true" ]; then
      status="${MOCK_TIER_PREMIUM_STATUS:-500}"
      body="${MOCK_TIER_PREMIUM_BODY:-[]}"
    else
      status="${MOCK_TIER_FREE_STATUS:-500}"
      body="${MOCK_TIER_FREE_BODY:-[]}"
    fi
    ;;
  */rpc/get_popular_warmup_combos)
    status="${MOCK_LEGACY_STATUS:-500}"
    body="${MOCK_LEGACY_BODY:-[]}"
    ;;
esac

printf '%s' "${body}" > "${output_file}"
printf '%s' "${status}"
MOCK_CURL

chmod +x "${MOCK_BIN_DIR}/curl"

run_fixture_case() {
  local expected_exit="$1"
  local label="$2"
  shift 2

  echo ""
  echo "Case: ${label}"

  set +e
  CASE_OUTPUT="$("$@" 2>&1)"
  local actual_exit=$?
  set -e

  if [ "${actual_exit}" -ne "${expected_exit}" ]; then
    echo "${CASE_OUTPUT}"
    echo "Case failed: expected exit ${expected_exit}, got ${actual_exit}."
    exit 1
  fi

  echo "Case passed."
}

assert_case_output_contains() {
  local expected_text="$1"
  if ! printf '%s\n' "${CASE_OUTPUT}" | grep -Fq "${expected_text}"; then
    echo "${CASE_OUTPUT}"
    echo "Case failed: expected output to contain '${expected_text}'."
    exit 1
  fi
}

assert_combo_rows() {
  local output_file="$1"
  local expected_rows="$2"
  local actual_rows

  if [ ! -f "${output_file}" ]; then
    echo "Case failed: expected output file to exist: ${output_file}"
    exit 1
  fi

  actual_rows="$(grep -Ev '^[[:space:]]*(#|$)' "${output_file}" || true)"

  if [ "${actual_rows}" != "${expected_rows}" ]; then
    echo "Case failed: warmup combo output mismatch."
    echo "Expected rows:"
    printf '%s\n' "${expected_rows}"
    echo "Actual rows:"
    printf '%s\n' "${actual_rows}"
    echo "Raw file:"
    cat "${output_file}"
    exit 1
  fi
}

echo "Running warmup combo fixture regression suite..."

case_one_output="${TMP_OUTPUT_DIR}/case-one.txt"
run_fixture_case \
  0 \
  "tiered RPC output interleaves free/premium combos with dedupe and limit enforcement" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="fixture-service-role-key" \
  WARMUP_COMBOS_GENERATED_FILE="${case_one_output}" \
  WARMUP_LIMIT="4" WARMUP_LOOKBACK_DAYS="30" INCLUDE_PREMIUM="true" \
  MOCK_TIER_FREE_STATUS="200" \
  MOCK_TIER_FREE_BODY='[{"zodiac_sign":"Aries","mbti_type":"INTJ"},{"zodiac_sign":"Gemini","mbti_type":"ENFP"},{"zodiac_sign":"Cancer","mbti_type":"ISFJ"}]' \
  MOCK_TIER_PREMIUM_STATUS="200" \
  MOCK_TIER_PREMIUM_BODY='[{"zodiac_sign":"Leo","mbti_type":"ENTJ"},{"zodiac_sign":"Gemini","mbti_type":"ENFP"},{"zodiac_sign":"Pisces","mbti_type":"INFP"}]' \
  MOCK_LEGACY_STATUS="500" \
  MOCK_LEGACY_BODY='{"message":"legacy-not-used"}' \
  bash "${BUILD_SCRIPT}"
assert_combo_rows "${case_one_output}" "$(cat <<'EOF'
Aries|INTJ
Leo|ENTJ
Gemini|ENFP
Cancer|ISFJ
EOF
)"

case_two_output="${TMP_OUTPUT_DIR}/case-two.txt"
run_fixture_case \
  0 \
  "premium tier RPC failure falls back to free-tier list without aborting generation" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  SUPABASE_PROJECT_REF="fixture-project" \
  SUPABASE_SERVICE_ROLE_KEY="fixture-service-role-key" \
  WARMUP_COMBOS_GENERATED_FILE="${case_two_output}" \
  WARMUP_LIMIT="5" WARMUP_LOOKBACK_DAYS="30" INCLUDE_PREMIUM="true" \
  MOCK_TIER_FREE_STATUS="200" \
  MOCK_TIER_FREE_BODY='[{"zodiac_sign":"Taurus","mbti_type":"ISTJ"},{"zodiac_sign":"Virgo","mbti_type":"INTP"}]' \
  MOCK_TIER_PREMIUM_STATUS="503" \
  MOCK_TIER_PREMIUM_BODY='{"message":"premium-tier-rpc-unavailable"}' \
  MOCK_LEGACY_STATUS="500" \
  MOCK_LEGACY_BODY='{"message":"legacy-not-used"}' \
  bash "${BUILD_SCRIPT}"
assert_combo_rows "${case_two_output}" "$(cat <<'EOF'
Taurus|ISTJ
Virgo|INTP
EOF
)"
assert_case_output_contains "Warning: combo RPC /rest/v1/rpc/get_popular_warmup_combos_by_tier failed with HTTP 503."

case_three_output="${TMP_OUTPUT_DIR}/case-three.txt"
run_fixture_case \
  0 \
  "legacy RPC fallback is used when tiered RPC cannot resolve combos" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="fixture-service-role-key" \
  WARMUP_COMBOS_GENERATED_FILE="${case_three_output}" \
  WARMUP_LIMIT="3" WARMUP_LOOKBACK_DAYS="30" INCLUDE_PREMIUM="true" \
  MOCK_TIER_FREE_STATUS="500" \
  MOCK_TIER_FREE_BODY='{"message":"tier-free-failed"}' \
  MOCK_TIER_PREMIUM_STATUS="500" \
  MOCK_TIER_PREMIUM_BODY='{"message":"tier-premium-failed"}' \
  MOCK_LEGACY_STATUS="200" \
  MOCK_LEGACY_BODY='[{"zodiac_sign":"Libra","mbti_type":"ENFJ"},{"zodiac_sign":"Scorpio","mbti_type":"INTP"},{"zodiac_sign":"Pisces","mbti_type":"INFP"}]' \
  bash "${BUILD_SCRIPT}"
assert_combo_rows "${case_three_output}" "$(cat <<'EOF'
Libra|ENFJ
Scorpio|INTP
Pisces|INFP
EOF
)"
assert_case_output_contains "Falling back to legacy combo RPC."

case_four_output="${TMP_OUTPUT_DIR}/case-four.txt"
run_fixture_case \
  1 \
  "script fails when both tiered and legacy combo RPCs are unavailable" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="fixture-service-role-key" \
  WARMUP_COMBOS_GENERATED_FILE="${case_four_output}" \
  WARMUP_LIMIT="3" WARMUP_LOOKBACK_DAYS="30" INCLUDE_PREMIUM="true" \
  MOCK_TIER_FREE_STATUS="500" \
  MOCK_TIER_FREE_BODY='{"message":"tier-free-failed"}' \
  MOCK_TIER_PREMIUM_STATUS="500" \
  MOCK_TIER_PREMIUM_BODY='{"message":"tier-premium-failed"}' \
  MOCK_LEGACY_STATUS="500" \
  MOCK_LEGACY_BODY='{"message":"legacy-failed"}' \
  bash "${BUILD_SCRIPT}"
assert_case_output_contains "Error: unable to resolve warmup combos from tiered or legacy RPC."

echo ""
echo "Warmup combo fixture regression suite passed."
