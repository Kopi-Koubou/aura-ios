#!/bin/bash
# Runs fixture-mode regression checks for Apple Distribution identity validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/check-apple-distribution-identity.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Apple Distribution identity fixture tests failed: could not locate repository root."
  exit 1
fi

CHECK_SCRIPT="${REPO_ROOT}/scripts/check-apple-distribution-identity.sh"

if [ ! -f "${CHECK_SCRIPT}" ]; then
  echo "Apple Distribution identity fixture tests failed: missing script ${CHECK_SCRIPT}."
  exit 1
fi

TMP_FIXTURE_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_FIXTURE_DIR}"
}
trap cleanup EXIT

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

write_identity_fixture() {
  local output_path="$1"
  local content="$2"
  printf '%s\n' "${content}" > "${output_path}"
}

echo "Running Apple Distribution identity fixture regression suite..."

valid_identity_fixture="${TMP_FIXTURE_DIR}/valid-team.txt"
write_identity_fixture "${valid_identity_fixture}" '1) DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF "Apple Distribution: Aura Labs (M42QAK8JZ9)"
  1 valid identities found'

run_fixture_case \
  0 \
  "accepts valid Apple Distribution identity for expected team" \
  env IDENTITY_OUTPUT_PATH="${valid_identity_fixture}" EXPECTED_TEAM_ID="M42QAK8JZ9" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Valid Apple Distribution identity entries for team M42QAK8JZ9"

missing_distribution_fixture="${TMP_FIXTURE_DIR}/missing-distribution.txt"
write_identity_fixture "${missing_distribution_fixture}" '1) FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF "iPhone Developer: Local Dev (M42QAK8JZ9)"
  1 valid identities found'

run_fixture_case \
  1 \
  "rejects when no Apple Distribution identity exists" \
  env IDENTITY_OUTPUT_PATH="${missing_distribution_fixture}" EXPECTED_TEAM_ID="M42QAK8JZ9" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "No Apple Distribution signing identity found."

revoked_identity_fixture="${TMP_FIXTURE_DIR}/revoked-distribution.txt"
write_identity_fixture "${revoked_identity_fixture}" '1) BADBADBADBADBADBADBADBADBADBADBADBADBADD "Apple Distribution: Aura Labs (M42QAK8JZ9)" (CSSMERR_TP_CERT_REVOKED)
  0 valid identities found'

run_fixture_case \
  1 \
  "rejects revoked Apple Distribution identity entries" \
  env IDENTITY_OUTPUT_PATH="${revoked_identity_fixture}" EXPECTED_TEAM_ID="M42QAK8JZ9" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Detected invalid Apple Distribution identity entries."

wrong_team_fixture="${TMP_FIXTURE_DIR}/wrong-team.txt"
write_identity_fixture "${wrong_team_fixture}" '1) C0FFEEC0FFEEC0FFEEC0FFEEC0FFEEC0FFEEC0FF "Apple Distribution: Aura Labs (ZZZZZZZZZZ)"
  1 valid identities found'

run_fixture_case \
  1 \
  "rejects valid identity when expected team id is missing" \
  env IDENTITY_OUTPUT_PATH="${wrong_team_fixture}" EXPECTED_TEAM_ID="M42QAK8JZ9" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "No valid Apple Distribution identity found for expected team 'M42QAK8JZ9'"

run_fixture_case \
  0 \
  "allows any valid team when EXPECTED_TEAM_ID is unset" \
  env IDENTITY_OUTPUT_PATH="${wrong_team_fixture}" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Valid Apple Distribution identity entries:"

echo ""
echo "Apple Distribution identity fixture regression suite passed."
