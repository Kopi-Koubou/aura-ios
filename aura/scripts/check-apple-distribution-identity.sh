#!/bin/bash
# Fails fast when Apple Distribution identities are missing, invalid, or drifted from expected team.

set -euo pipefail

EXPECTED_TEAM_ID="$(printf '%s' "${EXPECTED_TEAM_ID:-}" | tr '[:lower:]' '[:upper:]')"
IDENTITY_OUTPUT_PATH="${IDENTITY_OUTPUT_PATH:-}"

if [ -n "${EXPECTED_TEAM_ID}" ] && ! [[ "${EXPECTED_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "::error::EXPECTED_TEAM_ID must be a 10-character Apple team identifier (received '${EXPECTED_TEAM_ID}')."
  exit 1
fi

if [ -n "${IDENTITY_OUTPUT_PATH}" ]; then
  if [ ! -r "${IDENTITY_OUTPUT_PATH}" ]; then
    echo "::error::IDENTITY_OUTPUT_PATH is not readable: ${IDENTITY_OUTPUT_PATH}"
    exit 1
  fi
  IDENTITY_OUTPUT="$(cat "${IDENTITY_OUTPUT_PATH}")"
else
  if ! command -v security >/dev/null 2>&1; then
    echo "::error::security command is required but not available."
    exit 1
  fi
  IDENTITY_OUTPUT="$(security find-identity -v -p codesigning 2>&1 || true)"
fi

echo "${IDENTITY_OUTPUT}"

DISTRIBUTION_LINES="$(printf '%s\n' "${IDENTITY_OUTPUT}" | grep -F "Apple Distribution" || true)"
if [ -z "${DISTRIBUTION_LINES}" ]; then
  echo "::error::No Apple Distribution signing identity found."
  exit 1
fi

INVALID_DISTRIBUTION_LINES="$(
  printf '%s\n' "${DISTRIBUTION_LINES}" \
    | grep -E '\(CSSMERR_|REVOKED|EXPIRED|NOT_TRUSTED|NO_CERTIFICATE_FOUND' || true
)"
if [ -n "${INVALID_DISTRIBUTION_LINES}" ]; then
  echo "::error::Detected invalid Apple Distribution identity entries."
  printf '%s\n' "${INVALID_DISTRIBUTION_LINES}"
  echo "Install a current Apple Distribution certificate and remove revoked/expired identities."
  exit 1
fi

VALID_DISTRIBUTION_LINES="$(printf '%s\n' "${DISTRIBUTION_LINES}" | grep -Ev '\(CSSMERR_' || true)"
if [ -z "${VALID_DISTRIBUTION_LINES}" ]; then
  echo "::error::No valid Apple Distribution identity available for code signing."
  exit 1
fi

if [ -n "${EXPECTED_TEAM_ID}" ]; then
  TEAM_MATCH_LINES="$(
    printf '%s\n' "${VALID_DISTRIBUTION_LINES}" \
      | grep -E "\\(${EXPECTED_TEAM_ID}\\)\"?$" || true
  )"
  if [ -z "${TEAM_MATCH_LINES}" ]; then
    AVAILABLE_TEAM_IDS="$(
      printf '%s\n' "${VALID_DISTRIBUTION_LINES}" \
        | sed -nE 's/.*\(([A-Z0-9]{10})\)"?$/\1/p' \
        | sort -u \
        | tr '\n' ',' \
        | sed 's/,$//'
    )"
    if [ -z "${AVAILABLE_TEAM_IDS}" ]; then
      AVAILABLE_TEAM_IDS="<unparseable>"
    fi

    echo "::error::No valid Apple Distribution identity found for expected team '${EXPECTED_TEAM_ID}'. Available team IDs: ${AVAILABLE_TEAM_IDS}."
    exit 1
  fi

  echo "Valid Apple Distribution identity entries for team ${EXPECTED_TEAM_ID}:"
  printf '%s\n' "${TEAM_MATCH_LINES}"
  exit 0
fi

echo "Valid Apple Distribution identity entries:"
printf '%s\n' "${VALID_DISTRIBUTION_LINES}"
