#!/bin/bash
# Summarizes warm-cache run metrics and recommends a retry-rate threshold.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/summarize-warm-cache-metrics.sh [metrics-file-or-directory ...]

Environment:
  RETRY_RATE_BUFFER_PERCENT             Optional integer 0-100, default 5
  MIN_RECOMMENDED_RETRY_RATE_PERCENT    Optional integer 0-100, default 0
  WARMUP_METRICS_SUMMARY_FILE           Optional path for JSON summary output

Notes:
  - Directories are scanned recursively for *.json files.
  - Files are treated as warm-cache metrics only when required fields exist.
EOF
}

require_dependency() {
  local dependency="$1"
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Error: required dependency '${dependency}' is not installed."
    exit 1
  fi
}

validate_percent_env() {
  local var_name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -gt 100 ]; then
    echo "Error: ${var_name} must be an integer between 0 and 100."
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
    (.retry_rate_percent | type == "number")
    and (.outcome | type == "string")
    and (.generated_at_utc | type == "string")
    and (.exit_code | type == "number")
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

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_dependency "jq"
require_dependency "find"

RETRY_RATE_BUFFER_PERCENT="${RETRY_RATE_BUFFER_PERCENT:-5}"
MIN_RECOMMENDED_RETRY_RATE_PERCENT="${MIN_RECOMMENDED_RETRY_RATE_PERCENT:-0}"
WARMUP_METRICS_SUMMARY_FILE="${WARMUP_METRICS_SUMMARY_FILE:-}"

validate_percent_env "RETRY_RATE_BUFFER_PERCENT" "${RETRY_RATE_BUFFER_PERCENT}"
validate_percent_env "MIN_RECOMMENDED_RETRY_RATE_PERCENT" "${MIN_RECOMMENDED_RETRY_RATE_PERCENT}"

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
  echo "Error: no valid warm-cache metrics files found."
  echo "Hint: pass one or more warm-generated-cache metrics JSON files or directories."
  exit 1
fi

success_count=0
failed_requests_count=0
retry_rate_exceeded_count=0
other_outcome_count=0
retry_rates=()
target_dates=()

for metrics_file in "${metrics_files[@]}"; do
  retry_rate="$(jq -r '.retry_rate_percent | floor' "${metrics_file}")"
  outcome="$(jq -r '.outcome' "${metrics_file}")"
  target_date="$(jq -r '.target_date // empty' "${metrics_file}")"

  retry_rates+=("${retry_rate}")

  if [ -n "${target_date}" ] && [ "${target_date}" != "null" ]; then
    target_dates+=("${target_date}")
  fi

  case "${outcome}" in
    success)
      success_count=$((success_count + 1))
      ;;
    failed_requests)
      failed_requests_count=$((failed_requests_count + 1))
      ;;
    retry_rate_exceeded)
      retry_rate_exceeded_count=$((retry_rate_exceeded_count + 1))
      ;;
    *)
      other_outcome_count=$((other_outcome_count + 1))
      ;;
  esac
done

p50_retry_rate="$(percentile_nearest_rank 50 "${retry_rates[@]}")"
p95_retry_rate="$(percentile_nearest_rank 95 "${retry_rates[@]}")"
max_retry_rate="$(percentile_nearest_rank 100 "${retry_rates[@]}")"
runs_analyzed="${#metrics_files[@]}"

recommended_retry_rate=$((p95_retry_rate + RETRY_RATE_BUFFER_PERCENT))
if [ "${recommended_retry_rate}" -lt "${MIN_RECOMMENDED_RETRY_RATE_PERCENT}" ]; then
  recommended_retry_rate="${MIN_RECOMMENDED_RETRY_RATE_PERCENT}"
fi
if [ "${recommended_retry_rate}" -gt 100 ]; then
  recommended_retry_rate=100
fi

target_date_range="(unavailable)"
if [ "${#target_dates[@]}" -gt 0 ]; then
  min_target_date="$(printf '%s\n' "${target_dates[@]}" | sort | head -n 1)"
  max_target_date="$(printf '%s\n' "${target_dates[@]}" | sort | tail -n 1)"
  target_date_range="${min_target_date} -> ${max_target_date}"
fi

echo "Warm-cache metrics summary"
echo "  Candidate files scanned: ${#candidate_files[@]}"
echo "  Metrics files analyzed:  ${runs_analyzed}"
echo "  Non-metrics skipped:     ${#skipped_files[@]}"
echo "  Target date range:       ${target_date_range}"
echo "  Outcome counts:          success=${success_count} failed_requests=${failed_requests_count} retry_rate_exceeded=${retry_rate_exceeded_count} other=${other_outcome_count}"
echo "  Retry rate p50/p95/max:  ${p50_retry_rate}% / ${p95_retry_rate}% / ${max_retry_rate}%"
echo "  Recommendation:          set WARMUP_MAX_RETRY_RATE_PERCENT=${recommended_retry_rate}"
echo "                           (p95 ${p95_retry_rate}% + buffer ${RETRY_RATE_BUFFER_PERCENT}%, floor ${MIN_RECOMMENDED_RETRY_RATE_PERCENT}%)"

if [ "${runs_analyzed}" -lt 10 ]; then
  echo "  Confidence note:         low sample size (${runs_analyzed} run(s)); keep threshold in audit mode until >=10 runs."
fi

if [ -n "${WARMUP_METRICS_SUMMARY_FILE}" ]; then
  summary_dir="$(dirname "${WARMUP_METRICS_SUMMARY_FILE}")"
  if [ "${summary_dir}" != "." ]; then
    mkdir -p "${summary_dir}"
  fi

  source_files_json="$(printf '%s\n' "${metrics_files[@]}" | jq -R . | jq -s .)"
  generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -n \
    --arg generated_at_utc "${generated_at_utc}" \
    --argjson source_files "${source_files_json}" \
    --arg target_date_range "${target_date_range}" \
    --argjson runs_analyzed "${runs_analyzed}" \
    --argjson non_metrics_skipped "${#skipped_files[@]}" \
    --argjson p50_retry_rate_percent "${p50_retry_rate}" \
    --argjson p95_retry_rate_percent "${p95_retry_rate}" \
    --argjson max_retry_rate_percent "${max_retry_rate}" \
    --argjson retry_rate_buffer_percent "${RETRY_RATE_BUFFER_PERCENT}" \
    --argjson min_recommended_retry_rate_percent "${MIN_RECOMMENDED_RETRY_RATE_PERCENT}" \
    --argjson recommended_max_retry_rate_percent "${recommended_retry_rate}" \
    --argjson success_count "${success_count}" \
    --argjson failed_requests_count "${failed_requests_count}" \
    --argjson retry_rate_exceeded_count "${retry_rate_exceeded_count}" \
    --argjson other_outcome_count "${other_outcome_count}" \
    '{
      generated_at_utc: $generated_at_utc,
      target_date_range: $target_date_range,
      runs_analyzed: $runs_analyzed,
      non_metrics_skipped: $non_metrics_skipped,
      retry_rate_percentiles: {
        p50: $p50_retry_rate_percent,
        p95: $p95_retry_rate_percent,
        max: $max_retry_rate_percent
      },
      outcomes: {
        success: $success_count,
        failed_requests: $failed_requests_count,
        retry_rate_exceeded: $retry_rate_exceeded_count,
        other: $other_outcome_count
      },
      recommendation: {
        max_retry_rate_percent: $recommended_max_retry_rate_percent,
        buffer_percent: $retry_rate_buffer_percent,
        floor_percent: $min_recommended_retry_rate_percent
      },
      source_files: $source_files
    }' > "${WARMUP_METRICS_SUMMARY_FILE}"

  echo "  JSON summary written:    ${WARMUP_METRICS_SUMMARY_FILE}"
fi
