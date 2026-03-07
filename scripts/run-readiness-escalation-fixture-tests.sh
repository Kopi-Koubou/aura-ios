#!/bin/bash
# Runs fixture-mode and mocked live-mode regression checks for readiness escalation handling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""
FAKE_CURL_BIN_DIR=""
TEMP_PATHS=()

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/run-readiness-escalation.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Readiness escalation fixture tests failed: could not locate repository root."
  exit 1
fi

ESCALATION_SCRIPT="${REPO_ROOT}/scripts/run-readiness-escalation.sh"

for dependency in jq; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Readiness escalation fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${ESCALATION_SCRIPT}" ]; then
  echo "Readiness escalation fixture tests failed: missing script ${ESCALATION_SCRIPT}."
  exit 1
fi

register_temp_path() {
  local temp_path="$1"
  TEMP_PATHS+=("${temp_path}")
}

cleanup_temp_paths() {
  local temp_path=""
  for temp_path in "${TEMP_PATHS[@]-}"; do
    [ -n "${temp_path}" ] && rm -rf "${temp_path}"
  done
}
trap cleanup_temp_paths EXIT

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

assert_case_output_not_contains() {
  local unexpected_text="$1"
  if printf '%s\n' "${CASE_OUTPUT}" | grep -Fq "${unexpected_text}"; then
    echo "${CASE_OUTPUT}"
    echo "Case failed: expected output to omit '${unexpected_text}'."
    exit 1
  fi
}

assert_file_contains() {
  local file_path="$1"
  local expected_text="$2"

  if ! grep -Fq "${expected_text}" "${file_path}"; then
    [ -f "${file_path}" ] && cat "${file_path}"
    echo "Case failed: expected ${file_path} to contain '${expected_text}'."
    exit 1
  fi
}

assert_file_exists() {
  local file_path="$1"
  if [ ! -f "${file_path}" ]; then
    echo "Case failed: expected file to exist: ${file_path}."
    exit 1
  fi
}

assert_file_not_contains() {
  local file_path="$1"
  local unexpected_text="$2"

  if [ -f "${file_path}" ] && grep -Fq "${unexpected_text}" "${file_path}"; then
    cat "${file_path}"
    echo "Case failed: expected ${file_path} to omit '${unexpected_text}'."
    exit 1
  fi
}

assert_json_field_equals() {
  local file_path="$1"
  local jq_filter="$2"
  local expected_value="$3"
  local actual_value=""

  if ! actual_value="$(jq -r "${jq_filter}" "${file_path}")"; then
    echo "Case failed: could not evaluate jq filter '${jq_filter}' for ${file_path}."
    cat "${file_path}"
    exit 1
  fi

  if [ "${actual_value}" != "${expected_value}" ]; then
    echo "Case failed: expected ${jq_filter} in ${file_path} to be '${expected_value}', got '${actual_value}'."
    cat "${file_path}"
    exit 1
  fi
}

create_temp_dir() {
  local temp_dir=""
  local temp_base=""
  local candidate_bases=()

  [ -n "${TMPDIR:-}" ] && candidate_bases+=("${TMPDIR%/}")
  [ -n "${HOME:-}" ] && candidate_bases+=("${HOME%/}/.tmp")
  candidate_bases+=("/tmp")

  if temp_dir="$(mktemp -d 2>/dev/null)"; then
    printf '%s\n' "${temp_dir}"
    return 0
  fi

  for temp_base in "${candidate_bases[@]}"; do
    [ -z "${temp_base}" ] && continue
    mkdir -p "${temp_base}" >/dev/null 2>&1 || continue
    if temp_dir="$(mktemp -d "${temp_base}/aura-readiness.XXXXXX" 2>/dev/null)"; then
      printf '%s\n' "${temp_dir}"
      return 0
    fi
  done

  echo "Readiness escalation fixture tests failed: unable to create temporary directory." >&2
  echo "Set TMPDIR to a writable directory and retry." >&2
  return 1
}

create_fake_curl_bin_dir() {
  local temp_dir=""
  if ! temp_dir="$(create_temp_dir)"; then
    exit 1
  fi
  register_temp_path "${temp_dir}"

  cat > "${temp_dir}/curl" <<'FAKECURL'
#!/bin/bash
set -euo pipefail

method="GET"
url=""
expect_method_value=0

for arg in "$@"; do
  if [ "${expect_method_value}" -eq 1 ]; then
    method="${arg}"
    expect_method_value=0
    continue
  fi

  if [ "${arg}" = "-X" ]; then
    expect_method_value=1
    continue
  fi

  case "${arg}" in
    http://*|https://*)
      url="${arg}"
      ;;
  esac
done

if [ -z "${url}" ]; then
  echo "fake curl: missing URL argument" >&2
  exit 1
fi

if [ -n "${FAKE_CURL_LOG_FILE:-}" ]; then
  printf '%s %s\n' "${method}" "${url}" >> "${FAKE_CURL_LOG_FILE}"
fi

if [[ "${url}" == https://hooks.example.invalid/* ]]; then
  printf '%s' "${FAKE_CURL_WEBHOOK_STATUS:-200}"
  exit 0
fi

if [[ "${url}" == *"/issues?state=open"* ]]; then
  page="$(printf '%s' "${url}" | sed -n 's/.*[?&]page=\([0-9][0-9]*\).*/\1/p')"
  [ -z "${page}" ] && page="1"
  payload_var="FAKE_CURL_OPEN_PAGE_${page}"
  status_var="FAKE_CURL_OPEN_PAGE_${page}_STATUS"
  payload="${!payload_var:-[]}"
  status="${!status_var:-200}"
  printf '%s\n%s' "${payload}" "${status}"
  exit 0
fi

if [[ "${url}" == *"/issues?state=closed"* ]]; then
  page="$(printf '%s' "${url}" | sed -n 's/.*[?&]page=\([0-9][0-9]*\).*/\1/p')"
  [ -z "${page}" ] && page="1"
  payload_var="FAKE_CURL_CLOSED_PAGE_${page}"
  status_var="FAKE_CURL_CLOSED_PAGE_${page}_STATUS"
  payload="${!payload_var:-[]}"
  status="${!status_var:-200}"
  printf '%s\n%s' "${payload}" "${status}"
  exit 0
fi

if [ "${method}" = "POST" ] && [[ "${url}" == */issues/*/comments ]]; then
  printf '%s\n%s' "${FAKE_CURL_COMMENT_RESPONSE:-{}}" "${FAKE_CURL_COMMENT_STATUS:-201}"
  exit 0
fi

if [ "${method}" = "PATCH" ] && [[ "${url}" == */issues/* ]] && [[ "${url}" != */comments ]]; then
  printf '%s\n%s' "${FAKE_CURL_PATCH_RESPONSE:-{}}" "${FAKE_CURL_PATCH_STATUS:-200}"
  exit 0
fi

if [ "${method}" = "POST" ] && [[ "${url}" == */issues ]] && [[ "${url}" != *"state="* ]]; then
  default_create_response='{"number":123}'
  printf '%s\n%s' "${FAKE_CURL_CREATE_RESPONSE:-${default_create_response}}" "${FAKE_CURL_CREATE_STATUS:-201}"
  exit 0
fi

echo "fake curl: unexpected request ${method} ${url}" >&2
exit 1
FAKECURL

  chmod +x "${temp_dir}/curl"
  FAKE_CURL_BIN_DIR="${temp_dir}"
}

echo "Running readiness escalation fixture regression suite..."

dry_case_dir="$(create_temp_dir)"
register_temp_path "${dry_case_dir}"
dry_case_metrics="${dry_case_dir}/dry-create.metrics.json"

run_fixture_case \
  0 \
  "auth fallback creates issue when no matching open issue exists" \
  env READINESS_ESCALATION_KIND="auth_fallback" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  ALERT_WEBHOOK_URL="https://hooks.example.invalid/aura" \
  LOOKBACK_DAYS="3" MAX_FALLBACKS="0" AUTH_CONTEXT_FILTER="missing" \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/123456" \
  READINESS_LOG_FILE="/tmp/non-existent-auth-readiness.log" \
  READINESS_ESCALATION_METRICS_FILE="${dry_case_metrics}" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Webhook attempted: true"
assert_case_output_contains "Webhook success:   true"
assert_case_output_contains "Issue action:      create"
assert_case_output_contains "Open pages scanned: 0"
assert_case_output_contains "Open match page:   0"
assert_case_output_contains "Closed pages scanned: 0"
assert_case_output_contains "Closed match page: 0"
assert_file_exists "${dry_case_metrics}"
assert_json_field_equals "${dry_case_metrics}" '.kind' 'auth_fallback'
assert_json_field_equals "${dry_case_metrics}" '.status' 'failure'
assert_json_field_equals "${dry_case_metrics}" '.issue_action' 'create'
assert_json_field_equals "${dry_case_metrics}" '.issue_number_raw' 'new'
assert_json_field_equals "${dry_case_metrics}" '.issue_number' 'null'
assert_json_field_equals "${dry_case_metrics}" '.webhook_attempted' 'true'
assert_json_field_equals "${dry_case_metrics}" '.webhook_success' 'true'
assert_json_field_equals "${dry_case_metrics}" '.strict_webhook_requirement_failed' 'false'
assert_json_field_equals "${dry_case_metrics}" '.open_scan_hit_page_limit' 'false'
assert_json_field_equals "${dry_case_metrics}" '.closed_scan_hit_page_limit' 'false'

run_fixture_case \
  1 \
  "open-issue page depth must be a positive integer" \
  env READINESS_ESCALATION_KIND="auth_fallback" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES="0" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/119999" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES must be a positive integer."

run_fixture_case \
  1 \
  "closed-issue page depth must be a positive integer" \
  env READINESS_ESCALATION_KIND="auth_fallback" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES="0" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/120000" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES must be a positive integer."

run_fixture_case \
  0 \
  "cache degradation comments on labeled escalation issue even after title rename" \
  env READINESS_ESCALATION_KIND="cache_degradation" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[{"number":42,"title":"Cache incident renamed by operator","labels":[{"name":"ops-readiness"},{"name":"ops-readiness-cache-degradation"}],"body":"Manual title update."}]' \
  LOOKBACK_DAYS="2" MAX_DEGRADATIONS="1" PREMIUM_FILTER="premium" REASON_FILTER="all" \
  SUPABASE_BASE_URL="https://aura-staging.supabase.co" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/654321" \
  READINESS_LOG_FILE="/tmp/non-existent-cache-readiness.log" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Webhook attempted: false"
assert_case_output_contains "Issue action:      comment"
assert_case_output_contains "Issue number:      42"

run_fixture_case \
  0 \
  "auth fallback reopens matching closed escalation issue before creating a new one" \
  env READINESS_ESCALATION_KIND="auth_fallback" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  READINESS_ESCALATION_CLOSED_ISSUES_JSON='[{"number":57,"title":"Closed auth readiness incident","body":"<!-- aura-readiness-escalation:auth_fallback -->\nAutomated auth fallback readiness gate failed on 2026-03-03."}]' \
  LOOKBACK_DAYS="2" MAX_FALLBACKS="0" AUTH_CONTEXT_FILTER="all" \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/700000" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      reopen"
assert_case_output_contains "Issue number:      57"

strict_case_dir="$(create_temp_dir)"
register_temp_path "${strict_case_dir}"
strict_case_metrics="${strict_case_dir}/strict-webhook.metrics.json"

run_fixture_case \
  1 \
  "strict webhook requirement fails when webhook delivery is simulated as failed" \
  env READINESS_ESCALATION_KIND="auth_fallback" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_DRY_WEBHOOK_RESULT="failure" \
  READINESS_ESCALATION_REQUIRE_WEBHOOK_SUCCESS="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  ALERT_WEBHOOK_URL="https://hooks.example.invalid/aura" \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/777777" \
  READINESS_ESCALATION_METRICS_FILE="${strict_case_metrics}" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Escalation failed strict webhook requirement."
assert_file_exists "${strict_case_metrics}"
assert_json_field_equals "${strict_case_metrics}" '.issue_action' 'create'
assert_json_field_equals "${strict_case_metrics}" '.strict_webhook_required' 'true'
assert_json_field_equals "${strict_case_metrics}" '.strict_webhook_requirement_failed' 'true'
assert_json_field_equals "${strict_case_metrics}" '.webhook_attempted' 'true'
assert_json_field_equals "${strict_case_metrics}" '.webhook_success' 'false'

run_fixture_case \
  0 \
  "recovery closes legacy auth issue when title changed but body marker prefix remains" \
  env READINESS_ESCALATION_KIND="auth_fallback" READINESS_ESCALATION_STATUS="recovered" \
  READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[{"number":71,"title":"Auth incident renamed manually","body":"Automated auth fallback readiness gate failed on 2026-03-04.\n\n- Workflow run: https://github.com/example/aura/actions/runs/100001"}]' \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/888888" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      close"
assert_case_output_contains "Issue number:      71"

run_fixture_case \
  0 \
  "recovery no-ops when no matching cache degradation escalation issue exists" \
  env READINESS_ESCALATION_KIND="cache_degradation" READINESS_ESCALATION_STATUS="recovered" \
  READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/999999" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      noop"
assert_case_output_contains "Issue number:      none"

run_fixture_case \
  0 \
  "warmup calibration low-confidence creates issue with calibration labels" \
  env READINESS_ESCALATION_KIND="warmup_threshold_calibration" READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[]' \
  CALIBRATION_WORKFLOW_FILE="warmup-threshold-calibration.yml" \
  CALIBRATION_ESCALATION_EVENT_NAME="schedule" \
  CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD="3" \
  CALIBRATION_CURRENT_LOW_CONFIDENCE_STREAK="3" \
  CALIBRATION_LOW_CONFIDENCE_REASON="sample size below minimum confidence threshold (3 < 10)." \
  CALIBRATION_FAIL_ON_LOW_CONFIDENCE="false" \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/1000001" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      create"
assert_case_output_contains "Issue number:      new"

run_fixture_case \
  0 \
  "readiness page-limit calibration recovery closes marker-matched issue" \
  env READINESS_ESCALATION_KIND="readiness_page_limit_calibration" READINESS_ESCALATION_STATUS="recovered" \
  READINESS_ESCALATION_DRY_RUN="true" \
  READINESS_ESCALATION_OPEN_ISSUES_JSON='[{"number":91,"title":"Calibration incident renamed manually","body":"<!-- aura-calibration-escalation:readiness_page_limit -->\nAutomated readiness page-limit calibration remained low-confidence on 2026-03-04."}]' \
  CALIBRATION_WORKFLOW_FILE="readiness-page-limit-calibration.yml" \
  CALIBRATION_ESCALATION_EVENT_NAME="schedule" \
  CALIBRATION_LOW_CONFIDENCE_STREAK_THRESHOLD="3" \
  CALIBRATION_CURRENT_LOW_CONFIDENCE_STREAK="0" \
  CALIBRATION_LOW_CONFIDENCE_REASON="(none)" \
  CALIBRATION_FAIL_ON_LOW_CONFIDENCE="false" \
  SUPABASE_PROJECT_REF="aura-staging" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/1000002" \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      close"
assert_case_output_contains "Issue number:      91"

echo ""
echo "Running mocked live-mode escalation regression suite..."

create_fake_curl_bin_dir

live_case_dir="$(create_temp_dir)"
register_temp_path "${live_case_dir}"
live_case_log="${live_case_dir}/curl-open-page2.log"

run_fixture_case \
  0 \
  "live mode comments on matching open issue discovered on page 2" \
  env PATH="${FAKE_CURL_BIN_DIR}:${PATH}" \
  READINESS_ESCALATION_KIND="auth_fallback" \
  READINESS_ESCALATION_DRY_RUN="false" \
  READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES="2" \
  READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES="2" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/110000" \
  SUPABASE_PROJECT_REF="aura-staging" \
  GITHUB_TOKEN="test-token" \
  GITHUB_REPOSITORY="example/aura" \
  GITHUB_API_URL="https://api.example.test" \
  FAKE_CURL_LOG_FILE="${live_case_log}" \
  FAKE_CURL_OPEN_PAGE_1='[{"number":12,"title":"Unrelated incident","labels":[{"name":"bug"}]}]' \
  FAKE_CURL_OPEN_PAGE_2='[{"number":42,"title":"Auth fallback readiness gate failing","labels":[{"name":"ops-readiness"},{"name":"ops-readiness-auth-fallback"}]}]' \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      comment"
assert_case_output_contains "Issue number:      42"
assert_case_output_contains "Open pages scanned: 2"
assert_case_output_contains "Open match page:   2"
assert_case_output_contains "Closed pages scanned: 0"
assert_case_output_contains "Closed match page: 0"
assert_file_contains "${live_case_log}" "state=open&per_page=100&page=2"

live_case_dir="$(create_temp_dir)"
register_temp_path "${live_case_dir}"
live_case_log="${live_case_dir}/curl-reopen.log"

run_fixture_case \
  0 \
  "live mode reopens matching closed issue when no open issue exists" \
  env PATH="${FAKE_CURL_BIN_DIR}:${PATH}" \
  READINESS_ESCALATION_KIND="auth_fallback" \
  READINESS_ESCALATION_DRY_RUN="false" \
  READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES="2" \
  READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES="2" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/120000" \
  SUPABASE_PROJECT_REF="aura-staging" \
  GITHUB_TOKEN="test-token" \
  GITHUB_REPOSITORY="example/aura" \
  GITHUB_API_URL="https://api.example.test" \
  FAKE_CURL_LOG_FILE="${live_case_log}" \
  FAKE_CURL_OPEN_PAGE_1='[]' \
  FAKE_CURL_CLOSED_PAGE_1='[{"number":13,"title":"closed unrelated","labels":[{"name":"bug"}]}]' \
  FAKE_CURL_CLOSED_PAGE_2='[{"number":57,"title":"Closed auth incident","labels":[{"name":"ops-readiness"},{"name":"ops-readiness-auth-fallback"}]}]' \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      reopen"
assert_case_output_contains "Issue number:      57"
assert_case_output_contains "Open pages scanned: 1"
assert_case_output_contains "Open match page:   0"
assert_case_output_contains "Closed pages scanned: 2"
assert_case_output_contains "Closed match page: 2"
assert_file_contains "${live_case_log}" "state=closed&per_page=100&page=2"

live_case_dir="$(create_temp_dir)"
register_temp_path "${live_case_dir}"
live_case_log="${live_case_dir}/curl-page-bounds.log"
live_case_metrics="${live_case_dir}/live-page-bounds.metrics.json"

run_fixture_case \
  0 \
  "live mode respects max-page bounds before creating a new issue" \
  env PATH="${FAKE_CURL_BIN_DIR}:${PATH}" \
  READINESS_ESCALATION_KIND="auth_fallback" \
  READINESS_ESCALATION_DRY_RUN="false" \
  READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES="1" \
  READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES="1" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/130000" \
  SUPABASE_PROJECT_REF="aura-staging" \
  GITHUB_TOKEN="test-token" \
  GITHUB_REPOSITORY="example/aura" \
  GITHUB_API_URL="https://api.example.test" \
  FAKE_CURL_LOG_FILE="${live_case_log}" \
  READINESS_ESCALATION_METRICS_FILE="${live_case_metrics}" \
  FAKE_CURL_OPEN_PAGE_1='[]' \
  FAKE_CURL_CLOSED_PAGE_1='[]' \
  FAKE_CURL_CREATE_RESPONSE='{"number":88}' \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Issue action:      create"
assert_case_output_contains "Issue number:      88"
assert_case_output_contains "Open pages scanned: 1"
assert_case_output_contains "Open match page:   0"
assert_case_output_contains "Closed pages scanned: 1"
assert_case_output_contains "Closed match page: 0"
assert_file_not_contains "${live_case_log}" "state=open&per_page=100&page=2"
assert_file_not_contains "${live_case_log}" "state=closed&per_page=100&page=2"
assert_file_exists "${live_case_metrics}"
assert_json_field_equals "${live_case_metrics}" '.dry_run' 'false'
assert_json_field_equals "${live_case_metrics}" '.issue_action' 'create'
assert_json_field_equals "${live_case_metrics}" '.issue_number' '88'
assert_json_field_equals "${live_case_metrics}" '.open_issues_max_pages' '1'
assert_json_field_equals "${live_case_metrics}" '.closed_issues_max_pages' '1'
assert_json_field_equals "${live_case_metrics}" '.open_scan_hit_page_limit' 'true'
assert_json_field_equals "${live_case_metrics}" '.closed_scan_hit_page_limit' 'true'

run_fixture_case \
  1 \
  "live mode fails fast when GitHub open-issues listing returns non-2xx" \
  env PATH="${FAKE_CURL_BIN_DIR}:${PATH}" \
  READINESS_ESCALATION_KIND="auth_fallback" \
  READINESS_ESCALATION_DRY_RUN="false" \
  READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES="2" \
  READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES="2" \
  READINESS_RUN_URL="https://github.com/example/aura/actions/runs/140000" \
  SUPABASE_PROJECT_REF="aura-staging" \
  GITHUB_TOKEN="test-token" \
  GITHUB_REPOSITORY="example/aura" \
  GITHUB_API_URL="https://api.example.test" \
  FAKE_CURL_OPEN_PAGE_1='{"message":"boom"}' \
  FAKE_CURL_OPEN_PAGE_1_STATUS='500' \
  bash "${ESCALATION_SCRIPT}"
assert_case_output_contains "Failed to list open issues page 1 (HTTP 500)."
assert_case_output_not_contains "Readiness escalation handling complete."

echo ""
echo "Readiness escalation fixture regression suite passed."
