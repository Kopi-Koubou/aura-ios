#!/bin/bash
# Ensures duplicated deploy artifacts and wrapper entrypoints stay in sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

has_mismatch=0

check_file_pair() {
  local left_rel="$1"
  local right_rel="$2"

  local left_path="${REPO_ROOT}/${left_rel}"
  local right_path="${REPO_ROOT}/${right_rel}"

  if [ ! -f "${left_path}" ] || [ ! -f "${right_path}" ]; then
    echo "Missing file for parity check: ${left_rel} or ${right_rel}"
    has_mismatch=1
    return
  fi

  if ! diff -q "${left_path}" "${right_path}" >/dev/null; then
    echo "Parity mismatch detected:"
    echo "  - ${left_rel}"
    echo "  - ${right_rel}"
    has_mismatch=1
  fi
}

check_wrapper_script() {
  local wrapper_rel="$1"
  local target_rel="$2"

  local wrapper_path="${REPO_ROOT}/${wrapper_rel}"
  local expected_line="bash \"\${REPO_ROOT}/${target_rel}\""

  if [ ! -f "${wrapper_path}" ]; then
    echo "Missing wrapper script for parity check: ${wrapper_rel}"
    has_mismatch=1
    return
  fi

  if ! grep -Fq "${expected_line}" "${wrapper_path}"; then
    echo "Wrapper parity mismatch: ${wrapper_rel} should delegate to ${target_rel}"
    has_mismatch=1
  fi
}

list_relative_files() {
  local directory="$1"
  (cd "${directory}" && find . -type f | sed 's#^\./##' | sort)
}

check_directory_mirror() {
  local left_rel="$1"
  local right_rel="$2"
  local label="$3"

  local left_dir="${REPO_ROOT}/${left_rel}"
  local right_dir="${REPO_ROOT}/${right_rel}"

  if [ ! -d "${left_dir}" ] || [ ! -d "${right_dir}" ]; then
    echo "Missing directory for parity check: ${left_rel} or ${right_rel}"
    has_mismatch=1
    return
  fi

  while IFS= read -r relative_path; do
    [ -z "${relative_path}" ] && continue
    echo "${label} parity mismatch: missing in ${right_rel} -> ${left_rel}/${relative_path}"
    has_mismatch=1
  done < <(comm -23 <(list_relative_files "${left_dir}") <(list_relative_files "${right_dir}"))

  while IFS= read -r relative_path; do
    [ -z "${relative_path}" ] && continue
    echo "${label} parity mismatch: missing in ${left_rel} -> ${right_rel}/${relative_path}"
    has_mismatch=1
  done < <(comm -13 <(list_relative_files "${left_dir}") <(list_relative_files "${right_dir}"))

  while IFS= read -r relative_path; do
    [ -z "${relative_path}" ] && continue
    if ! diff -q "${left_dir}/${relative_path}" "${right_dir}/${relative_path}" >/dev/null; then
      echo "${label} parity mismatch: content drift for ${relative_path}"
      has_mismatch=1
    fi
  done < <(comm -12 <(list_relative_files "${left_dir}") <(list_relative_files "${right_dir}"))
}

list_root_sql_files() {
  (cd "${REPO_ROOT}" && find . -maxdepth 1 -type f -name '*.sql' | sed 's#^\./##' | sort)
}

list_migration_sql_files() {
  (cd "${REPO_ROOT}/aura/supabase/migrations" && find . -maxdepth 1 -type f -name '*.sql' | sed 's#^\./##' | sort)
}

check_sql_mirror() {
  local migrations_dir="${REPO_ROOT}/aura/supabase/migrations"

  if [ ! -d "${migrations_dir}" ]; then
    echo "Missing directory for parity check: aura/supabase/migrations"
    has_mismatch=1
    return
  fi

  while IFS= read -r file_name; do
    [ -z "${file_name}" ] && continue
    echo "SQL parity mismatch: missing migration mirror in aura/supabase/migrations -> ${file_name}"
    has_mismatch=1
  done < <(comm -23 <(list_root_sql_files) <(list_migration_sql_files))

  while IFS= read -r file_name; do
    [ -z "${file_name}" ] && continue
    echo "SQL parity mismatch: missing root SQL mirror -> aura/supabase/migrations/${file_name}"
    has_mismatch=1
  done < <(comm -13 <(list_root_sql_files) <(list_migration_sql_files))

  while IFS= read -r file_name; do
    [ -z "${file_name}" ] && continue
    if ! diff -q "${REPO_ROOT}/${file_name}" "${migrations_dir}/${file_name}" >/dev/null; then
      echo "SQL parity mismatch: content drift for ${file_name}"
      has_mismatch=1
    fi
  done < <(comm -12 <(list_root_sql_files) <(list_migration_sql_files))
}

check_file_pair "config.toml" "aura/supabase/config.toml"
check_file_pair "DEPLOYMENT.md" "aura/DEPLOYMENT.md"
check_file_pair "scripts/deploy-functions.sh" "aura/scripts/deploy-functions.sh"
check_file_pair "scripts/set-secrets.sh" "aura/scripts/set-secrets.sh"
check_file_pair "scripts/warm-generated-cache.sh" "aura/scripts/warm-generated-cache.sh"
check_file_pair "scripts/check-auth-fallback-readiness.sh" "aura/scripts/check-auth-fallback-readiness.sh"
check_file_pair "scripts/check-cache-degradation-readiness.sh" "aura/scripts/check-cache-degradation-readiness.sh"
check_file_pair "scripts/set-generate-horoscope-auth-mode.sh" "aura/scripts/set-generate-horoscope-auth-mode.sh"
check_file_pair "scripts/build-warmup-combos.sh" "aura/scripts/build-warmup-combos.sh"
check_file_pair "scripts/rehearse-auth-rollout.sh" "aura/scripts/rehearse-auth-rollout.sh"
check_file_pair "scripts/run-critical-swift-tests.sh" "aura/scripts/run-critical-swift-tests.sh"
check_file_pair "scripts/run-edge-function-tests.sh" "aura/scripts/run-edge-function-tests.sh"
check_file_pair "scripts/check-apple-distribution-identity.sh" "aura/scripts/check-apple-distribution-identity.sh"
check_file_pair "scripts/run-apple-distribution-identity-fixture-tests.sh" "aura/scripts/run-apple-distribution-identity-fixture-tests.sh"
check_file_pair "scripts/check-provisioning-profile-health.sh" "aura/scripts/check-provisioning-profile-health.sh"
check_file_pair "scripts/run-provisioning-profile-health-fixture-tests.sh" "aura/scripts/run-provisioning-profile-health-fixture-tests.sh"
check_file_pair "scripts/run-readiness-fixture-tests.sh" "aura/scripts/run-readiness-fixture-tests.sh"
check_file_pair "scripts/run-readiness-escalation.sh" "aura/scripts/run-readiness-escalation.sh"
check_file_pair "scripts/run-readiness-escalation-fixture-tests.sh" "aura/scripts/run-readiness-escalation-fixture-tests.sh"
check_file_pair "scripts/summarize-readiness-escalation-metrics.sh" "aura/scripts/summarize-readiness-escalation-metrics.sh"
check_file_pair "scripts/run-readiness-escalation-metrics-summary-fixture-tests.sh" "aura/scripts/run-readiness-escalation-metrics-summary-fixture-tests.sh"
check_file_pair "scripts/apply-readiness-page-limits-from-metrics.sh" "aura/scripts/apply-readiness-page-limits-from-metrics.sh"
check_file_pair "scripts/run-readiness-page-limit-apply-fixture-tests.sh" "aura/scripts/run-readiness-page-limit-apply-fixture-tests.sh"
check_file_pair "scripts/propose-readiness-page-limit-update.sh" "aura/scripts/propose-readiness-page-limit-update.sh"
check_file_pair "scripts/run-propose-readiness-page-limit-fixture-tests.sh" "aura/scripts/run-propose-readiness-page-limit-fixture-tests.sh"
check_file_pair "scripts/resolve-calibration-low-confidence-escalation.sh" "aura/scripts/resolve-calibration-low-confidence-escalation.sh"
check_file_pair "scripts/run-resolve-calibration-low-confidence-escalation-fixture-tests.sh" "aura/scripts/run-resolve-calibration-low-confidence-escalation-fixture-tests.sh"
check_file_pair "scripts/run-auth-rollout-fixture-tests.sh" "aura/scripts/run-auth-rollout-fixture-tests.sh"
check_file_pair "scripts/run-warmup-combo-fixture-tests.sh" "aura/scripts/run-warmup-combo-fixture-tests.sh"
check_file_pair "scripts/run-warm-generated-cache-fixture-tests.sh" "aura/scripts/run-warm-generated-cache-fixture-tests.sh"
check_file_pair "scripts/summarize-warm-cache-metrics.sh" "aura/scripts/summarize-warm-cache-metrics.sh"
check_file_pair "scripts/run-warm-cache-metrics-summary-fixture-tests.sh" "aura/scripts/run-warm-cache-metrics-summary-fixture-tests.sh"
check_file_pair "scripts/apply-warmup-threshold-from-metrics.sh" "aura/scripts/apply-warmup-threshold-from-metrics.sh"
check_file_pair "scripts/run-warmup-threshold-apply-fixture-tests.sh" "aura/scripts/run-warmup-threshold-apply-fixture-tests.sh"
check_file_pair "scripts/propose-warmup-threshold-update.sh" "aura/scripts/propose-warmup-threshold-update.sh"
check_file_pair "scripts/run-propose-warmup-threshold-fixture-tests.sh" "aura/scripts/run-propose-warmup-threshold-fixture-tests.sh"
check_file_pair "scripts/lint-workflows.sh" "aura/scripts/lint-workflows.sh"
check_file_pair "scripts/prune-generated-cache.sh" "aura/scripts/prune-generated-cache.sh"
check_file_pair "ops/warmup-combos.txt" "aura/ops/warmup-combos.txt"

check_wrapper_script "aura/scripts/check-deploy-parity.sh" "scripts/check-deploy-parity.sh"
check_wrapper_script "aura/scripts/sync-deploy-mirrors.sh" "scripts/sync-deploy-mirrors.sh"

check_directory_mirror "edge-functions" "aura/supabase/functions" "Edge function"
check_sql_mirror

if [ "${has_mismatch}" -ne 0 ]; then
  echo ""
  echo "Deploy parity check failed."
  echo "Sync duplicate deploy artifacts before continuing:"
  echo "  bash ./scripts/sync-deploy-mirrors.sh"
  exit 1
fi

echo "Deploy parity check passed."
