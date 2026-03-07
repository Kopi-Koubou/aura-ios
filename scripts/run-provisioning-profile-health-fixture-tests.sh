#!/bin/bash
# Runs fixture-mode regression checks for provisioning-profile health validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="${SCRIPT_DIR}"
REPO_ROOT=""
CASE_OUTPUT=""

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/scripts/check-provisioning-profile-health.sh" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Provisioning profile fixture tests failed: could not locate repository root."
  exit 1
fi

CHECK_SCRIPT="${REPO_ROOT}/scripts/check-provisioning-profile-health.sh"

for dependency in mktemp grep sed date; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Provisioning profile fixture tests failed: missing dependency '${dependency}'."
    exit 1
  fi
done

if [ ! -x "/usr/libexec/PlistBuddy" ] && ! command -v python3 >/dev/null 2>&1; then
  echo "Provisioning profile fixture tests failed: requires /usr/libexec/PlistBuddy or python3."
  exit 1
fi

if [ ! -f "${CHECK_SCRIPT}" ]; then
  echo "Provisioning profile fixture tests failed: missing script ${CHECK_SCRIPT}."
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

write_profile_plist_fixture() {
  local output_path="$1"
  local team_identifier="$2"
  local application_identifier="$3"
  local expiration_date="$4"
  local get_task_allow="$5"
  local include_provisioned_devices="$6"
  local provisions_all_devices="$7"

  cat > "${output_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Name</key>
  <string>Aura AppStore Fixture</string>
  <key>UUID</key>
  <string>fixture-profile-uuid-1234</string>
  <key>TeamIdentifier</key>
  <array>
    <string>${team_identifier}</string>
  </array>
  <key>ExpirationDate</key>
  <date>${expiration_date}</date>
  <key>Entitlements</key>
  <dict>
    <key>application-identifier</key>
    <string>${application_identifier}</string>
    <key>get-task-allow</key>
    <${get_task_allow}/>
  </dict>
PLIST

  if [ "${include_provisioned_devices}" = "true" ]; then
    cat >> "${output_path}" <<'PLIST'
  <key>ProvisionedDevices</key>
  <array>
    <string>00008110-001A111E0A88001E</string>
  </array>
PLIST
  fi

  cat >> "${output_path}" <<PLIST
  <key>ProvisionsAllDevices</key>
  <${provisions_all_devices}/>
</dict>
</plist>
PLIST
}

echo "Running provisioning-profile health fixture regression suite..."

valid_plist="${TMP_FIXTURE_DIR}/valid.plist"
write_profile_plist_fixture "${valid_plist}" "M42QAK8JZ9" "M42QAK8JZ9.com.kopikoubou.aura" "2099-12-31T23:59:59Z" "false" "false" "false"

run_fixture_case \
  0 \
  "accepts matching unexpired App Store profile metadata" \
  env PROFILE_PLIST_PATH="${valid_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Provisioning profile health check passed."

run_fixture_case \
  0 \
  "accepts matching unexpired profile metadata via python parser fallback" \
  env PLIST_BUDDY_BIN="/nonexistent/plistbuddy" PROFILE_PLIST_PATH="${valid_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Provisioning profile health check passed."

expired_plist="${TMP_FIXTURE_DIR}/expired.plist"
write_profile_plist_fixture "${expired_plist}" "M42QAK8JZ9" "M42QAK8JZ9.com.kopikoubou.aura" "2020-01-01T00:00:00Z" "false" "false" "false"

run_fixture_case \
  1 \
  "rejects expired profile metadata" \
  env PROFILE_PLIST_PATH="${expired_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Provisioning profile expired"

wrong_bundle_plist="${TMP_FIXTURE_DIR}/wrong-bundle.plist"
write_profile_plist_fixture "${wrong_bundle_plist}" "M42QAK8JZ9" "M42QAK8JZ9.com.kopikoubou.other" "2099-12-31T23:59:59Z" "false" "false" "false"

run_fixture_case \
  1 \
  "rejects bundle identifier mismatch" \
  env PROFILE_PLIST_PATH="${wrong_bundle_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "does not match expected bundle id"

development_plist="${TMP_FIXTURE_DIR}/development.plist"
write_profile_plist_fixture "${development_plist}" "M42QAK8JZ9" "M42QAK8JZ9.com.kopikoubou.aura" "2099-12-31T23:59:59Z" "true" "false" "false"

run_fixture_case \
  1 \
  "rejects get-task-allow=true development profiles" \
  env PROFILE_PLIST_PATH="${development_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "get-task-allow=true"

ad_hoc_plist="${TMP_FIXTURE_DIR}/ad-hoc.plist"
write_profile_plist_fixture "${ad_hoc_plist}" "M42QAK8JZ9" "M42QAK8JZ9.com.kopikoubou.aura" "2099-12-31T23:59:59Z" "false" "true" "false"

run_fixture_case \
  1 \
  "rejects non-App-Store profile metadata with provisioned devices" \
  env PROFILE_PLIST_PATH="${ad_hoc_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "ProvisionedDevices present"

wrong_team_plist="${TMP_FIXTURE_DIR}/wrong-team.plist"
write_profile_plist_fixture "${wrong_team_plist}" "A1B2C3D4E5" "A1B2C3D4E5.com.kopikoubou.aura" "2099-12-31T23:59:59Z" "false" "false" "false"

run_fixture_case \
  1 \
  "rejects team identifier mismatch" \
  env PROFILE_PLIST_PATH="${wrong_team_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "does not match expected team"

run_fixture_case \
  1 \
  "rejects profile UUID mismatch" \
  env PROFILE_PLIST_PATH="${valid_plist}" PROFILE_UUID="fixture-profile-uuid-other" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "Profile UUID mismatch"

enterprise_plist="${TMP_FIXTURE_DIR}/enterprise.plist"
write_profile_plist_fixture "${enterprise_plist}" "M42QAK8JZ9" "M42QAK8JZ9.com.kopikoubou.aura" "2099-12-31T23:59:59Z" "false" "false" "true"

run_fixture_case \
  1 \
  "rejects enterprise profile metadata with ProvisionsAllDevices=true" \
  env PROFILE_PLIST_PATH="${enterprise_plist}" PROFILE_UUID="fixture-profile-uuid-1234" \
  EXPECTED_TEAM_ID="M42QAK8JZ9" EXPECTED_BUNDLE_ID="com.kopikoubou.aura" \
  bash "${CHECK_SCRIPT}"
assert_case_output_contains "ProvisionsAllDevices=true"

echo ""
echo "Provisioning-profile health fixture regression suite passed."
