#!/bin/bash
# Safely updates GENERATE_HOROSCOPE_AUTH_MODE with readiness guardrails.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_READINESS_SCRIPT="${SCRIPT_DIR}/check-auth-fallback-readiness.sh"
CACHE_READINESS_SCRIPT="${SCRIPT_DIR}/check-cache-degradation-readiness.sh"

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/set-generate-horoscope-auth-mode.sh <legacy|audit|enforce>

Required environment:
  SUPABASE_PROJECT_REF=<project-ref>

Additional requirements for enforce:
  SUPABASE_SERVICE_ROLE_KEY=<service-role-key>

Optional environment:
  AUTH_READINESS_LOOKBACK_DAYS=<default: LOOKBACK_DAYS or 3 when enforce>
  AUTH_READINESS_MAX_FALLBACKS=<default: MAX_FALLBACKS or 0 when enforce>
  AUTH_READINESS_CONTEXT_FILTER=<default: AUTH_CONTEXT_FILTER or all when enforce>
  CACHE_READINESS_LOOKBACK_DAYS=<default: 2 when enforce>
  CACHE_READINESS_MAX_DEGRADATIONS=<default: 0 when enforce>
  CACHE_READINESS_PREMIUM_FILTER=<default: all when enforce>
  CACHE_READINESS_REASON_FILTER=<default: all when enforce>
  SKIP_READINESS_CHECK=true   # emergency override for enforce (both readiness gates)
EOF
}

MODE="${1:-${GENERATE_HOROSCOPE_AUTH_MODE:-}}"
if [ -z "${MODE}" ]; then
  usage
  echo -e "${RED}Error: auth mode argument is required.${NC}"
  exit 1
fi

MODE="$(printf "%s" "${MODE}" | tr '[:upper:]' '[:lower:]')"
case "${MODE}" in
  legacy|audit|enforce) ;;
  *)
    usage
    echo -e "${RED}Error: unsupported auth mode '${MODE}'.${NC}"
    exit 1
    ;;
esac

if [ -z "${SUPABASE_PROJECT_REF:-}" ]; then
  echo -e "${RED}Error: SUPABASE_PROJECT_REF is required.${NC}"
  exit 1
fi

echo -e "${BLUE}Target project:${NC} ${SUPABASE_PROJECT_REF}"
echo -e "${BLUE}Requested mode:${NC} ${MODE}"

if [ "${MODE}" = "enforce" ]; then
  if [ "${SKIP_READINESS_CHECK:-false}" = "true" ]; then
    echo -e "${YELLOW}Skipping readiness check because SKIP_READINESS_CHECK=true.${NC}"
  else
    if [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
      echo -e "${RED}Error: SUPABASE_SERVICE_ROLE_KEY is required before switching to enforce.${NC}"
      exit 1
    fi
    if [ ! -f "${AUTH_READINESS_SCRIPT}" ]; then
      echo -e "${RED}Error: auth readiness script not found at ${AUTH_READINESS_SCRIPT}.${NC}"
      exit 1
    fi
    if [ ! -f "${CACHE_READINESS_SCRIPT}" ]; then
      echo -e "${RED}Error: cache readiness script not found at ${CACHE_READINESS_SCRIPT}.${NC}"
      exit 1
    fi

    AUTH_LOOKBACK_DAYS="${AUTH_READINESS_LOOKBACK_DAYS:-${LOOKBACK_DAYS:-3}}"
    AUTH_MAX_FALLBACKS="${AUTH_READINESS_MAX_FALLBACKS:-${MAX_FALLBACKS:-0}}"
    AUTH_CONTEXT_FILTER_VALUE="${AUTH_READINESS_CONTEXT_FILTER:-${AUTH_CONTEXT_FILTER:-all}}"

    CACHE_LOOKBACK_DAYS="${CACHE_READINESS_LOOKBACK_DAYS:-2}"
    CACHE_MAX_DEGRADATIONS="${CACHE_READINESS_MAX_DEGRADATIONS:-0}"
    CACHE_PREMIUM_FILTER_VALUE="${CACHE_READINESS_PREMIUM_FILTER:-all}"
    CACHE_REASON_FILTER_VALUE="${CACHE_READINESS_REASON_FILTER:-all}"

    echo -e "${BLUE}Running auth fallback readiness guard...${NC}"
    echo "LOOKBACK_DAYS=${AUTH_LOOKBACK_DAYS}"
    echo "MAX_FALLBACKS=${AUTH_MAX_FALLBACKS}"
    echo "AUTH_CONTEXT_FILTER=${AUTH_CONTEXT_FILTER_VALUE}"
    echo ""
    LOOKBACK_DAYS="${AUTH_LOOKBACK_DAYS}" \
    MAX_FALLBACKS="${AUTH_MAX_FALLBACKS}" \
    AUTH_CONTEXT_FILTER="${AUTH_CONTEXT_FILTER_VALUE}" \
    bash "${AUTH_READINESS_SCRIPT}"
    echo ""
    echo -e "${GREEN}Auth fallback readiness guard passed.${NC}"
    echo ""

    echo -e "${BLUE}Running shared cache degradation readiness guard...${NC}"
    echo "LOOKBACK_DAYS=${CACHE_LOOKBACK_DAYS}"
    echo "MAX_DEGRADATIONS=${CACHE_MAX_DEGRADATIONS}"
    echo "PREMIUM_FILTER=${CACHE_PREMIUM_FILTER_VALUE}"
    echo "REASON_FILTER=${CACHE_REASON_FILTER_VALUE}"
    echo ""
    LOOKBACK_DAYS="${CACHE_LOOKBACK_DAYS}" \
    MAX_DEGRADATIONS="${CACHE_MAX_DEGRADATIONS}" \
    PREMIUM_FILTER="${CACHE_PREMIUM_FILTER_VALUE}" \
    REASON_FILTER="${CACHE_REASON_FILTER_VALUE}" \
    bash "${CACHE_READINESS_SCRIPT}"
    echo ""
    echo -e "${GREEN}Shared cache degradation readiness guard passed.${NC}"
  fi
fi

echo -e "${BLUE}Updating GENERATE_HOROSCOPE_AUTH_MODE secret...${NC}"
supabase secrets set --project-ref "${SUPABASE_PROJECT_REF}" "GENERATE_HOROSCOPE_AUTH_MODE=${MODE}"

echo ""
echo -e "${GREEN}Success: GENERATE_HOROSCOPE_AUTH_MODE=${MODE}${NC}"
if [ "${MODE}" = "enforce" ]; then
  echo -e "${YELLOW}Reminder:${NC} monitor auth-fallback and cache-degradation readiness workflows plus edge function errors after rollout."
fi
