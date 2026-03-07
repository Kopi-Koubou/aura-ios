#!/bin/bash
# Runs fixture-mode regression checks for auth rollout rehearsal without Supabase secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/rehearse-auth-rollout.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Auth rollout fixture tests failed: could not locate repository root."
  exit 1
fi

REHEARSAL_SCRIPT="${REPO_ROOT}/scripts/rehearse-auth-rollout.sh"

for dependency in jq; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Auth rollout fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -f "${REHEARSAL_SCRIPT}" ]; then
  echo "Auth rollout fixture tests failed: missing script ${REHEARSAL_SCRIPT}."
  exit 1
fi

run_fixture_case() {
  local expected_exit="$1"
  local label="$2"
  local fixture_json="$3"
  shift 3

  echo ""
  echo "Case: ${label}"

  set +e
  REHEARSAL_FIXTURE_JSON="${fixture_json}" "$@"
  local actual_exit=$?
  set -e

  if [ "${actual_exit}" -ne "${expected_exit}" ]; then
    echo "Case failed: expected exit ${expected_exit}, got ${actual_exit}."
    exit 1
  fi

  echo "Case passed."
}

STATIC_USER_ID="3f5e51b5-57f4-4dc6-b069-1f65f48d64f7"
STATIC_USER_ID_UPPER="3F5E51B5-57F4-4DC6-B069-1F65F48D64F7"

FIXTURE_PASS_STATIC='{"responses":{"lower":{"http_status":200,"headers":{"x-aura-auth-mode":"audit","x-aura-auth-context":"authenticated","x-aura-auth-fallback":"0"},"body":{"reading":{"id":"reading-static-1","user_id":"3f5e51b5-57f4-4dc6-b069-1f65f48d64f7","fortune_score":77,"lucky_numbers":[3,11,19,27,35],"power_colors":["Gold","Teal","Amber"]}}},"upper":{"http_status":200,"headers":{"x-aura-auth-mode":"audit","x-aura-auth-context":"authenticated","x-aura-auth-fallback":"0"},"body":{"reading":{"id":"reading-static-1","user_id":"3F5E51B5-57F4-4DC6-B069-1F65F48D64F7","fortune_score":77,"lucky_numbers":[3,11,19,27,35],"power_colors":["Gold","Teal","Amber"]}}}}}'

FIXTURE_PASS_PASSWORD='{"login":{"http_status":200,"body":{"access_token":"fixture-login-token","user":{"id":"7a4d9555-26eb-4f12-a5ba-168951f56b19"}}},"responses":{"lower":{"http_status":200,"headers":{"x-aura-auth-mode":"audit","x-aura-auth-context":"authenticated","x-aura-auth-fallback":"0"},"body":{"reading":{"id":"reading-login-1","user_id":"7a4d9555-26eb-4f12-a5ba-168951f56b19","fortune_score":68,"lucky_numbers":[5,14,22,49,90],"power_colors":["Emerald","Silver","Crimson"]}}},"upper":{"http_status":200,"headers":{"x-aura-auth-mode":"audit","x-aura-auth-context":"authenticated","x-aura-auth-fallback":"0"},"body":{"reading":{"id":"reading-login-1","user_id":"7A4D9555-26EB-4F12-A5BA-168951F56B19","fortune_score":68,"lucky_numbers":[5,14,22,49,90],"power_colors":["Emerald","Silver","Crimson"]}}}}}'

FIXTURE_FAIL_DRIFT='{"responses":{"lower":{"http_status":200,"headers":{"x-aura-auth-mode":"audit","x-aura-auth-context":"authenticated","x-aura-auth-fallback":"0"},"body":{"reading":{"id":"reading-drift-1","user_id":"3f5e51b5-57f4-4dc6-b069-1f65f48d64f7","fortune_score":80,"lucky_numbers":[1,2,3,4,5],"power_colors":["Teal","Gold","Silver"]}}},"upper":{"http_status":200,"headers":{"x-aura-auth-mode":"audit","x-aura-auth-context":"authenticated","x-aura-auth-fallback":"0"},"body":{"reading":{"id":"reading-drift-1","user_id":"3F5E51B5-57F4-4DC6-B069-1F65F48D64F7","fortune_score":81,"lucky_numbers":[1,2,3,4,5],"power_colors":["Teal","Gold","Silver"]}}}}}'

echo "Running auth rollout fixture regression suite..."

run_fixture_case \
  0 \
  "static token source passes with casing-stable deterministic extras" \
  "${FIXTURE_PASS_STATIC}" \
  env SUPABASE_ANON_KEY="fixture-anon-key" SUPABASE_BASE_URL="https://fixture.supabase.co" \
  AUTH_TEST_BEARER_TOKEN="fixture.jwt.token" AUTH_TEST_USER_ID="${STATIC_USER_ID}" \
  TARGET_DATE="2026-03-05" CATEGORY="Career" EXPECT_AUTH_MODE="audit" \
  bash "${REHEARSAL_SCRIPT}"

run_fixture_case \
  0 \
  "password login source resolves credentials from fixture login payload" \
  "${FIXTURE_PASS_PASSWORD}" \
  env SUPABASE_ANON_KEY="fixture-anon-key" SUPABASE_BASE_URL="https://fixture.supabase.co" \
  AUTH_TEST_USER_EMAIL="fixture@example.com" AUTH_TEST_USER_PASSWORD="fixture-password" \
  TARGET_DATE="2026-03-05" CATEGORY="Love" EXPECT_AUTH_MODE="audit" \
  bash "${REHEARSAL_SCRIPT}"

run_fixture_case \
  1 \
  "deterministic extras drift is rejected" \
  "${FIXTURE_FAIL_DRIFT}" \
  env SUPABASE_ANON_KEY="fixture-anon-key" SUPABASE_BASE_URL="https://fixture.supabase.co" \
  AUTH_TEST_BEARER_TOKEN="fixture.jwt.token" AUTH_TEST_USER_ID="${STATIC_USER_ID_UPPER}" \
  TARGET_DATE="2026-03-05" CATEGORY="Social" EXPECT_AUTH_MODE="audit" \
  bash "${REHEARSAL_SCRIPT}"

echo ""
echo "Auth rollout fixture regression suite passed."
