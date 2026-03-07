#!/bin/bash
# Validates GitHub Actions workflows with YAML parsing and actionlint checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "${SCRIPT_DIR}/../.github/workflows" ]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [ -d "${SCRIPT_DIR}/../../.github/workflows" ]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  echo "Workflow lint failed: unable to locate repository root from ${SCRIPT_DIR}."
  exit 1
fi

WORKFLOW_DIR="${REPO_ROOT}/.github/workflows"
ACTIONLINT_DOCKER_IMAGE="${ACTIONLINT_DOCKER_IMAGE:-rhysd/actionlint:latest}"
ACTIONLINT_GO_PACKAGE="${ACTIONLINT_GO_PACKAGE:-github.com/rhysd/actionlint/cmd/actionlint@latest}"
ACTIONLINT_FALLBACK_TIMEOUT_SECONDS="${ACTIONLINT_FALLBACK_TIMEOUT_SECONDS:-45}"
ACTIONLINT_AUTO_INSTALL="$(printf '%s' "${ACTIONLINT_AUTO_INSTALL:-true}" | tr '[:upper:]' '[:lower:]')"
ACTIONLINT_AUTO_VERSION="${ACTIONLINT_AUTO_VERSION:-1.7.7}"
ACTIONLINT_INSTALL_DIR="${ACTIONLINT_INSTALL_DIR:-}"

skip_actionlint=0

usage() {
  cat <<'EOF'
Usage: lint-workflows.sh [--skip-actionlint]

Options:
  --skip-actionlint  Run YAML parse checks only.

Environment:
  ACTIONLINT_DOCKER_IMAGE  Docker image used when actionlint binary is missing.
  ACTIONLINT_GO_PACKAGE    Go package used when actionlint binary is missing.
  ACTIONLINT_FALLBACK_TIMEOUT_SECONDS  Max seconds per docker/go fallback attempt (0 disables timeout).
  ACTIONLINT_AUTO_INSTALL  Attempt to auto-download actionlint release binary (true|false).
  ACTIONLINT_AUTO_VERSION  actionlint version for auto-download fallback (for example: 1.7.7).
  ACTIONLINT_INSTALL_DIR   Optional writable install root for auto-downloaded actionlint binaries.
EOF
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if [ "${timeout_seconds}" -le 0 ]; then
    "$@"
    return $?
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_seconds}" "$@"
    return $?
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_seconds}" "$@"
    return $?
  fi

  "$@" &
  local command_pid="$!"
  local elapsed=0

  while kill -0 "${command_pid}" >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${timeout_seconds}" ]; then
      kill -TERM "${command_pid}" >/dev/null 2>&1 || true
      sleep 1
      kill -KILL "${command_pid}" >/dev/null 2>&1 || true
      wait "${command_pid}" >/dev/null 2>&1 || true
      return 124
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "${command_pid}"
}

is_timeout_exit_code() {
  local status="$1"
  [ "${status}" -eq 124 ] || [ "${status}" -eq 137 ]
}

resolve_actionlint_release_target() {
  local os
  local arch

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${os}" in
    linux|darwin)
      ;;
    *)
      echo "Automatic actionlint bootstrap does not support OS '${os}'." >&2
      return 1
      ;;
  esac

  case "${arch}" in
    x86_64|amd64)
      arch="amd64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      echo "Automatic actionlint bootstrap does not support architecture '${arch}'." >&2
      return 1
      ;;
  esac

  printf '%s|%s\n' "${os}" "${arch}"
}

resolve_actionlint_install_bases() {
  {
    [ -n "${ACTIONLINT_INSTALL_DIR}" ] && printf '%s\n' "${ACTIONLINT_INSTALL_DIR%/}"
    [ -n "${XDG_CACHE_HOME:-}" ] && printf '%s\n' "${XDG_CACHE_HOME%/}/aura-actionlint"
    [ -n "${HOME:-}" ] && printf '%s\n' "${HOME%/}/.cache/aura-actionlint"
    [ -n "${REPO_ROOT}" ] && printf '%s\n' "${REPO_ROOT%/}/.cache/aura-actionlint"
    [ -n "${TMPDIR:-}" ] && printf '%s\n' "${TMPDIR%/}/aura-actionlint"
    printf '%s\n' "/tmp/aura-actionlint"
  } | awk 'NF && !seen[$0]++'
}

install_auto_actionlint() {
  local fallback_timeout_seconds="$1"
  local target
  local target_os
  local target_arch
  local version_tag
  local version_value
  local archive_name
  local download_url
  local install_base
  local install_root
  local actionlint_bin
  local archive_path
  local extract_dir
  local extracted_bin
  local install_errors=()
  local error_detail
  local curl_args=()

  if ! command -v curl >/dev/null 2>&1; then
    echo "Automatic actionlint bootstrap requires curl." >&2
    return 1
  fi

  if ! command -v tar >/dev/null 2>&1; then
    echo "Automatic actionlint bootstrap requires tar." >&2
    return 1
  fi

  target="$(resolve_actionlint_release_target)" || return 1
  target_os="${target%%|*}"
  target_arch="${target#*|}"
  if [ "${target_os}" = "${target}" ] || [ -z "${target_arch}" ]; then
    echo "Automatic actionlint bootstrap could not parse release target '${target}'." >&2
    return 1
  fi

  version_value="${ACTIONLINT_AUTO_VERSION#v}"
  version_tag="v${version_value}"
  archive_name="actionlint_${version_value}_${target_os}_${target_arch}.tar.gz"
  download_url="https://github.com/rhysd/actionlint/releases/download/${version_tag}/${archive_name}"

  if [ "${fallback_timeout_seconds}" -gt 0 ]; then
    curl_args=(--connect-timeout 10 --max-time "${fallback_timeout_seconds}")
  fi

  while IFS= read -r install_base; do
    [ -z "${install_base}" ] && continue

    install_root="${install_base%/}/${version_tag}/${target_os}_${target_arch}"
    actionlint_bin="${install_root}/actionlint"
    archive_path="${install_root}/${archive_name}"
    extract_dir="${install_root}/extract"

    if [ -x "${actionlint_bin}" ]; then
      printf '%s\n' "${actionlint_bin}"
      return 0
    fi

    rm -rf "${extract_dir}" >/dev/null 2>&1 || true
    if ! mkdir -p "${install_root}" "${extract_dir}" >/dev/null 2>&1; then
      install_errors+=("${install_root}: mkdir_failed")
      continue
    fi

    if ! curl -fsSL "${curl_args[@]}" "${download_url}" -o "${archive_path}"; then
      install_errors+=("${install_root}: download_failed")
      rm -f "${archive_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if ! tar -xzf "${archive_path}" -C "${extract_dir}" >/dev/null 2>&1; then
      install_errors+=("${install_root}: extract_failed")
      rm -f "${archive_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    extracted_bin="$(find "${extract_dir}" -type f -name actionlint | head -n 1)"
    if [ -z "${extracted_bin}" ]; then
      install_errors+=("${install_root}: missing_binary")
      rm -f "${archive_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if ! mv "${extracted_bin}" "${actionlint_bin}"; then
      install_errors+=("${install_root}: move_failed")
      rm -f "${archive_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    if ! chmod +x "${actionlint_bin}"; then
      install_errors+=("${install_root}: chmod_failed")
      rm -f "${actionlint_bin}" "${archive_path}"
      rm -rf "${extract_dir}"
      continue
    fi

    rm -f "${archive_path}"
    rm -rf "${extract_dir}"
    printf '%s\n' "${actionlint_bin}"
    return 0
  done < <(resolve_actionlint_install_bases)

  echo "Failed to auto-install actionlint in any candidate install root." >&2
  echo "Attempted install roots:" >&2
  while IFS= read -r install_base; do
    [ -n "${install_base}" ] && echo "  - ${install_base}" >&2
  done < <(resolve_actionlint_install_bases)

  if [ "${#install_errors[@]}" -gt 0 ]; then
    echo "Failure details:" >&2
    for error_detail in "${install_errors[@]}"; do
      echo "  - ${error_detail}" >&2
    done
  fi

  echo "Set ACTIONLINT_INSTALL_DIR to a writable location and retry." >&2
  return 1
}

run_actionlint_with_fallbacks() {
  local fallback_timeout_seconds="${ACTIONLINT_FALLBACK_TIMEOUT_SECONDS}"
  local actionlint_cmd=""

  if command -v actionlint >/dev/null 2>&1; then
    actionlint_cmd="$(command -v actionlint)"
  fi

  if [ -z "${actionlint_cmd}" ] && [ "${ACTIONLINT_AUTO_INSTALL}" = "true" ]; then
    echo "actionlint binary not found on PATH; attempting automatic bootstrap (version ${ACTIONLINT_AUTO_VERSION})..."
    if actionlint_cmd="$(install_auto_actionlint "${fallback_timeout_seconds}")"; then
      echo "Using auto-installed actionlint binary at ${actionlint_cmd}."
    else
      echo "Automatic actionlint bootstrap failed."
    fi
  fi

  if [ -n "${actionlint_cmd}" ]; then
    "${actionlint_cmd}" -color
    return 0
  fi

  echo "actionlint binary not found on PATH; attempting fallback runners."

  if command -v docker >/dev/null 2>&1; then
    echo "Trying docker fallback: ${ACTIONLINT_DOCKER_IMAGE} (timeout ${fallback_timeout_seconds}s)"
    if run_with_timeout "${fallback_timeout_seconds}" \
      docker run --rm -v "${REPO_ROOT}:/repo" -w /repo "${ACTIONLINT_DOCKER_IMAGE}" -color; then
      return 0
    fi
    local docker_status=$?
    if is_timeout_exit_code "${docker_status}" && [ "${fallback_timeout_seconds}" -gt 0 ]; then
      echo "Docker fallback timed out after ${fallback_timeout_seconds}s."
    else
      echo "Docker fallback failed."
    fi
  fi

  if command -v go >/dev/null 2>&1; then
    echo "Trying go fallback: go run ${ACTIONLINT_GO_PACKAGE} (timeout ${fallback_timeout_seconds}s)"
    if run_with_timeout "${fallback_timeout_seconds}" env GO111MODULE=on go run "${ACTIONLINT_GO_PACKAGE}" -color; then
      return 0
    fi
    local go_status=$?
    if is_timeout_exit_code "${go_status}" && [ "${fallback_timeout_seconds}" -gt 0 ]; then
      echo "Go fallback timed out after ${fallback_timeout_seconds}s."
    else
      echo "Go fallback failed."
    fi
  fi

  echo "Workflow lint failed: actionlint is unavailable."
  [ "${ACTIONLINT_AUTO_INSTALL}" = "true" ] && echo "Automatic actionlint bootstrap did not complete successfully."
  echo "Install actionlint (example: brew install actionlint), or ensure docker/go fallbacks are available."
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-actionlint)
      skip_actionlint=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
  shift
done

if [ ! -d "${WORKFLOW_DIR}" ]; then
  echo "Workflow lint failed: directory not found -> ${WORKFLOW_DIR}"
  exit 1
fi

if ! [[ "${ACTIONLINT_FALLBACK_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "Workflow lint failed: ACTIONLINT_FALLBACK_TIMEOUT_SECONDS must be a non-negative integer."
  exit 1
fi

if [ "${ACTIONLINT_AUTO_INSTALL}" != "true" ] && [ "${ACTIONLINT_AUTO_INSTALL}" != "false" ]; then
  echo "Workflow lint failed: ACTIONLINT_AUTO_INSTALL must be true or false."
  exit 1
fi

if ! [[ "${ACTIONLINT_AUTO_VERSION}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Workflow lint failed: ACTIONLINT_AUTO_VERSION must be semantic version like 1.7.7 or v1.7.7."
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "Workflow lint failed: ruby is required for YAML parsing."
  exit 1
fi

echo "Parsing workflow YAML files and checking local script references..."
(
  cd "${REPO_ROOT}"
  ruby -e '
require "psych"
require "set"
require "shellwords"

SHELL_COMMANDS = Set["bash", "sh", "zsh"].freeze
SOURCE_COMMANDS = Set[".", "source"].freeze
SHELL_OPTIONS_WITH_VALUE = Set["-c", "-o", "--command", "--init-file", "--rcfile"].freeze
ENV_ASSIGNMENT_REGEX = /\A[A-Za-z_][A-Za-z0-9_]*=/
DYNAMIC_TOKEN_PATTERN = /[\$\`\(\)\*\?\[\]\{\}!]/
WORKFLOW_SECRET_PATTERN = /\$\{\{\s*secrets\.([A-Za-z0-9_]+)\s*\}\}/
WORKFLOW_BUNDLE_ID_PATTERN = /\bcom\.[A-Za-z0-9.-]+\b/
TESTFLIGHT_HOSTED_WORKFLOW = ".github/workflows/testflight.yml"
TESTFLIGHT_SELF_HOSTED_WORKFLOW = ".github/workflows/testflight-selfhosted.yml"
AUTH_FALLBACK_READINESS_WORKFLOW = ".github/workflows/auth-fallback-readiness.yml"
CACHE_DEGRADATION_READINESS_WORKFLOW = ".github/workflows/cache-degradation-readiness.yml"
AUTH_ROLLOUT_REHEARSAL_WORKFLOW = ".github/workflows/auth-rollout-rehearsal.yml"
WARM_GENERATED_CACHE_WORKFLOW = ".github/workflows/warm-generated-cache.yml"
PRUNE_GENERATED_CACHE_WORKFLOW = ".github/workflows/prune-generated-cache.yml"
REQUIRED_WORKFLOW_SECRETS = {
  TESTFLIGHT_HOSTED_WORKFLOW => Set[
    "APPLE_CERTIFICATE_BASE64",
    "APPLE_CERTIFICATE_PASSWORD",
    "BUILD_PROVISION_PROFILE_BASE64",
    "APPLE_ISSUER_ID",
    "APPLE_API_KEY_ID",
    "APPLE_API_PRIVATE_KEY",
  ],
  TESTFLIGHT_SELF_HOSTED_WORKFLOW => Set[
    "BUILD_PROVISION_PROFILE_BASE64",
    "APPLE_ISSUER_ID",
    "APPLE_API_KEY_ID",
    "APPLE_API_PRIVATE_KEY",
  ],
  AUTH_FALLBACK_READINESS_WORKFLOW => Set[
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_PROJECT_REF",
    "SUPABASE_BASE_URL",
  ],
  CACHE_DEGRADATION_READINESS_WORKFLOW => Set[
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_PROJECT_REF",
    "SUPABASE_BASE_URL",
  ],
  AUTH_ROLLOUT_REHEARSAL_WORKFLOW => Set[
    "SUPABASE_ANON_KEY",
    "SUPABASE_PROJECT_REF",
    "SUPABASE_BASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "AUTH_TEST_BEARER_TOKEN",
    "AUTH_TEST_USER_ID",
    "AUTH_TEST_USER_EMAIL",
    "AUTH_TEST_USER_PASSWORD",
  ],
  WARM_GENERATED_CACHE_WORKFLOW => Set[
    "SUPABASE_ANON_KEY",
    "SUPABASE_PROJECT_REF",
    "SUPABASE_BASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "CACHE_WARM_SECRET",
  ],
  PRUNE_GENERATED_CACHE_WORKFLOW => Set[
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_PROJECT_REF",
    "SUPABASE_BASE_URL",
  ],
}.freeze
REQUIRED_TESTFLIGHT_SIGNING_DIRECTIVES = {
  TESTFLIGHT_HOSTED_WORKFLOW => Set[
    "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=\"Apple Distribution\"",
    "PROVISIONING_PROFILE_SPECIFIER=\"$PROVISIONING_PROFILE_UUID\"",
    "PRODUCT_BUNDLE_IDENTIFIER=\"$PRODUCT_BUNDLE_IDENTIFIER\"",
  ],
  TESTFLIGHT_SELF_HOSTED_WORKFLOW => Set[
    "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=\"Apple Distribution\"",
    "PROVISIONING_PROFILE_SPECIFIER=\"$PROVISIONING_PROFILE_UUID\"",
    "PRODUCT_BUNDLE_IDENTIFIER=\"$PRODUCT_BUNDLE_IDENTIFIER\"",
  ],
}.freeze
FORBIDDEN_TESTFLIGHT_SIGNING_DIRECTIVES = {
  TESTFLIGHT_HOSTED_WORKFLOW => Set[
    "CODE_SIGN_STYLE=Automatic",
  ],
  TESTFLIGHT_SELF_HOSTED_WORKFLOW => Set[
    "CODE_SIGN_STYLE=Automatic",
  ],
}.freeze
DEPRECATED_WORKFLOW_SECRETS = Set[
  "APPLE_KEY_ID",
  "APPLE_KEY_CONTENT",
].freeze
EDGE_TEST_SCRIPT_PATH = "./scripts/run-edge-function-tests.sh"
DENO_SETUP_USES_PATTERN = /\Adenoland\/setup-deno@/i
READINESS_ESCALATION_SCRIPT_PATH = "./scripts/run-readiness-escalation.sh"
READINESS_ESCALATION_REQUIRED_ENV_KEYS = Set[
  "READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES",
  "READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES",
].freeze

def option_requires_value?(token)
  return true if SHELL_OPTIONS_WITH_VALUE.include?(token)

  # Handles compact short-option bundles such as -euxo, where -o consumes the next token.
  token.match?(/\A-[^-]*o[^-]*\z/)
end

def sanitize_local_script_token(token)
  return nil unless token

  candidate = token.strip
  return nil if candidate.empty?

  candidate = candidate.sub(/[|&;]+$/, "")
  return nil unless candidate.start_with?("./")
  return nil if candidate.match?(DYNAMIC_TOKEN_PATTERN)

  candidate
end

def extract_shell_script_reference(tokens)
  index = 1
  skip_next = false

  while index < tokens.length
    token = tokens[index]

    if skip_next
      skip_next = false
      index += 1
      next
    end

    if token == "--"
      index += 1
      break
    end

    if token.start_with?("-")
      skip_next = option_requires_value?(token)
      index += 1
      next
    end

    return sanitize_local_script_token(token)
  end

  sanitize_local_script_token(tokens[index])
end

def extract_candidate_from_tokens(tokens)
  return nil if tokens.empty?

  while !tokens.empty? && tokens.first.match?(ENV_ASSIGNMENT_REGEX)
    tokens = tokens.drop(1)
  end
  return nil if tokens.empty?

  command = tokens.first
  if SHELL_COMMANDS.include?(command)
    return extract_shell_script_reference(tokens)
  end

  if SOURCE_COMMANDS.include?(command)
    return sanitize_local_script_token(tokens[1])
  end

  sanitize_local_script_token(command)
end

def extract_local_script_references(run_script)
  refs = []
  run_script.each_line do |line|
    stripped = line.strip
    next if stripped.empty?

    stripped
      .split(/\s*(?:\|\||&&|;|\|)\s*/)
      .each do |segment|
        next if segment.strip.empty?

        tokens = begin
          Shellwords.shellsplit(segment)
        rescue ArgumentError
          []
        end
        next if tokens.empty?

        candidate = extract_candidate_from_tokens(tokens)
        refs << candidate if candidate
      end
  end

  refs
end

def deno_truthy?(value)
  case value
  when true
    true
  when false, nil
    false
  else
    value.to_s.strip.downcase == "true"
  end
end

def run_enforces_deno?(run_script)
  run_script.match?(/(^|[[:space:]])REQUIRE_DENO[[:space:]]*=[[:space:]]*"?true"?([[:space:]]|$)/i)
end

def setup_deno_step?(step)
  return false unless step.is_a?(Hash)

  uses = step["uses"]
  uses.is_a?(String) && uses.strip.match?(DENO_SETUP_USES_PATTERN)
end

files = Dir.glob(".github/workflows/*.{yml,yaml}").sort
if files.empty?
  puts "No workflow files found."
  exit 0
end

missing_script_refs = Set.new
secret_contract_failures = []
bundle_contract_failures = []
signing_contract_failures = []
edge_runtime_contract_failures = []
readiness_escalation_contract_failures = []
workflow_bundle_ids = {}

files.each do |path|
  begin
    raw = File.read(path)
    Psych.parse_stream(raw)
    referenced_secrets = raw.scan(WORKFLOW_SECRET_PATTERN).flatten.map(&:upcase).to_set
    workflow_bundle_ids[path] = raw.scan(WORKFLOW_BUNDLE_ID_PATTERN).map(&:downcase).to_set

    required_secrets = REQUIRED_WORKFLOW_SECRETS[path]
    if required_secrets
      missing_required = required_secrets - referenced_secrets
      if missing_required.any?
        secret_contract_failures << "#{path}: missing required secret references -> #{missing_required.to_a.sort.join(", ")}"
      end
    end

    required_signing_directives = REQUIRED_TESTFLIGHT_SIGNING_DIRECTIVES[path]
    if required_signing_directives
      missing_directives = required_signing_directives.to_a.reject { |directive| raw.include?(directive) }
      if missing_directives.any?
        signing_contract_failures << "#{path}: missing required TestFlight signing directives -> #{missing_directives.sort.join(", ")}"
      end

      forbidden_signing_directives = FORBIDDEN_TESTFLIGHT_SIGNING_DIRECTIVES.fetch(path, Set.new)
      present_forbidden = forbidden_signing_directives.to_a.select { |directive| raw.include?(directive) }
      if present_forbidden.any?
        signing_contract_failures << "#{path}: forbidden TestFlight signing directives detected -> #{present_forbidden.sort.join(", ")}"
      end
    end

    deprecated_secrets = referenced_secrets & DEPRECATED_WORKFLOW_SECRETS
    if deprecated_secrets.any?
      secret_contract_failures << "#{path}: deprecated secret references detected -> #{deprecated_secrets.to_a.sort.join(", ")}"
    end

    workflow = Psych.safe_load(raw, aliases: true)
    jobs = workflow.is_a?(Hash) ? workflow["jobs"] : nil

    if jobs.is_a?(Hash)
      jobs.each do |job_name, job|
        next unless job.is_a?(Hash)
        steps = job["steps"]
        next unless steps.is_a?(Array)
        job_env = job["env"].is_a?(Hash) ? job["env"] : {}
        deno_setup_seen = false

        steps.each_with_index do |step, index|
          next unless step.is_a?(Hash)
          deno_setup_seen ||= setup_deno_step?(step)
          run = step["run"]
          next unless run.is_a?(String)

          references = extract_local_script_references(run)
          references.each do |candidate|
            resolved = File.expand_path(candidate, Dir.pwd)
            next if File.file?(resolved)

            step_name = step["name"] || "step_#{index + 1}"
            missing_script_refs << "#{path}: job=#{job_name}, step=#{step_name}, missing #{candidate}"
          end

          if references.include?(EDGE_TEST_SCRIPT_PATH)
            step_name = step["name"] || "step_#{index + 1}"
            step_env = step["env"].is_a?(Hash) ? step["env"] : {}
            require_deno_value = if step_env.key?("REQUIRE_DENO")
              step_env["REQUIRE_DENO"]
            else
              job_env["REQUIRE_DENO"]
            end
            require_deno_enabled = deno_truthy?(require_deno_value) || run_enforces_deno?(run)

            unless deno_setup_seen
              edge_runtime_contract_failures << "#{path}: job=#{job_name}, step=#{step_name}, edge test runtime contract requires denoland/setup-deno before #{EDGE_TEST_SCRIPT_PATH}"
            end

            unless require_deno_enabled
              edge_runtime_contract_failures << "#{path}: job=#{job_name}, step=#{step_name}, edge test runtime contract requires REQUIRE_DENO=true for #{EDGE_TEST_SCRIPT_PATH}"
            end
          end

          if references.include?(READINESS_ESCALATION_SCRIPT_PATH)
            step_name = step["name"] || "step_#{index + 1}"
            step_env = step["env"].is_a?(Hash) ? step["env"] : {}
            missing_escalation_keys = READINESS_ESCALATION_REQUIRED_ENV_KEYS.reject { |key| step_env.key?(key) }
            if missing_escalation_keys.any?
              readiness_escalation_contract_failures << "#{path}: job=#{job_name}, step=#{step_name}, readiness escalation contract requires env keys -> #{missing_escalation_keys.to_a.sort.join(", ")}"
            end
          end
        end
      end
    end

    puts "OK: #{path}"
  rescue Psych::SyntaxError => error
    warn "YAML parse failure in #{path}: line #{error.line}, column #{error.column}: #{error.problem}"
    exit 1
  end
end

hosted_bundle_ids = workflow_bundle_ids.fetch(TESTFLIGHT_HOSTED_WORKFLOW, Set.new)
self_hosted_bundle_ids = workflow_bundle_ids.fetch(TESTFLIGHT_SELF_HOSTED_WORKFLOW, Set.new)

if hosted_bundle_ids.empty?
  bundle_contract_failures << "#{TESTFLIGHT_HOSTED_WORKFLOW}: missing bundle identifier literal (expected PRODUCT_BUNDLE_IDENTIFIER seed)."
elsif hosted_bundle_ids.size > 1
  bundle_contract_failures << "#{TESTFLIGHT_HOSTED_WORKFLOW}: multiple bundle identifiers detected -> #{hosted_bundle_ids.to_a.sort.join(", ")}"
end

if self_hosted_bundle_ids.empty?
  bundle_contract_failures << "#{TESTFLIGHT_SELF_HOSTED_WORKFLOW}: missing bundle identifier literals."
elsif hosted_bundle_ids.size == 1
  expected_bundle_id = hosted_bundle_ids.first
  drifted_bundle_ids = self_hosted_bundle_ids - Set[expected_bundle_id]
  if drifted_bundle_ids.any?
    bundle_contract_failures << "#{TESTFLIGHT_SELF_HOSTED_WORKFLOW}: bundle identifier drift detected -> expected #{expected_bundle_id}, found #{self_hosted_bundle_ids.to_a.sort.join(", ")}"
  end
end

if missing_script_refs.any?
  warn "Workflow lint failed: missing local script references detected:"
  missing_script_refs.to_a.sort.each { |entry| warn "  - #{entry}" }
  exit 1
end

if secret_contract_failures.any?
  warn "Workflow lint failed: workflow secret contract drift detected:"
  secret_contract_failures.sort.each { |entry| warn "  - #{entry}" }
  warn "Required contracts: TestFlight upload secrets and generate-horoscope readiness/warm/prune workflow secrets."
  warn "Deprecated secrets must not be referenced: APPLE_KEY_ID, APPLE_KEY_CONTENT."
  exit 1
end

if bundle_contract_failures.any?
  warn "Workflow lint failed: TestFlight bundle identifier contract drift detected:"
  bundle_contract_failures.sort.each { |entry| warn "  - #{entry}" }
  warn "Required contract: both TestFlight workflows must resolve to one shared bundle identifier."
  exit 1
end

if signing_contract_failures.any?
  warn "Workflow lint failed: TestFlight signing contract drift detected:"
  signing_contract_failures.sort.each { |entry| warn "  - #{entry}" }
  warn "Required contract: both TestFlight workflows must use explicit manual signing with Apple Distribution and provisioning profile UUID."
  warn "Forbidden contract: CODE_SIGN_STYLE=Automatic must not appear in TestFlight workflows."
  exit 1
end

if edge_runtime_contract_failures.any?
  warn "Workflow lint failed: edge test runtime contract drift detected:"
  edge_runtime_contract_failures.sort.each { |entry| warn "  - #{entry}" }
  warn "Required contract: workflows running ./scripts/run-edge-function-tests.sh must setup Deno and enforce REQUIRE_DENO=true."
  exit 1
end

if readiness_escalation_contract_failures.any?
  warn "Workflow lint failed: readiness escalation contract drift detected:"
  readiness_escalation_contract_failures.sort.each { |entry| warn "  - #{entry}" }
  warn "Required contract: workflows running ./scripts/run-readiness-escalation.sh must pass READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES and READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES."
  exit 1
end
'
)

if [ "${skip_actionlint}" -eq 1 ]; then
  echo "Skipping actionlint checks (--skip-actionlint)."
  exit 0
fi

echo "Running actionlint semantic checks..."
(
  cd "${REPO_ROOT}"
  run_actionlint_with_fallbacks
)
