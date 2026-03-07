#!/bin/bash
# Runs fixture-mode regression checks for readiness gates and escalation handling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/check-auth-fallback-readiness.sh" ] \
    && [ -f "${SEARCH_DIR}/scripts/check-cache-degradation-readiness.sh" ] \
    && [ -f "${SEARCH_DIR}/scripts/run-readiness-escalation-fixture-tests.sh" ] \
    && [ -f "${SEARCH_DIR}/scripts/run-readiness-escalation-metrics-summary-fixture-tests.sh" ] \
    && [ -f "${SEARCH_DIR}/scripts/run-readiness-page-limit-apply-fixture-tests.sh" ] \
    && [ -f "${SEARCH_DIR}/scripts/run-propose-readiness-page-limit-fixture-tests.sh" ] \
    && [ -f "${SEARCH_DIR}/scripts/run-resolve-calibration-low-confidence-escalation-fixture-tests.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Readiness fixture tests failed: could not locate repository root."
  exit 1
fi

AUTH_SCRIPT="${REPO_ROOT}/scripts/check-auth-fallback-readiness.sh"
CACHE_SCRIPT="${REPO_ROOT}/scripts/check-cache-degradation-readiness.sh"
ESCALATION_SCRIPT="${REPO_ROOT}/scripts/run-readiness-escalation-fixture-tests.sh"
SUMMARY_FIXTURE_SCRIPT="${REPO_ROOT}/scripts/run-readiness-escalation-metrics-summary-fixture-tests.sh"
APPLY_FIXTURE_SCRIPT="${REPO_ROOT}/scripts/run-readiness-page-limit-apply-fixture-tests.sh"
PROPOSE_FIXTURE_SCRIPT="${REPO_ROOT}/scripts/run-propose-readiness-page-limit-fixture-tests.sh"
RESOLVE_ESCALATION_FIXTURE_SCRIPT="${REPO_ROOT}/scripts/run-resolve-calibration-low-confidence-escalation-fixture-tests.sh"

for dependency in jq; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Readiness fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

for script_path in \
  "${AUTH_SCRIPT}" \
  "${CACHE_SCRIPT}" \
  "${ESCALATION_SCRIPT}" \
  "${SUMMARY_FIXTURE_SCRIPT}" \
  "${APPLY_FIXTURE_SCRIPT}" \
  "${PROPOSE_FIXTURE_SCRIPT}" \
  "${RESOLVE_ESCALATION_FIXTURE_SCRIPT}"; do
  if [ ! -f "${script_path}" ]; then
    echo "Readiness fixture tests failed: missing script ${script_path}."
    exit 1
  fi
done

run_fixture_case() {
  local expected_exit="$1"
  local label="$2"
  local payload="$3"
  shift 3

  echo ""
  echo "Case: ${label}"

  set +e
  printf '%s\n' "${payload}" | "$@"
  local actual_exit=$?
  set -e

  if [ "${actual_exit}" -ne "${expected_exit}" ]; then
    echo "Case failed: expected exit ${expected_exit}, got ${actual_exit}."
    exit 1
  fi

  echo "Case passed."
}

AUTH_FIXTURE_PAYLOAD='[{"date":"2026-03-04","category":"daily","auth_context":"missing","fallback_count":1,"updated_at":"2026-03-04T00:05:00Z"},{"date":"2026-03-04","category":"love","auth_context":"invalid","fallback_count":0,"updated_at":"2026-03-04T00:07:00Z"}]'

CACHE_FIXTURE_PAYLOAD='[{"date":"2026-03-04","category":"daily","is_premium":true,"resolution_reason":"generated_shared_content_cache_temporarily_unavailable","degradation_count":1,"lookup_failed_count":0,"persist_failed_count":0,"temporarily_unavailable_count":1,"updated_at":"2026-03-04T00:09:00Z"},{"date":"2026-03-04","category":"career","is_premium":false,"resolution_reason":"shared_content_cache_unavailable","degradation_count":0,"lookup_failed_count":0,"persist_failed_count":0,"temporarily_unavailable_count":0,"updated_at":"2026-03-04T00:12:00Z"}]'

echo "Running readiness fixture regression suite..."

run_fixture_case \
  0 \
  "auth-fallback passes when threshold allows observed fallback count" \
  "${AUTH_FIXTURE_PAYLOAD}" \
  env LOOKBACK_DAYS=2 MAX_FALLBACKS=1 AUTH_CONTEXT_FILTER=all READINESS_JSON_FILE=- \
  bash "${AUTH_SCRIPT}"

run_fixture_case \
  2 \
  "auth-fallback fails when threshold is stricter than observed fallback count" \
  "${AUTH_FIXTURE_PAYLOAD}" \
  env LOOKBACK_DAYS=2 MAX_FALLBACKS=0 AUTH_CONTEXT_FILTER=all READINESS_JSON_FILE=- \
  bash "${AUTH_SCRIPT}"

run_fixture_case \
  0 \
  "cache degradation passes when threshold allows observed degradation count" \
  "${CACHE_FIXTURE_PAYLOAD}" \
  env LOOKBACK_DAYS=2 MAX_DEGRADATIONS=1 PREMIUM_FILTER=all REASON_FILTER=all READINESS_JSON_FILE=- \
  bash "${CACHE_SCRIPT}"

run_fixture_case \
  2 \
  "cache degradation fails when premium-filtered threshold is exceeded" \
  "${CACHE_FIXTURE_PAYLOAD}" \
  env LOOKBACK_DAYS=2 MAX_DEGRADATIONS=0 PREMIUM_FILTER=premium REASON_FILTER=all READINESS_JSON_FILE=- \
  bash "${CACHE_SCRIPT}"

echo ""
echo "Running readiness escalation fixture suite..."
bash "${ESCALATION_SCRIPT}"

echo ""
echo "Running readiness escalation metrics summary fixture suite..."
bash "${SUMMARY_FIXTURE_SCRIPT}"

echo ""
echo "Running readiness page-limit apply fixture suite..."
bash "${APPLY_FIXTURE_SCRIPT}"

echo ""
echo "Running readiness page-limit calibration fixture suite..."
bash "${PROPOSE_FIXTURE_SCRIPT}"

echo ""
echo "Running calibration low-confidence escalation resolver fixture suite..."
bash "${RESOLVE_ESCALATION_FIXTURE_SCRIPT}"

echo ""
echo "Readiness fixture regression suite passed."
