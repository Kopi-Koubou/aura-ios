#!/bin/bash
# Summarizes readiness escalation metrics and recommends issue-scan page limits.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/summarize-readiness-escalation-metrics.sh [metrics-file-or-directory ...]

Environment:
  READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES    Optional integer >= 0, default 1
  MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES           Optional integer >= 1, default 1
  MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES         Optional integer >= 1, default 1
  READINESS_ESCALATION_METRICS_SUMMARY_FILE       Optional path for JSON summary output

Notes:
  - Directories are scanned recursively for *.json files.
  - Files are treated as readiness-escalation metrics only when required fields exist.
EOF
}

require_dependency() {
  local dependency="$1"
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Error: required dependency '${dependency}' is not installed."
    exit 1
  fi
}

validate_positive_integer() {
  local var_name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -lt 1 ]; then
    echo "Error: ${var_name} must be an integer >= 1."
    exit 1
  fi
}

validate_non_negative_integer() {
  local var_name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    echo "Error: ${var_name} must be an integer >= 0."
    exit 1
  fi
}

add_unique_path() {
  local candidate="$1"
  local existing
  for existing in "${candidate_files[@]:-}"; do
    if [ "${existing}" = "${candidate}" ]; then
      return
    fi
  done
  candidate_files+=("${candidate}")
}

is_valid_metrics_file() {
  local candidate="$1"
  jq -e '
    (.kind | type == "string")
    and (.status | type == "string")
    and (.issue_action | type == "string")
    and (.open_issues_max_pages | type == "number")
    and (.open_pages_scanned | type == "number")
    and (.open_match_page | type == "number")
    and (.open_scan_hit_page_limit | type == "boolean")
    and (.closed_issues_max_pages | type == "number")
    and (.closed_pages_scanned | type == "number")
    and (.closed_match_page | type == "number")
    and (.closed_scan_hit_page_limit | type == "boolean")
    and (.generated_at_utc | type == "string")
  ' "${candidate}" >/dev/null 2>&1
}

percentile_nearest_rank() {
  local percentile="$1"
  shift
  local values=("$@")
  local count="${#values[@]}"
  local rank
  local sorted_values=()
  local value

  if [ "${count}" -eq 0 ]; then
    printf '0'
    return
  fi

  rank=$(((percentile * count + 99) / 100))
  if [ "${rank}" -lt 1 ]; then
    rank=1
  elif [ "${rank}" -gt "${count}" ]; then
    rank="${count}"
  fi

  while IFS= read -r value; do
    sorted_values+=("${value}")
  done < <(printf '%s\n' "${values[@]}" | sort -n)

  printf '%s' "${sorted_values[$((rank - 1))]}"
}

max_of_two() {
  local left="$1"
  local right="$2"
  if [ "${left}" -ge "${right}" ]; then
    printf '%s' "${left}"
  else
    printf '%s' "${right}"
  fi
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_dependency "jq"
require_dependency "find"

READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES="${READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES:-1}"
MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES="${MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES:-1}"
MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES="${MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES:-1}"
READINESS_ESCALATION_METRICS_SUMMARY_FILE="${READINESS_ESCALATION_METRICS_SUMMARY_FILE:-}"

validate_non_negative_integer "READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES" "${READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES}"
validate_positive_integer "MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES" "${MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES}"
validate_positive_integer "MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES" "${MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}"

if [ "$#" -eq 0 ]; then
  set -- "."
fi

candidate_files=()
metrics_files=()
skipped_files=()

for input_path in "$@"; do
  if [ -f "${input_path}" ]; then
    add_unique_path "${input_path}"
    continue
  fi

  if [ -d "${input_path}" ]; then
    while IFS= read -r resolved_path; do
      add_unique_path "${resolved_path}"
    done < <(find "${input_path}" -type f -name '*.json' | sort)
    continue
  fi

  echo "Warning: path does not exist, skipping: ${input_path}"
done

for candidate in "${candidate_files[@]:-}"; do
  if [ -z "${candidate}" ]; then
    continue
  fi
  if is_valid_metrics_file "${candidate}"; then
    metrics_files+=("${candidate}")
  else
    skipped_files+=("${candidate}")
  fi
done

if [ "${#metrics_files[@]}" -eq 0 ]; then
  echo "Error: no valid readiness escalation metrics files found."
  echo "Hint: pass one or more readiness escalation metrics JSON files or directories."
  exit 1
fi

runs_analyzed="${#metrics_files[@]}"

kind_auth_fallback_count=0
kind_cache_degradation_count=0
kind_other_count=0
status_failure_count=0
status_recovered_count=0
status_other_count=0
mode_dry_run_count=0
mode_live_count=0
open_limit_hit_count=0
closed_limit_hit_count=0

open_pages_scanned_values=()
open_match_page_values=()
closed_pages_scanned_values=()
closed_match_page_values=()
generated_at_values=()

for metrics_file in "${metrics_files[@]}"; do
  kind="$(jq -r '.kind' "${metrics_file}")"
  status="$(jq -r '.status' "${metrics_file}")"
  dry_run="$(jq -r '.dry_run // false' "${metrics_file}")"
  open_pages_scanned="$(jq -r '.open_pages_scanned | floor' "${metrics_file}")"
  open_match_page="$(jq -r '.open_match_page | floor' "${metrics_file}")"
  closed_pages_scanned="$(jq -r '.closed_pages_scanned | floor' "${metrics_file}")"
  closed_match_page="$(jq -r '.closed_match_page | floor' "${metrics_file}")"
  open_limit_hit="$(jq -r '.open_scan_hit_page_limit' "${metrics_file}")"
  closed_limit_hit="$(jq -r '.closed_scan_hit_page_limit' "${metrics_file}")"
  generated_at_utc="$(jq -r '.generated_at_utc // empty' "${metrics_file}")"

  open_pages_scanned_values+=("${open_pages_scanned}")
  closed_pages_scanned_values+=("${closed_pages_scanned}")

  if [ "${open_match_page}" -gt 0 ]; then
    open_match_page_values+=("${open_match_page}")
  fi

  if [ "${closed_match_page}" -gt 0 ]; then
    closed_match_page_values+=("${closed_match_page}")
  fi

  if [ -n "${generated_at_utc}" ] && [ "${generated_at_utc}" != "null" ]; then
    generated_at_values+=("${generated_at_utc}")
  fi

  case "${kind}" in
    auth_fallback)
      kind_auth_fallback_count=$((kind_auth_fallback_count + 1))
      ;;
    cache_degradation)
      kind_cache_degradation_count=$((kind_cache_degradation_count + 1))
      ;;
    *)
      kind_other_count=$((kind_other_count + 1))
      ;;
  esac

  case "${status}" in
    failure)
      status_failure_count=$((status_failure_count + 1))
      ;;
    recovered)
      status_recovered_count=$((status_recovered_count + 1))
      ;;
    *)
      status_other_count=$((status_other_count + 1))
      ;;
  esac

  if [ "${dry_run}" = "true" ]; then
    mode_dry_run_count=$((mode_dry_run_count + 1))
  else
    mode_live_count=$((mode_live_count + 1))
  fi

  if [ "${open_limit_hit}" = "true" ]; then
    open_limit_hit_count=$((open_limit_hit_count + 1))
  fi

  if [ "${closed_limit_hit}" = "true" ]; then
    closed_limit_hit_count=$((closed_limit_hit_count + 1))
  fi
done

open_pages_scanned_p50="$(percentile_nearest_rank 50 "${open_pages_scanned_values[@]}")"
open_pages_scanned_p95="$(percentile_nearest_rank 95 "${open_pages_scanned_values[@]}")"
open_pages_scanned_max="$(percentile_nearest_rank 100 "${open_pages_scanned_values[@]}")"
open_match_page_p50="$(percentile_nearest_rank 50 "${open_match_page_values[@]}")"
open_match_page_p95="$(percentile_nearest_rank 95 "${open_match_page_values[@]}")"
open_match_page_max="$(percentile_nearest_rank 100 "${open_match_page_values[@]}")"

closed_pages_scanned_p50="$(percentile_nearest_rank 50 "${closed_pages_scanned_values[@]}")"
closed_pages_scanned_p95="$(percentile_nearest_rank 95 "${closed_pages_scanned_values[@]}")"
closed_pages_scanned_max="$(percentile_nearest_rank 100 "${closed_pages_scanned_values[@]}")"
closed_match_page_p50="$(percentile_nearest_rank 50 "${closed_match_page_values[@]}")"
closed_match_page_p95="$(percentile_nearest_rank 95 "${closed_match_page_values[@]}")"
closed_match_page_max="$(percentile_nearest_rank 100 "${closed_match_page_values[@]}")"

open_baseline="$(max_of_two "${open_pages_scanned_p95}" "${open_match_page_p95}")"
closed_baseline="$(max_of_two "${closed_pages_scanned_p95}" "${closed_match_page_p95}")"

if [ "${open_limit_hit_count}" -gt 0 ]; then
  open_baseline="$(max_of_two "${open_baseline}" "${open_pages_scanned_max}")"
fi

if [ "${closed_limit_hit_count}" -gt 0 ]; then
  closed_baseline="$(max_of_two "${closed_baseline}" "${closed_pages_scanned_max}")"
fi

recommended_open_issues_max_pages=$((open_baseline + READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES))
recommended_closed_issues_max_pages=$((closed_baseline + READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES))

if [ "${recommended_open_issues_max_pages}" -lt "${MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES}" ]; then
  recommended_open_issues_max_pages="${MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES}"
fi

if [ "${recommended_closed_issues_max_pages}" -lt "${MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}" ]; then
  recommended_closed_issues_max_pages="${MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}"
fi

open_limit_hit_rate_percent=$((open_limit_hit_count * 100 / runs_analyzed))
closed_limit_hit_rate_percent=$((closed_limit_hit_count * 100 / runs_analyzed))

metrics_window_start_utc="(unavailable)"
metrics_window_end_utc="(unavailable)"
if [ "${#generated_at_values[@]}" -gt 0 ]; then
  metrics_window_start_utc="$(printf '%s\n' "${generated_at_values[@]}" | sort | head -n 1)"
  metrics_window_end_utc="$(printf '%s\n' "${generated_at_values[@]}" | sort | tail -n 1)"
fi

echo "Readiness escalation metrics summary"
echo "  Candidate files scanned:  ${#candidate_files[@]}"
echo "  Metrics files analyzed:   ${runs_analyzed}"
echo "  Non-metrics skipped:      ${#skipped_files[@]}"
echo "  Metrics window (UTC):     ${metrics_window_start_utc} -> ${metrics_window_end_utc}"
echo "  Kind counts:              auth_fallback=${kind_auth_fallback_count} cache_degradation=${kind_cache_degradation_count} other=${kind_other_count}"
echo "  Status counts:            failure=${status_failure_count} recovered=${status_recovered_count} other=${status_other_count}"
echo "  Mode counts:              dry_run=${mode_dry_run_count} live=${mode_live_count}"
echo "  Open pages p50/p95/max:   ${open_pages_scanned_p50} / ${open_pages_scanned_p95} / ${open_pages_scanned_max}"
echo "  Open match p50/p95/max:   ${open_match_page_p50} / ${open_match_page_p95} / ${open_match_page_max}"
echo "  Open limit-hit count:     ${open_limit_hit_count} (${open_limit_hit_rate_percent}%)"
echo "  Closed pages p50/p95/max: ${closed_pages_scanned_p50} / ${closed_pages_scanned_p95} / ${closed_pages_scanned_max}"
echo "  Closed match p50/p95/max: ${closed_match_page_p50} / ${closed_match_page_p95} / ${closed_match_page_max}"
echo "  Closed limit-hit count:   ${closed_limit_hit_count} (${closed_limit_hit_rate_percent}%)"
echo "  Recommendation:           set escalation_open_issues_max_pages=${recommended_open_issues_max_pages}"
echo "                            set escalation_closed_issues_max_pages=${recommended_closed_issues_max_pages}"
echo "                            (buffer ${READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES}, min-open ${MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES}, min-closed ${MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES})"

if [ "${runs_analyzed}" -lt 10 ]; then
  echo "  Confidence note:          low sample size (${runs_analyzed} run(s)); keep in audit mode until >=10 runs."
fi

if [ -n "${READINESS_ESCALATION_METRICS_SUMMARY_FILE}" ]; then
  summary_dir="$(dirname "${READINESS_ESCALATION_METRICS_SUMMARY_FILE}")"
  if [ "${summary_dir}" != "." ]; then
    mkdir -p "${summary_dir}"
  fi

  source_files_json="$(printf '%s\n' "${metrics_files[@]}" | jq -R . | jq -s .)"
  generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -n \
    --arg generated_at_utc "${generated_at_utc}" \
    --arg metrics_window_start_utc "${metrics_window_start_utc}" \
    --arg metrics_window_end_utc "${metrics_window_end_utc}" \
    --argjson source_files "${source_files_json}" \
    --argjson runs_analyzed "${runs_analyzed}" \
    --argjson non_metrics_skipped "${#skipped_files[@]}" \
    --argjson kind_auth_fallback_count "${kind_auth_fallback_count}" \
    --argjson kind_cache_degradation_count "${kind_cache_degradation_count}" \
    --argjson kind_other_count "${kind_other_count}" \
    --argjson status_failure_count "${status_failure_count}" \
    --argjson status_recovered_count "${status_recovered_count}" \
    --argjson status_other_count "${status_other_count}" \
    --argjson mode_dry_run_count "${mode_dry_run_count}" \
    --argjson mode_live_count "${mode_live_count}" \
    --argjson open_pages_scanned_p50 "${open_pages_scanned_p50}" \
    --argjson open_pages_scanned_p95 "${open_pages_scanned_p95}" \
    --argjson open_pages_scanned_max "${open_pages_scanned_max}" \
    --argjson open_match_page_p50 "${open_match_page_p50}" \
    --argjson open_match_page_p95 "${open_match_page_p95}" \
    --argjson open_match_page_max "${open_match_page_max}" \
    --argjson open_limit_hit_count "${open_limit_hit_count}" \
    --argjson open_limit_hit_rate_percent "${open_limit_hit_rate_percent}" \
    --argjson closed_pages_scanned_p50 "${closed_pages_scanned_p50}" \
    --argjson closed_pages_scanned_p95 "${closed_pages_scanned_p95}" \
    --argjson closed_pages_scanned_max "${closed_pages_scanned_max}" \
    --argjson closed_match_page_p50 "${closed_match_page_p50}" \
    --argjson closed_match_page_p95 "${closed_match_page_p95}" \
    --argjson closed_match_page_max "${closed_match_page_max}" \
    --argjson closed_limit_hit_count "${closed_limit_hit_count}" \
    --argjson closed_limit_hit_rate_percent "${closed_limit_hit_rate_percent}" \
    --argjson recommended_open_issues_max_pages "${recommended_open_issues_max_pages}" \
    --argjson recommended_closed_issues_max_pages "${recommended_closed_issues_max_pages}" \
    --argjson buffer_pages "${READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES}" \
    --argjson min_open_pages "${MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES}" \
    --argjson min_closed_pages "${MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES}" \
    '{
      generated_at_utc: $generated_at_utc,
      metrics_window: {
        start_utc: $metrics_window_start_utc,
        end_utc: $metrics_window_end_utc
      },
      runs_analyzed: $runs_analyzed,
      non_metrics_skipped: $non_metrics_skipped,
      kind_counts: {
        auth_fallback: $kind_auth_fallback_count,
        cache_degradation: $kind_cache_degradation_count,
        other: $kind_other_count
      },
      status_counts: {
        failure: $status_failure_count,
        recovered: $status_recovered_count,
        other: $status_other_count
      },
      mode_counts: {
        dry_run: $mode_dry_run_count,
        live: $mode_live_count
      },
      open_pages: {
        scanned_percentiles: {
          p50: $open_pages_scanned_p50,
          p95: $open_pages_scanned_p95,
          max: $open_pages_scanned_max
        },
        match_percentiles: {
          p50: $open_match_page_p50,
          p95: $open_match_page_p95,
          max: $open_match_page_max
        },
        limit_hit_count: $open_limit_hit_count,
        limit_hit_rate_percent: $open_limit_hit_rate_percent
      },
      closed_pages: {
        scanned_percentiles: {
          p50: $closed_pages_scanned_p50,
          p95: $closed_pages_scanned_p95,
          max: $closed_pages_scanned_max
        },
        match_percentiles: {
          p50: $closed_match_page_p50,
          p95: $closed_match_page_p95,
          max: $closed_match_page_max
        },
        limit_hit_count: $closed_limit_hit_count,
        limit_hit_rate_percent: $closed_limit_hit_rate_percent
      },
      recommendation: {
        escalation_open_issues_max_pages: $recommended_open_issues_max_pages,
        escalation_closed_issues_max_pages: $recommended_closed_issues_max_pages,
        buffer_pages: $buffer_pages,
        min_open_pages: $min_open_pages,
        min_closed_pages: $min_closed_pages
      },
      source_files: $source_files
    }' > "${READINESS_ESCALATION_METRICS_SUMMARY_FILE}"

  echo "  JSON summary written:     ${READINESS_ESCALATION_METRICS_SUMMARY_FILE}"
fi
