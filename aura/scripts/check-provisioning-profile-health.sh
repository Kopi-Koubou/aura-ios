#!/bin/bash
# Fails fast when the selected provisioning profile is missing, expired, mismatched, or not App Store compatible.

set -euo pipefail

EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.kopikoubou.aura}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-M42QAK8JZ9}"
PROFILE_UUID="${PROFILE_UUID:-${PROVISIONING_PROFILE_UUID:-}}"
PROFILE_PATH="${PROFILE_PATH:-}"
PROFILE_PLIST_PATH="${PROFILE_PLIST_PATH:-}"
PROFILE_DIR="${PROFILE_DIR:-${HOME}/Library/MobileDevice/Provisioning Profiles}"
PLIST_BUDDY_BIN="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
PLIST_PARSER_MODE=""

init_plist_parser() {
  if [ -n "${PLIST_BUDDY_BIN}" ] && [ -x "${PLIST_BUDDY_BIN}" ]; then
    PLIST_PARSER_MODE="plistbuddy"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    PLIST_PARSER_MODE="python3"
    return
  fi

  echo "::error::Unable to parse provisioning profile metadata: /usr/libexec/PlistBuddy is unavailable and python3 is not installed."
  exit 1
}

resolve_profile_path() {
  if [ -n "${PROFILE_PATH}" ]; then
    printf '%s\n' "${PROFILE_PATH}"
    return
  fi

  if [ -n "${PROFILE_UUID}" ]; then
    printf '%s/%s.mobileprovision\n' "${PROFILE_DIR}" "${PROFILE_UUID}"
    return
  fi

  if [ ! -d "${PROFILE_DIR}" ]; then
    echo "::error::Provisioning profile directory does not exist: ${PROFILE_DIR}"
    exit 1
  fi

  local discovered
  discovered="$(find "${PROFILE_DIR}" -maxdepth 1 -type f -name '*.mobileprovision' | head -n 1 || true)"
  if [ -z "${discovered}" ]; then
    echo "::error::No provisioning profile found in ${PROFILE_DIR}."
    exit 1
  fi

  echo "::warning::PROFILE_UUID was not provided; validating first discovered profile."
  printf '%s\n' "${discovered}"
}

read_plist_value() {
  local key_path="$1"

  if [ "${PLIST_PARSER_MODE}" = "plistbuddy" ]; then
    "${PLIST_BUDDY_BIN}" -c "Print :${key_path}" "${PROFILE_PLIST_PATH}" 2>/dev/null || true
    return
  fi

  python3 - "${PROFILE_PLIST_PATH}" "${key_path}" <<'PY' 2>/dev/null || true
import datetime
import plistlib
import sys

plist_path = sys.argv[1]
key_path = sys.argv[2]

with open(plist_path, "rb") as handle:
    node = plistlib.load(handle)

for raw_part in key_path.split(":"):
    if not raw_part:
        continue

    if isinstance(node, list):
        try:
            index = int(raw_part)
        except ValueError:
            sys.exit(1)
        if index < 0 or index >= len(node):
            sys.exit(1)
        node = node[index]
        continue

    if isinstance(node, dict):
        if raw_part not in node:
            sys.exit(1)
        node = node[raw_part]
        continue

    sys.exit(1)

if isinstance(node, bool):
    print("true" if node else "false")
elif isinstance(node, datetime.datetime):
    if node.tzinfo is None:
        node = node.replace(tzinfo=datetime.timezone.utc)
    node = node.astimezone(datetime.timezone.utc)
    print(node.strftime("%Y-%m-%dT%H:%M:%SZ"))
elif isinstance(node, bytes):
    sys.stdout.write(node.hex())
elif isinstance(node, list):
    for item in node:
        print(item)
elif isinstance(node, dict):
    for item_key, item_value in node.items():
        print(f"{item_key}={item_value}")
elif node is None:
    pass
else:
    print(node)
PY
}

normalize_bool() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

date_to_epoch() {
  local value="$1"
  local normalized_with_minutes="$1"

  if [ -z "${value}" ]; then
    return 1
  fi

  normalized_with_minutes="$(printf '%s\n' "${value}" | sed -E 's/ ([+-][0-9]{2}) ([0-9]{4})$/ \100 \2/')"

  if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${value}" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${value}" +%s
    return 0
  fi

  if date -u -j -f "%a %b %e %T %Z %Y" "${value}" +%s >/dev/null 2>&1; then
    date -u -j -f "%a %b %e %T %Z %Y" "${value}" +%s
    return 0
  fi

  if date -u -j -f "%a %b %e %T %z %Y" "${normalized_with_minutes}" +%s >/dev/null 2>&1; then
    date -u -j -f "%a %b %e %T %z %Y" "${normalized_with_minutes}" +%s
    return 0
  fi

  if date -u -j -f "%a %b %d %T %Z %Y" "${value}" +%s >/dev/null 2>&1; then
    date -u -j -f "%a %b %d %T %Z %Y" "${value}" +%s
    return 0
  fi

  if date -u -j -f "%a %b %d %T %z %Y" "${normalized_with_minutes}" +%s >/dev/null 2>&1; then
    date -u -j -f "%a %b %d %T %z %Y" "${normalized_with_minutes}" +%s
    return 0
  fi

  if date -u -d "${value}" +%s >/dev/null 2>&1; then
    date -u -d "${value}" +%s
    return 0
  fi

  return 1
}

profile_matches_bundle_id() {
  local application_identifier="$1"
  local team_id="$2"
  local expected_bundle_id="$3"

  local prefix="${team_id}."
  if [[ "${application_identifier}" != "${prefix}"* ]]; then
    return 1
  fi

  local pattern="${application_identifier#${prefix}}"
  if [ -z "${pattern}" ]; then
    return 1
  fi

  case "${expected_bundle_id}" in
    ${pattern})
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

init_plist_parser

tmp_profile_plist=""
cleanup() {
  if [ -n "${tmp_profile_plist}" ] && [ -f "${tmp_profile_plist}" ]; then
    rm -f "${tmp_profile_plist}"
  fi
}
trap cleanup EXIT

if [ -n "${PROFILE_PLIST_PATH}" ]; then
  if [ ! -r "${PROFILE_PLIST_PATH}" ]; then
    echo "::error::PROFILE_PLIST_PATH is not readable: ${PROFILE_PLIST_PATH}"
    exit 1
  fi
else
  if ! command -v security >/dev/null 2>&1; then
    echo "::error::security command is required when PROFILE_PLIST_PATH is not provided."
    exit 1
  fi

  PROFILE_PATH="$(resolve_profile_path)"
  if [ ! -r "${PROFILE_PATH}" ]; then
    echo "::error::Provisioning profile is not readable: ${PROFILE_PATH}"
    exit 1
  fi

  tmp_profile_plist="$(mktemp "${TMPDIR:-/tmp}/profile-health.XXXXXX.plist")"
  security cms -D -i "${PROFILE_PATH}" > "${tmp_profile_plist}"
  PROFILE_PLIST_PATH="${tmp_profile_plist}"
fi

PROFILE_NAME="$(read_plist_value "Name")"
PROFILE_UUID_ACTUAL="$(read_plist_value "UUID")"
PROFILE_TEAM_ID="$(read_plist_value "TeamIdentifier:0")"
PROFILE_EXPIRATION_RAW="$(read_plist_value "ExpirationDate")"
PROFILE_APP_IDENTIFIER="$(read_plist_value "Entitlements:application-identifier")"
PROFILE_GET_TASK_ALLOW="$(normalize_bool "$(read_plist_value "Entitlements:get-task-allow")")"
PROFILE_PROVISIONS_ALL_DEVICES="$(normalize_bool "$(read_plist_value "ProvisionsAllDevices")")"
PROFILE_PROVISIONED_DEVICES="$(read_plist_value "ProvisionedDevices")"

if [ -z "${PROFILE_NAME}" ]; then
  echo "::warning::Provisioning profile name is missing from parsed metadata."
fi

if [ -z "${PROFILE_UUID_ACTUAL}" ]; then
  echo "::error::Unable to extract provisioning profile UUID."
  exit 1
fi

if [ -n "${PROFILE_UUID}" ] && [ "${PROFILE_UUID_ACTUAL}" != "${PROFILE_UUID}" ]; then
  echo "::error::Profile UUID mismatch: expected ${PROFILE_UUID}, found ${PROFILE_UUID_ACTUAL}."
  exit 1
fi

if [ -z "${PROFILE_TEAM_ID}" ]; then
  echo "::error::Unable to extract TeamIdentifier from provisioning profile."
  exit 1
fi

if [ "${PROFILE_TEAM_ID}" != "${EXPECTED_TEAM_ID}" ]; then
  echo "::error::Provisioning profile team '${PROFILE_TEAM_ID}' does not match expected team '${EXPECTED_TEAM_ID}'."
  exit 1
fi

if [ -z "${PROFILE_APP_IDENTIFIER}" ]; then
  echo "::error::Unable to extract entitlements application-identifier from provisioning profile."
  exit 1
fi

if ! profile_matches_bundle_id "${PROFILE_APP_IDENTIFIER}" "${PROFILE_TEAM_ID}" "${EXPECTED_BUNDLE_ID}"; then
  echo "::error::Provisioning profile application-identifier '${PROFILE_APP_IDENTIFIER}' does not match expected bundle id '${EXPECTED_BUNDLE_ID}'."
  exit 1
fi

if [ "${PROFILE_GET_TASK_ALLOW}" = "true" ] || [ "${PROFILE_GET_TASK_ALLOW}" = "1" ]; then
  echo "::error::Provisioning profile is not App Store compatible (get-task-allow=true)."
  exit 1
fi

if [ -n "${PROFILE_PROVISIONED_DEVICES}" ]; then
  echo "::error::Provisioning profile is not App Store compatible (ProvisionedDevices present)."
  exit 1
fi

if [ "${PROFILE_PROVISIONS_ALL_DEVICES}" = "true" ] || [ "${PROFILE_PROVISIONS_ALL_DEVICES}" = "1" ]; then
  echo "::error::Provisioning profile is not App Store compatible (ProvisionsAllDevices=true)."
  exit 1
fi

if [ -z "${PROFILE_EXPIRATION_RAW}" ]; then
  echo "::error::Unable to extract ExpirationDate from provisioning profile."
  exit 1
fi

PROFILE_EXPIRATION_EPOCH="$(date_to_epoch "${PROFILE_EXPIRATION_RAW}" || true)"
if [ -z "${PROFILE_EXPIRATION_EPOCH}" ]; then
  echo "::error::Unable to parse provisioning profile ExpirationDate '${PROFILE_EXPIRATION_RAW}'."
  exit 1
fi

CURRENT_EPOCH="$(date -u +%s)"
if [ "${PROFILE_EXPIRATION_EPOCH}" -le "${CURRENT_EPOCH}" ]; then
  echo "::error::Provisioning profile expired at '${PROFILE_EXPIRATION_RAW}'."
  exit 1
fi

SECONDS_UNTIL_EXPIRY=$((PROFILE_EXPIRATION_EPOCH - CURRENT_EPOCH))
if [ "${SECONDS_UNTIL_EXPIRY}" -le $((30 * 24 * 60 * 60)) ]; then
  echo "::warning::Provisioning profile expires within 30 days (${PROFILE_EXPIRATION_RAW})."
fi

echo "Provisioning profile health check passed."
echo "Profile name: ${PROFILE_NAME:-<unknown>}"
echo "Profile UUID: ${PROFILE_UUID_ACTUAL}"
echo "Team ID: ${PROFILE_TEAM_ID}"
echo "Application identifier: ${PROFILE_APP_IDENTIFIER}"
echo "Expiration: ${PROFILE_EXPIRATION_RAW}"
