#!/bin/bash
# Runs focused edge-function regression suites for deployment guardrails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DENO_TEST_DIR=""
NODE_TEST_DIR=""
SEARCH_DIR="${SCRIPT_DIR}"
REQUIRE_DENO="$(printf '%s' "${REQUIRE_DENO:-false}" | tr '[:upper:]' '[:lower:]')"
DENO_DOCKER_IMAGE="${DENO_DOCKER_IMAGE:-denoland/deno:2.2.3}"
ALLOW_DOCKER_DENO="$(printf '%s' "${ALLOW_DOCKER_DENO:-true}" | tr '[:upper:]' '[:lower:]')"
ALLOW_AUTO_INSTALL_DENO="$(printf '%s' "${ALLOW_AUTO_INSTALL_DENO:-true}" | tr '[:upper:]' '[:lower:]')"
DENO_AUTO_VERSION="${DENO_AUTO_VERSION:-2.2.3}"
DENO_INSTALL_DIR="${DENO_INSTALL_DIR:-}"
REPO_ROOT=""

if [ "${REQUIRE_DENO}" != "true" ] && [ "${REQUIRE_DENO}" != "false" ]; then
  echo "Invalid REQUIRE_DENO value '${REQUIRE_DENO}'. Expected true or false."
  exit 1
fi

if [ "${ALLOW_DOCKER_DENO}" != "true" ] && [ "${ALLOW_DOCKER_DENO}" != "false" ]; then
  echo "Invalid ALLOW_DOCKER_DENO value '${ALLOW_DOCKER_DENO}'. Expected true or false."
  exit 1
fi

if [ "${ALLOW_AUTO_INSTALL_DENO}" != "true" ] && [ "${ALLOW_AUTO_INSTALL_DENO}" != "false" ]; then
  echo "Invalid ALLOW_AUTO_INSTALL_DENO value '${ALLOW_AUTO_INSTALL_DENO}'. Expected true or false."
  exit 1
fi

if ! [[ "${DENO_AUTO_VERSION}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid DENO_AUTO_VERSION value '${DENO_AUTO_VERSION}'. Expected semantic version like 2.2.3 or v2.2.3."
  exit 1
fi

if [ "${REQUIRE_DENO}" = "true" ]; then
  if [ "${ALLOW_AUTO_INSTALL_DENO}" = "true" ] || [ "${ALLOW_DOCKER_DENO}" = "true" ]; then
    echo "REQUIRE_DENO=true: disabling automatic Deno bootstrap and Docker fallback; expecting Deno on PATH."
  fi
  ALLOW_AUTO_INSTALL_DENO="false"
  ALLOW_DOCKER_DENO="false"
fi

while [ "${SEARCH_DIR}" != "/" ]; do
  if [ -f "${SEARCH_DIR}/edge-functions/generate-horoscope/rate-limit.test.ts" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    DENO_TEST_DIR="${SEARCH_DIR}/edge-functions/generate-horoscope"
    NODE_TEST_DIR="${SEARCH_DIR}/edge-functions/generate-horoscope"
    break
  fi
  if [ -f "${SEARCH_DIR}/supabase/functions/generate-horoscope/rate-limit.test.ts" ]; then
    REPO_ROOT="${SEARCH_DIR}"
    DENO_TEST_DIR="${SEARCH_DIR}/supabase/functions/generate-horoscope"
    NODE_TEST_DIR="${SEARCH_DIR}/supabase/functions/generate-horoscope"
    break
  fi
  SEARCH_DIR="$(dirname "${SEARCH_DIR}")"
done

if [ -z "${DENO_TEST_DIR}" ] || [ -z "${NODE_TEST_DIR}" ]; then
  echo "Unable to locate edge-function test files from ${SCRIPT_DIR}"
  exit 1
fi

collect_tests() {
  local directory="$1"
  local pattern="$2"
  find "${directory}" -maxdepth 1 -type f -name "${pattern}" | sort
}

ran_any=0
ran_deno=0

run_deno_tests_with_docker() {
  local directory="$1"
  shift

  local docker_test_files=()
  local file_name
  for file_name in "$@"; do
    docker_test_files+=("$(basename "${file_name}")")
  done

  docker run --rm \
    -v "${directory}:/workspace:ro" \
    -w /workspace \
    "${DENO_DOCKER_IMAGE}" \
    test --no-check "${docker_test_files[@]}"
}

resolve_deno_release_target() {
  local os
  local arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64)
      arch="x86_64"
      ;;
    arm64|aarch64)
      arch="aarch64"
      ;;
    *)
      echo "Automatic Deno bootstrap does not support architecture '${arch}'." >&2
      return 1
      ;;
  esac

  case "${os}" in
    linux)
      printf '%s\n' "${arch}-unknown-linux-gnu"
      ;;
    darwin)
      printf '%s\n' "${arch}-apple-darwin"
      ;;
    *)
      echo "Automatic Deno bootstrap does not support OS '${os}'." >&2
      return 1
      ;;
  esac
}

resolve_deno_install_bases() {
  {
    [ -n "${DENO_INSTALL_DIR}" ] && printf '%s\n' "${DENO_INSTALL_DIR%/}"
    [ -n "${XDG_CACHE_HOME:-}" ] && printf '%s\n' "${XDG_CACHE_HOME%/}/aura-deno"
    [ -n "${HOME:-}" ] && printf '%s\n' "${HOME%/}/.cache/aura-deno"
    [ -n "${REPO_ROOT}" ] && printf '%s\n' "${REPO_ROOT%/}/.cache/aura-deno"
    [ -n "${TMPDIR:-}" ] && printf '%s\n' "${TMPDIR%/}/aura-deno"
    printf '%s\n' "/tmp/aura-deno"
  } | awk 'NF && !seen[$0]++'
}

install_auto_deno() {
  local target
  local version_tag
  local install_base
  local install_root
  local deno_bin
  local archive_name
  local download_url
  local download_path
  local extract_dir
  local error_detail
  local install_errors=()

  if ! command -v curl >/dev/null 2>&1; then
    echo "Automatic Deno bootstrap requires curl." >&2
    return 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    echo "Automatic Deno bootstrap requires unzip." >&2
    return 1
  fi

  target="$(resolve_deno_release_target)" || return 1
  version_tag="v${DENO_AUTO_VERSION#v}"
  archive_name="deno-${target}.zip"
  download_url="https://github.com/denoland/deno/releases/download/${version_tag}/${archive_name}"

  while IFS= read -r install_base; do
    [ -z "${install_base}" ] && continue

    install_root="${install_base%/}/${version_tag}/${target}"
    deno_bin="${install_root}/deno"
    download_path="${install_root}/deno.zip"
    extract_dir="${install_root}/extract"

    if [ -x "${deno_bin}" ]; then
      printf '%s\n' "${deno_bin}"
      return 0
    fi

    rm -rf "${extract_dir}" >/dev/null 2>&1 || true
    if ! mkdir -p "${install_root}" "${extract_dir}" >/dev/null 2>&1; then
      install_errors+=("${install_root}: mkdir_failed")
      continue
    fi

    if ! curl -fsSL "${download_url}" -o "${download_path}"; then
      install_errors+=("${install_root}: download_failed")
      rm -f "${download_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if ! unzip -oq "${download_path}" -d "${extract_dir}"; then
      install_errors+=("${install_root}: extract_failed")
      rm -f "${download_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if [ ! -f "${extract_dir}/deno" ]; then
      install_errors+=("${install_root}: missing_binary")
      rm -f "${download_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if ! mv "${extract_dir}/deno" "${deno_bin}"; then
      install_errors+=("${install_root}: move_failed")
      rm -f "${download_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if ! chmod +x "${deno_bin}"; then
      install_errors+=("${install_root}: chmod_failed")
      rm -f "${deno_bin}" "${download_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    rm -f "${download_path}"
    rm -rf "${extract_dir}"
    printf '%s\n' "${deno_bin}"
    return 0
  done < <(resolve_deno_install_bases)

  echo "Failed to install Deno automatically in any candidate install root." >&2
  echo "Attempted install roots:" >&2
  while IFS= read -r install_base; do
    [ -n "${install_base}" ] && echo "  - ${install_base}" >&2
  done < <(resolve_deno_install_bases)

  if [ "${#install_errors[@]}" -gt 0 ]; then
    echo "Failure details:" >&2
    for error_detail in "${install_errors[@]}"; do
      echo "  - ${error_detail}" >&2
    done
  fi
  echo "Set DENO_INSTALL_DIR to a writable location and retry." >&2
  return 1
}

run_deno_tests() {
  local deno_binary="$1"
  shift
  "${deno_binary}" test --no-check "$@"
}

if command -v node >/dev/null 2>&1; then
  node_tests=()
  while IFS= read -r test_file; do
    [ -n "${test_file}" ] && node_tests+=("${test_file}")
  done < <(collect_tests "${NODE_TEST_DIR}" "*.node.test.mjs")
  if [ "${#node_tests[@]}" -gt 0 ]; then
    echo "Running Node-based edge tests..."
    node --test "${node_tests[@]}"
    ran_any=1
  else
    echo "No Node edge-function test files found in ${NODE_TEST_DIR}; skipping Node tests."
  fi
else
  echo "node is not available; skipping Node edge-function tests."
fi

deno_tests=()
while IFS= read -r test_file; do
  [ -n "${test_file}" ] && deno_tests+=("${test_file}")
done < <(collect_tests "${DENO_TEST_DIR}" "*.test.ts")

deno_cmd=""
if command -v deno >/dev/null 2>&1; then
  deno_cmd="$(command -v deno)"
elif [ "${ALLOW_AUTO_INSTALL_DENO}" = "true" ]; then
  echo "deno is not available; attempting automatic bootstrap (version ${DENO_AUTO_VERSION})..."
  if deno_cmd="$(install_auto_deno)"; then
    echo "Using auto-installed Deno binary at ${deno_cmd}."
  else
    echo "Automatic Deno bootstrap failed."
  fi
fi

if [ "${#deno_tests[@]}" -eq 0 ]; then
  echo "No Deno edge-function test files found in ${DENO_TEST_DIR}; skipping Deno tests."
elif [ -n "${deno_cmd}" ]; then
  echo "Running Deno edge-function tests..."
  run_deno_tests "${deno_cmd}" "${deno_tests[@]}"
  ran_any=1
  ran_deno=1
elif [ "${ALLOW_DOCKER_DENO}" = "true" ] && command -v docker >/dev/null 2>&1; then
  echo "deno is not available; running Deno edge-function tests via Docker (${DENO_DOCKER_IMAGE})..."
  run_deno_tests_with_docker "${DENO_TEST_DIR}" "${deno_tests[@]}"
  ran_any=1
  ran_deno=1
else
  echo "deno is not available; skipping Deno edge-function tests."
  if [ "${ALLOW_AUTO_INSTALL_DENO}" = "true" ]; then
    echo "Automatic Deno bootstrap did not complete successfully."
  fi
  [ "${ALLOW_DOCKER_DENO}" = "true" ] && echo "Docker fallback unavailable; install Deno or Docker to run Deno edge-function tests."
fi

if [ "${REQUIRE_DENO}" = "true" ]; then
  if [ "${ran_deno}" -eq 0 ]; then
    echo "Deno is required for this test run, but no Deno edge-function tests were executed."
    echo "Install Deno and ensure the 'deno' binary is available on PATH before running with REQUIRE_DENO=true."
    exit 1
  fi
fi

if [ "${ran_any}" -eq 0 ]; then
  echo "No supported edge-function test runtime found."
  echo "Install Node.js (v22+) or Deno to run edge-function tests."
  exit 1
fi

echo "Edge-function regression suite passed."
