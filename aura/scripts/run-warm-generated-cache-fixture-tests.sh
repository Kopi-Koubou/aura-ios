#!/bin/bash
# Runs fixture-mode regression checks for warm-generated-cache orchestration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/warm-generated-cache.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Warm-cache fixture tests failed: could not locate repository root."
  exit 1
fi

WARM_SCRIPT="${REPO_ROOT}/scripts/warm-generated-cache.sh"

for dependency in mktemp grep; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Warm-cache fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${WARM_SCRIPT}" ]; then
  echo "Warm-cache fixture tests failed: missing script ${WARM_SCRIPT}."
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

counter_file="${MOCK_CURL_COUNTER_FILE:-}"
if [ -z "${counter_file}" ]; then
  echo "mock curl: missing MOCK_CURL_COUNTER_FILE" >&2
  exit 1
fi

output_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output_file="${2:-}"
      shift 2
      ;;
    -d|-X|-H|-w)
      shift 2
      ;;
    -s|-S|-sS|--silent|--show-error)
      shift
      ;;
    http://*|https://*)
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

if [ ! -f "${counter_file}" ]; then
  printf '0' > "${counter_file}"
fi

call_index="$(( $(cat "${counter_file}") + 1 ))"
printf '%s' "${call_index}" > "${counter_file}"

status="200"
body='{"cached":false}'
exit_code=0

case "${MOCK_CURL_SCENARIO:-all_success}" in
  all_success)
    if [ "${call_index}" -eq 1 ]; then
      body='{"cached": true}'
    fi
    ;;
  http_fail_first)
    if [ "${call_index}" -eq 1 ]; then
      status="503"
      body='{"error":"upstream_unavailable"}'
    fi
    ;;
  transport_fail_first)
    if [ "${call_index}" -eq 1 ]; then
      status="000"
      body='{"error":"connection_reset"}'
      exit_code=7
    fi
    ;;
  *)
    status="500"
    body='{"error":"unknown_mock_scenario"}'
    ;;
esac

printf '%s' "${body}" > "${output_file}"
printf '%s' "${status}"
exit "${exit_code}"
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

assert_call_count() {
  local counter_file="$1"
  local expected_count="$2"
  local actual_count

  if [ ! -f "${counter_file}" ]; then
    echo "Case failed: missing counter file ${counter_file}."
    exit 1
  fi

  actual_count="$(cat "${counter_file}")"
  if [ "${actual_count}" != "${expected_count}" ]; then
    echo "Case failed: expected ${expected_count} warm-cache requests, got ${actual_count}."
    exit 1
  fi
}

assert_metrics_file_contains() {
  local metrics_file="$1"
  local expected_text="$2"

  if [ ! -f "${metrics_file}" ]; then
    echo "Case failed: expected metrics file ${metrics_file}."
    exit 1
  fi

  if ! grep -Fq "${expected_text}" "${metrics_file}"; then
    echo "Case failed: expected metrics file ${metrics_file} to contain '${expected_text}'."
    cat "${metrics_file}"
    exit 1
  fi
}

combos_file="${TMP_OUTPUT_DIR}/fixture-combos.txt"
cat > "${combos_file}" <<'EOF'
Aries|INTJ
Taurus|ENFP
EOF

echo "Running warm-cache fixture regression suite..."

case_one_counter="${TMP_OUTPUT_DIR}/case-one.counter"
case_one_metrics="${TMP_OUTPUT_DIR}/case-one.metrics.json"
printf '0' > "${case_one_counter}"
run_fixture_case \
  0 \
  "cache-hit detection handles spaced JSON and honors warmup limits" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_one_counter}" \
  MOCK_CURL_SCENARIO="all_success" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="0" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_METRICS_FILE="${case_one_metrics}" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "Combos limit: 1 (from 2 configured)"
assert_case_output_contains "Total requests: 2"
assert_case_output_contains "Cache hits:     1"
assert_case_output_contains "Newly generated:1"
assert_case_output_contains "Retry attempts:   0"
assert_case_output_contains "Metrics file:     ${case_one_metrics}"
assert_call_count "${case_one_counter}" "2"
assert_metrics_file_contains "${case_one_metrics}" '"total_requests": 2'
assert_metrics_file_contains "${case_one_metrics}" '"successful_requests": 2'
assert_metrics_file_contains "${case_one_metrics}" '"failed_requests": 0'
assert_metrics_file_contains "${case_one_metrics}" '"outcome": "success"'
assert_metrics_file_contains "${case_one_metrics}" '"exit_code": 0'
assert_metrics_file_contains "${case_one_metrics}" '"max_retry_rate_percent": null'

case_two_counter="${TMP_OUTPUT_DIR}/case-two.counter"
case_two_metrics="${TMP_OUTPUT_DIR}/case-two.metrics.json"
printf '0' > "${case_two_counter}"
run_fixture_case \
  1 \
  "HTTP failures are counted and processing continues for subsequent requests" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_two_counter}" \
  MOCK_CURL_SCENARIO="http_fail_first" \
  SUPABASE_PROJECT_REF="fixture-project" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="0" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_METRICS_FILE="${case_two_metrics}" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "(HTTP 503)"
assert_case_output_contains "Successful:     1"
assert_case_output_contains "Failed:         1"
assert_case_output_contains "Metrics file:     ${case_two_metrics}"
assert_call_count "${case_two_counter}" "2"
assert_metrics_file_contains "${case_two_metrics}" '"failed_requests": 1'
assert_metrics_file_contains "${case_two_metrics}" '"outcome": "failed_requests"'
assert_metrics_file_contains "${case_two_metrics}" '"exit_code": 1'

case_three_counter="${TMP_OUTPUT_DIR}/case-three.counter"
printf '0' > "${case_three_counter}"
run_fixture_case \
  1 \
  "curl transport failures are reported without aborting the warmup loop" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_three_counter}" \
  MOCK_CURL_SCENARIO="transport_fail_first" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="0" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "curl transport error 7"
assert_case_output_contains "Successful:     1"
assert_case_output_contains "Failed:         1"
assert_call_count "${case_three_counter}" "2"

case_four_counter="${TMP_OUTPUT_DIR}/case-four.counter"
printf '0' > "${case_four_counter}"
run_fixture_case \
  0 \
  "retryable HTTP failures are retried and can recover within bounded attempts" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_four_counter}" \
  MOCK_CURL_SCENARIO="http_fail_first" \
  SUPABASE_PROJECT_REF="fixture-project" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="1" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "(HTTP 503) retrying attempt 2/2 after 0s"
assert_case_output_contains "Successful:     2"
assert_case_output_contains "Failed:         0"
assert_case_output_contains "Requests retried: 1"
assert_case_output_contains "Retry attempts:   1"
assert_call_count "${case_four_counter}" "3"

case_five_counter="${TMP_OUTPUT_DIR}/case-five.counter"
printf '0' > "${case_five_counter}"
run_fixture_case \
  0 \
  "curl transport failures are retried when configured and recovery keeps warmup successful" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_five_counter}" \
  MOCK_CURL_SCENARIO="transport_fail_first" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="1" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "curl transport error 7) retrying attempt 2/2 after 0s"
assert_case_output_contains "Successful:     2"
assert_case_output_contains "Failed:         0"
assert_case_output_contains "Requests retried: 1"
assert_case_output_contains "Retry attempts:   1"
assert_call_count "${case_five_counter}" "3"

case_six_counter="${TMP_OUTPUT_DIR}/case-six.counter"
case_six_metrics="${TMP_OUTPUT_DIR}/case-six.metrics.json"
printf '0' > "${case_six_counter}"
run_fixture_case \
  2 \
  "elevated retry rate triggers explicit threshold failure even after successful retries" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_six_counter}" \
  MOCK_CURL_SCENARIO="http_fail_first" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="1" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_MAX_RETRY_RATE_PERCENT="40" \
  WARMUP_METRICS_FILE="${case_six_metrics}" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "Retry rate:       50%"
assert_case_output_contains "elevated retry rate (50% > 40%)"
assert_case_output_contains "Metrics file:     ${case_six_metrics}"
assert_call_count "${case_six_counter}" "3"
assert_metrics_file_contains "${case_six_metrics}" '"requests_retried": 1'
assert_metrics_file_contains "${case_six_metrics}" '"retry_rate_percent": 50'
assert_metrics_file_contains "${case_six_metrics}" '"max_retry_rate_percent": 40'
assert_metrics_file_contains "${case_six_metrics}" '"outcome": "retry_rate_exceeded"'
assert_metrics_file_contains "${case_six_metrics}" '"exit_code": 2'

case_seven_counter="${TMP_OUTPUT_DIR}/case-seven.counter"
printf '0' > "${case_seven_counter}"
run_fixture_case \
  0 \
  "retry-rate gate passes when retry rate is equal to threshold" \
  env PATH="${MOCK_BIN_DIR}:${PATH}" \
  MOCK_CURL_COUNTER_FILE="${case_seven_counter}" \
  MOCK_CURL_SCENARIO="http_fail_first" \
  SUPABASE_BASE_URL="https://fixture.supabase.co" \
  SUPABASE_ANON_KEY="fixture-anon-key" \
  CACHE_WARM_SECRET="fixture-cache-warm-secret" \
  WARMUP_COMBOS_FILE="${combos_file}" \
  WARMUP_LIMIT="1" INCLUDE_PREMIUM="false" \
  WARMUP_REQUEST_RETRIES="1" WARMUP_RETRY_DELAY_SECONDS="0" \
  WARMUP_MAX_RETRY_RATE_PERCENT="50" \
  WARMUP_CATEGORIES="Career, Love" \
  TARGET_DATE="2026-03-05" \
  bash "${WARM_SCRIPT}"
assert_case_output_contains "Retry rate:       50%"
assert_case_output_contains "Cache warmup completed successfully."
assert_call_count "${case_seven_counter}" "3"

echo ""
echo "Warm-cache fixture regression suite passed."
