#!/usr/bin/env bash

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/log.sh"

readonly LLM_TOOL_MANIFEST="${BOOTSTRAP_ROOT}/files/llm/llm-tools.txt"

declare -g -a LLM_TOOL_NAMES=()
declare -g -A LLM_TOOL_METHODS=()
declare -g -A LLM_TOOL_PACKAGES=()
declare -g -A LLM_TOOL_BINARIES=()
declare -g -A LLM_TOOL_VM_AUTH=()
declare -g -A LLM_TOOL_PROXY_AUTH=()
declare -g -A LLM_TOOL_CREDENTIAL_PATHS=()

trim_llm_field() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

load_llm_tool_manifest() {
  local line_number=0
  local tool
  local method
  local package_or_url
  local binary
  local vm_local_auth
  local proxy_auth
  local credential_path
  local expected_header="tool|method|package_or_url|binary|vm_local_auth|proxy_auth|credential_path"

  if [[ ! -f "${LLM_TOOL_MANIFEST}" ]]; then
    log_error "LLM tool manifest not found: ${LLM_TOOL_MANIFEST}"
    return 1
  fi

  LLM_TOOL_NAMES=()
  LLM_TOOL_METHODS=()
  LLM_TOOL_PACKAGES=()
  LLM_TOOL_BINARIES=()
  LLM_TOOL_VM_AUTH=()
  LLM_TOOL_PROXY_AUTH=()
  LLM_TOOL_CREDENTIAL_PATHS=()

  while IFS='|' read -r tool method package_or_url binary vm_local_auth proxy_auth credential_path || [[ -n "${tool}" ]]; do
    line_number=$((line_number + 1))
    tool="$(trim_llm_field "${tool}")"

    if [[ ${line_number} -eq 1 ]]; then
      local header="${tool}|$(trim_llm_field "${method}")|$(trim_llm_field "${package_or_url}")|$(trim_llm_field "${binary}")|$(trim_llm_field "${vm_local_auth}")|$(trim_llm_field "${proxy_auth}")|$(trim_llm_field "${credential_path}")"
      if [[ "${header}" != "${expected_header}" ]]; then
        log_error "Unexpected LLM manifest header: ${header}"
        return 1
      fi
      continue
    fi

    [[ -n "${tool}" ]] || continue
    [[ "${tool}" == \#* ]] && continue

    method="$(trim_llm_field "${method}")"
    package_or_url="$(trim_llm_field "${package_or_url}")"
    binary="$(trim_llm_field "${binary}")"
    vm_local_auth="$(trim_llm_field "${vm_local_auth}")"
    proxy_auth="$(trim_llm_field "${proxy_auth}")"
    credential_path="$(trim_llm_field "${credential_path}")"

    LLM_TOOL_NAMES+=("${tool}")
    LLM_TOOL_METHODS["${tool}"]="${method}"
    LLM_TOOL_PACKAGES["${tool}"]="${package_or_url}"
    LLM_TOOL_BINARIES["${tool}"]="${binary}"
    LLM_TOOL_VM_AUTH["${tool}"]="${vm_local_auth}"
    LLM_TOOL_PROXY_AUTH["${tool}"]="${proxy_auth}"
    LLM_TOOL_CREDENTIAL_PATHS["${tool}"]="${credential_path}"
  done <"${LLM_TOOL_MANIFEST}"

  if [[ "${#LLM_TOOL_NAMES[@]}" -ne 3 ]]; then
    log_error "Expected 3 LLM tools in manifest; found ${#LLM_TOOL_NAMES[@]}"
    return 1
  fi

  llm_assert_manifest_contract
}

llm_assert_manifest_contract() {
  local tool

  for tool in codex claude gemini; do
    if [[ -z "${LLM_TOOL_METHODS[${tool}]:-}" ]]; then
      log_error "LLM manifest missing tool definition for ${tool}"
      return 1
    fi

    if [[ "${LLM_TOOL_METHODS[${tool}]}" != "manual" ]]; then
      log_error "LLM manifest for ${tool} must remain manual"
      return 1
    fi

    if [[ "${LLM_TOOL_PACKAGES[${tool}]}" != "not-installed-by-bootstrap" ]]; then
      log_error "LLM manifest for ${tool} must document no bootstrap install"
      return 1
    fi
  done

  if [[ "${LLM_TOOL_PROXY_AUTH[codex]:-}" != *"requires_openai_auth = true"* ]]; then
    log_error "Codex manifest must preserve OpenAI auth for proxy usage"
    return 1
  fi

  if [[ "${LLM_TOOL_PROXY_AUTH[claude]:-}" != *"ANTHROPIC_AUTH_TOKEN"* ]]; then
    log_error "Claude manifest must document ANTHROPIC_AUTH_TOKEN for proxy usage"
    return 1
  fi

  if [[ "${LLM_TOOL_PROXY_AUTH[gemini]:-}" != *"vertex"* ]]; then
    log_error "Gemini manifest must document Vertex or proxy usage"
    return 1
  fi
}

deploy_llm_auth_artifacts() {
  local target_home="$1"

  if [[ -z "${TARGET_USER:-}" ]]; then
    log_error "TARGET_USER must be set before deploying LLM auth artifacts"
    return 1
  fi

  if [[ -z "${target_home}" ]]; then
    log_error "Target home is required for LLM auth artifact deployment"
    return 1
  fi

  install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${target_home}/.local/share/kali-bootstrap"
  install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${target_home}/.config/kali-bootstrap/llm"
  install -d -m 0700 -o "${TARGET_USER}" -g "${TARGET_USER}" "${target_home}/.codex"

  install -m 0644 -o "${TARGET_USER}" -g "${TARGET_USER}" \
    "${BOOTSTRAP_ROOT}/files/llm/auth-expectations.md" \
    "${target_home}/.local/share/kali-bootstrap/llm-auth-expectations.md"
  install -m 0600 -o "${TARGET_USER}" -g "${TARGET_USER}" \
    "${BOOTSTRAP_ROOT}/files/llm/codex-config.toml" \
    "${target_home}/.codex/config.toml"
  install -m 0644 -o "${TARGET_USER}" -g "${TARGET_USER}" \
    "${BOOTSTRAP_ROOT}/files/llm/claude.env.example" \
    "${target_home}/.config/kali-bootstrap/llm/claude.env.example"
  install -m 0644 -o "${TARGET_USER}" -g "${TARGET_USER}" \
    "${BOOTSTRAP_ROOT}/files/llm/gemini.env.example" \
    "${target_home}/.config/kali-bootstrap/llm/gemini.env.example"
}
