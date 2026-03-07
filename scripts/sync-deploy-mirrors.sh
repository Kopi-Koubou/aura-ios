#!/bin/bash
# Syncs canonical deploy artifacts into mirrored aura/ paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRUNE_STALE="${PRUNE_STALE:-true}"

if [ "${PRUNE_STALE}" != "true" ] && [ "${PRUNE_STALE}" != "false" ]; then
  echo "Error: PRUNE_STALE must be true or false."
  exit 1
fi

list_relative_files() {
  local directory="$1"
  (cd "${directory}" && find . -type f | sed 's#^\./##' | sort)
}

copy_file() {
  local source_rel="$1"
  local mirror_rel="$2"

  local source_path="${REPO_ROOT}/${source_rel}"
  local mirror_path="${REPO_ROOT}/${mirror_rel}"

  if [ ! -f "${source_path}" ]; then
    echo "Missing canonical file: ${source_rel}"
    exit 1
  fi

  mkdir -p "$(dirname "${mirror_path}")"
  cp "${source_path}" "${mirror_path}"

  if [ -x "${source_path}" ]; then
    chmod +x "${mirror_path}"
  fi

  echo "Synced file: ${source_rel} -> ${mirror_rel}"
}

sync_directory_mirror() {
  local source_rel="$1"
  local mirror_rel="$2"
  local label="$3"

  local source_dir="${REPO_ROOT}/${source_rel}"
  local mirror_dir="${REPO_ROOT}/${mirror_rel}"

  if [ ! -d "${source_dir}" ]; then
    echo "Missing canonical directory: ${source_rel}"
    exit 1
  fi

  mkdir -p "${mirror_dir}"

  while IFS= read -r relative_path; do
    [ -z "${relative_path}" ] && continue
    mkdir -p "$(dirname "${mirror_dir}/${relative_path}")"
    cp "${source_dir}/${relative_path}" "${mirror_dir}/${relative_path}"
  done < <(list_relative_files "${source_dir}")

  if [ "${PRUNE_STALE}" = "true" ]; then
    while IFS= read -r relative_path; do
      [ -z "${relative_path}" ] && continue
      if [ ! -f "${source_dir}/${relative_path}" ]; then
        rm -f "${mirror_dir}/${relative_path}"
        echo "Pruned stale ${label} file: ${mirror_rel}/${relative_path}"
      fi
    done < <(list_relative_files "${mirror_dir}")

    find "${mirror_dir}" -type d -empty -delete
  fi

  echo "Synced ${label} mirror: ${source_rel} -> ${mirror_rel}"
}

sync_sql_mirror() {
  local source_dir="${REPO_ROOT}"
  local mirror_dir="${REPO_ROOT}/aura/supabase/migrations"

  mkdir -p "${mirror_dir}"

  while IFS= read -r file_name; do
    [ -z "${file_name}" ] && continue
    cp "${source_dir}/${file_name}" "${mirror_dir}/${file_name}"
    echo "Synced SQL: ${file_name}"
  done < <(cd "${source_dir}" && find . -maxdepth 1 -type f -name '*.sql' | sed 's#^\./##' | sort)

  if [ "${PRUNE_STALE}" = "true" ]; then
    while IFS= read -r file_name; do
      [ -z "${file_name}" ] && continue
      if [ ! -f "${source_dir}/${file_name}" ]; then
        rm -f "${mirror_dir}/${file_name}"
        echo "Pruned stale SQL mirror: ${file_name}"
      fi
    done < <(cd "${mirror_dir}" && find . -maxdepth 1 -type f -name '*.sql' | sed 's#^\./##' | sort)
  fi
}

copy_file "config.toml" "aura/supabase/config.toml"
copy_file "DEPLOYMENT.md" "aura/DEPLOYMENT.md"
copy_file "scripts/deploy-functions.sh" "aura/scripts/deploy-functions.sh"
copy_file "scripts/set-secrets.sh" "aura/scripts/set-secrets.sh"
copy_file "scripts/warm-generated-cache.sh" "aura/scripts/warm-generated-cache.sh"
copy_file "scripts/check-auth-fallback-readiness.sh" "aura/scripts/check-auth-fallback-readiness.sh"
copy_file "scripts/check-cache-degradation-readiness.sh" "aura/scripts/check-cache-degradation-readiness.sh"
copy_file "scripts/set-generate-horoscope-auth-mode.sh" "aura/scripts/set-generate-horoscope-auth-mode.sh"
copy_file "scripts/build-warmup-combos.sh" "aura/scripts/build-warmup-combos.sh"
copy_file "scripts/rehearse-auth-rollout.sh" "aura/scripts/rehearse-auth-rollout.sh"
copy_file "scripts/run-critical-swift-tests.sh" "aura/scripts/run-critical-swift-tests.sh"
copy_file "scripts/run-edge-function-tests.sh" "aura/scripts/run-edge-function-tests.sh"
copy_file "scripts/check-apple-distribution-identity.sh" "aura/scripts/check-apple-distribution-identity.sh"
copy_file "scripts/run-apple-distribution-identity-fixture-tests.sh" "aura/scripts/run-apple-distribution-identity-fixture-tests.sh"
copy_file "scripts/check-provisioning-profile-health.sh" "aura/scripts/check-provisioning-profile-health.sh"
copy_file "scripts/run-provisioning-profile-health-fixture-tests.sh" "aura/scripts/run-provisioning-profile-health-fixture-tests.sh"
copy_file "scripts/run-readiness-fixture-tests.sh" "aura/scripts/run-readiness-fixture-tests.sh"
copy_file "scripts/run-readiness-escalation.sh" "aura/scripts/run-readiness-escalation.sh"
copy_file "scripts/run-readiness-escalation-fixture-tests.sh" "aura/scripts/run-readiness-escalation-fixture-tests.sh"
copy_file "scripts/summarize-readiness-escalation-metrics.sh" "aura/scripts/summarize-readiness-escalation-metrics.sh"
copy_file "scripts/run-readiness-escalation-metrics-summary-fixture-tests.sh" "aura/scripts/run-readiness-escalation-metrics-summary-fixture-tests.sh"
copy_file "scripts/apply-readiness-page-limits-from-metrics.sh" "aura/scripts/apply-readiness-page-limits-from-metrics.sh"
copy_file "scripts/run-readiness-page-limit-apply-fixture-tests.sh" "aura/scripts/run-readiness-page-limit-apply-fixture-tests.sh"
copy_file "scripts/propose-readiness-page-limit-update.sh" "aura/scripts/propose-readiness-page-limit-update.sh"
copy_file "scripts/run-propose-readiness-page-limit-fixture-tests.sh" "aura/scripts/run-propose-readiness-page-limit-fixture-tests.sh"
copy_file "scripts/resolve-calibration-low-confidence-escalation.sh" "aura/scripts/resolve-calibration-low-confidence-escalation.sh"
copy_file "scripts/run-resolve-calibration-low-confidence-escalation-fixture-tests.sh" "aura/scripts/run-resolve-calibration-low-confidence-escalation-fixture-tests.sh"
copy_file "scripts/run-auth-rollout-fixture-tests.sh" "aura/scripts/run-auth-rollout-fixture-tests.sh"
copy_file "scripts/run-warmup-combo-fixture-tests.sh" "aura/scripts/run-warmup-combo-fixture-tests.sh"
copy_file "scripts/run-warm-generated-cache-fixture-tests.sh" "aura/scripts/run-warm-generated-cache-fixture-tests.sh"
copy_file "scripts/summarize-warm-cache-metrics.sh" "aura/scripts/summarize-warm-cache-metrics.sh"
copy_file "scripts/run-warm-cache-metrics-summary-fixture-tests.sh" "aura/scripts/run-warm-cache-metrics-summary-fixture-tests.sh"
copy_file "scripts/apply-warmup-threshold-from-metrics.sh" "aura/scripts/apply-warmup-threshold-from-metrics.sh"
copy_file "scripts/run-warmup-threshold-apply-fixture-tests.sh" "aura/scripts/run-warmup-threshold-apply-fixture-tests.sh"
copy_file "scripts/propose-warmup-threshold-update.sh" "aura/scripts/propose-warmup-threshold-update.sh"
copy_file "scripts/run-propose-warmup-threshold-fixture-tests.sh" "aura/scripts/run-propose-warmup-threshold-fixture-tests.sh"
copy_file "scripts/lint-workflows.sh" "aura/scripts/lint-workflows.sh"
copy_file "scripts/prune-generated-cache.sh" "aura/scripts/prune-generated-cache.sh"
copy_file "ops/warmup-combos.txt" "aura/ops/warmup-combos.txt"

sync_directory_mirror "edge-functions" "aura/supabase/functions" "edge function"
sync_sql_mirror

echo ""
echo "Mirror sync complete."
echo "Run parity verification:"
echo "  bash ./scripts/check-deploy-parity.sh"
