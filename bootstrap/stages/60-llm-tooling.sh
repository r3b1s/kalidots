#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="llm-tooling"
stage_description="Deploy mixed-auth setup artifacts and documentation for coding agents"
stage_profiles=("llm")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/llm.sh"

LLM_POLICY_FILE="${BOOTSTRAP_ROOT}/files/llm/llm-policy.env"

stage_apply() {
  local target_home

  PACKAGE_POLICY_FILE="${LLM_POLICY_FILE}"
  load_package_policy
  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/llm-apt.txt"

  load_or_prompt_target_user >/dev/null
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  load_llm_tool_manifest
  # Do not run any coding-agent installer, npm install, native installer script, or package-manager install here.
  deploy_llm_auth_artifacts "${target_home}"
}

stage_verify() {
  local target_home
  local doc_path
  local codex_path
  local claude_env_path
  local gemini_env_path

  load_or_prompt_target_user >/dev/null
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  load_llm_tool_manifest
  llm_assert_manifest_contract

  doc_path="${target_home}/.local/share/kali-bootstrap/llm-auth-expectations.md"
  codex_path="${target_home}/.codex/config.toml"
  claude_env_path="${target_home}/.config/kali-bootstrap/llm/claude.env.example"
  gemini_env_path="${target_home}/.config/kali-bootstrap/llm/gemini.env.example"

  test -f "${doc_path}" || { log_error "LLM auth expectations doc not deployed"; return 1; }
  test -f "${codex_path}" || { log_error "Codex config template not deployed"; return 1; }
  test -f "${claude_env_path}" || { log_error "Claude env template not deployed"; return 1; }
  test -f "${gemini_env_path}" || { log_error "Gemini env template not deployed"; return 1; }

  [[ "$(stat -c %U "${doc_path}")" == "${TARGET_USER}" ]] || { log_error "LLM auth doc is not owned by ${TARGET_USER}"; return 1; }
  [[ "$(stat -c %U "${codex_path}")" == "${TARGET_USER}" ]] || { log_error "Codex config is not owned by ${TARGET_USER}"; return 1; }
  [[ "$(stat -c %U "${claude_env_path}")" == "${TARGET_USER}" ]] || { log_error "Claude env template is not owned by ${TARGET_USER}"; return 1; }
  [[ "$(stat -c %U "${gemini_env_path}")" == "${TARGET_USER}" ]] || { log_error "Gemini env template is not owned by ${TARGET_USER}"; return 1; }
  [[ "$(stat -c %a "${codex_path}")" == "600" ]] || { log_error "Codex config must be mode 600"; return 1; }

  grep -q 'requires_openai_auth = true' "${codex_path}" || { log_error "Codex config missing requires_openai_auth"; return 1; }
  grep -q 'manual for now' "${doc_path}" || { log_error "LLM auth doc must say installation is manual for now"; return 1; }
  grep -q 'ANTHROPIC_AUTH_TOKEN' "${claude_env_path}" || { log_error "Claude env template missing ANTHROPIC_AUTH_TOKEN"; return 1; }
  grep -q 'GOOGLE_GENAI_USE_VERTEXAI' "${gemini_env_path}" || { log_error "Gemini env template missing Vertex toggle"; return 1; }

  # Do not store tokens, browser session files, or auth selections in .bootstrap/state.json.
  log_info "llm-tooling stage verified"
  return 0
}
