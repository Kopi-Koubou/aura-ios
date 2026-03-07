#!/bin/bash
# Runs critical Swift regression suites that guard generation/auth/sync behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
SEARCH_DIR="${SCRIPT_DIR}"

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/aura/Package.swift" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${REPO_ROOT}" ]; then
  echo "Unable to locate repository root containing aura/Package.swift"
  exit 1
fi

PACKAGE_PATH="${REPO_ROOT}/aura"

if [ ! -d "${PACKAGE_PATH}" ]; then
  echo "Swift package path not found: ${PACKAGE_PATH}"
  exit 1
fi

declare -a TEST_FILTERS=(
  "OpenAIServicePolicyTests"
  "SecretsAuthModeTests"
  "ContentServiceCachingTests"
  "DailyReadingDeterminismTests"
  "SyncBacklogStoreTests"
  "IdentityReconciliationTests"
  "SupabaseSessionManagerTests"
  "AppStateProfileSyncTests"
  "ShareCardRenderSnapshotTests"
)

for test_filter in "${TEST_FILTERS[@]}"; do
  echo "Running ${test_filter}..."
  swift test --package-path "${PACKAGE_PATH}" --filter "${test_filter}"
done

echo "Critical Swift regression suite passed."
