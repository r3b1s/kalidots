#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="tools-runtimes"
stage_description="Install language runtimes, language-level tools, and reference repositories"
stage_profiles=("tools")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

clone_or_sync_repo() {
  local url="$1"
  local dest="$2"
  local shallow="${3:-yes}"

  if [[ -d "${dest}/.git" ]]; then
    log_info "Repo already cloned at ${dest}; pulling"
    git config --global --add safe.directory "${dest}" 2>/dev/null || true
    git -C "${dest}" pull --ff-only || log_warn "pull failed for ${dest}; skipping"
  else
    log_info "Cloning ${url} -> ${dest}"
    install -d -m 0755 "$(dirname "${dest}")"
    if [[ "${shallow}" == "yes" ]]; then
      git clone --depth 1 "${url}" "${dest}"
    else
      git clone "${url}" "${dest}"
    fi
  fi
}

ensure_gum_or_prompt_fallback() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$(state_get_value '.runtime.target_user // empty')" != "" ]]; then
    return 0
  fi

  if [[ -n "${TARGET_USER:-}" ]]; then
    return 0
  fi

  if ! command -v gum >/dev/null 2>&1; then
    log_info "gum unavailable; continuing with shell prompt fallback from users.sh"
  fi
}

run_in_target_home() {
  local target_home="$1"
  shift

  runuser -u "${TARGET_USER}" -- env HOME="${target_home}" "$@"
}

ensure_stable_rust_toolchain() {
  local target_home="$1"
  local user_tool_path="$2"
  local cargo_home="${target_home}/.cargo"
  local rustup_home="${target_home}/.rustup"

  command -v rustup >/dev/null 2>&1 || return 0

  if run_in_target_home "${target_home}" env PATH="${user_tool_path}" \
    CARGO_HOME="${cargo_home}" RUSTUP_HOME="${rustup_home}" \
    bash -c 'cd "$HOME" && rustup toolchain list 2>/dev/null | grep -q "^stable"'; then
    return 0
  fi

  log_info "Installing stable Rust toolchain for ${TARGET_USER}"
  if ! run_in_target_home "${target_home}" env PATH="${user_tool_path}" \
    CARGO_HOME="${cargo_home}" RUSTUP_HOME="${rustup_home}" \
    bash -c 'cd "$HOME" && rustup set profile minimal && rustup toolchain install stable --profile minimal'; then
    log_warn "Stable Rust toolchain install failed; cleaning partial state and retrying once"
    run_in_target_home "${target_home}" env PATH="${user_tool_path}" \
      CARGO_HOME="${cargo_home}" RUSTUP_HOME="${rustup_home}" \
      bash -c 'cd "$HOME" && rustup toolchain uninstall stable >/dev/null 2>&1 || true'
    run_in_target_home "${target_home}" env PATH="${user_tool_path}" \
      CARGO_HOME="${cargo_home}" RUSTUP_HOME="${rustup_home}" \
      bash -c 'cd "$HOME" && rustup set profile minimal && rustup toolchain install stable --profile minimal'
  fi

  run_in_target_home "${target_home}" env PATH="${user_tool_path}" \
    CARGO_HOME="${cargo_home}" RUSTUP_HOME="${rustup_home}" \
    bash -c 'cd "$HOME" && rustup default stable'
}

stage_apply() {
  ensure_gum_or_prompt_fallback
  load_or_prompt_target_user >/dev/null

  local target_home
  local user_tool_path
  local repos_file
  local line
  local url
  local dest
  local shallow

  local user_gopath

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/tools-policy.env"
  load_package_policy

  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  user_gopath="${target_home}/.local/share/go"

  install_user_dir ".bashrc.d"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc.d/51-golang.sh" ".bashrc.d/51-golang.sh"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc.d/52-cargo.sh" ".bashrc.d/52-cargo.sh"
  install_user_dir ".local"
  install_user_dir ".local/share"
  install_user_dir ".local/share/go"

  user_tool_path="${target_home}/.local/share/mise/shims:${target_home}/.local/bin:${user_gopath}/bin:${target_home}/.cargo/bin:/usr/local/go/bin:${PATH}"

  ensure_stable_rust_toolchain "${target_home}" "${user_tool_path}"

  if command -v gum >/dev/null 2>&1; then
    log_info "gum already available: $(gum --version)"
  else
    log_info "gum unavailable; downstream commands will use shell prompt fallback where supported"
  fi

  if command -v go >/dev/null 2>&1 || run_in_target_home "${target_home}" env PATH="${user_tool_path}" bash -c 'cd "$HOME" && command -v go' >/dev/null 2>&1; then
    log_info "Installing Go tools for ${TARGET_USER}"
    run_in_target_home "${target_home}" env PATH="${user_tool_path}" GOPATH="${user_gopath}" bash -c 'cd "$HOME" && go install golang.org/x/tools/gopls@latest'
  fi

  if run_in_target_home "${target_home}" env PATH="${user_tool_path}" MISE_USE_VERSIONS_HOST=0 bash -c 'command -v python' >/dev/null 2>&1; then
    log_info "Installing pipx via mise-managed pip for ${TARGET_USER}"
    run_in_target_home "${target_home}" env PATH="${user_tool_path}" MISE_USE_VERSIONS_HOST=0 \
      bash -c 'cd "$HOME" && python -m pip install --user pipx' || log_warn "pipx pip install failed; may already be installed"
    run_in_target_home "${target_home}" env PATH="${user_tool_path}" MISE_USE_VERSIONS_HOST=0 \
      bash -c 'cd "$HOME" && python -m pipx ensurepath' || log_info "pipx PATH already configured for ${TARGET_USER}"
  fi

  repos_file="${BOOTSTRAP_ROOT}/files/tools/repos.txt"
  if [[ -f "${repos_file}" ]]; then
    while IFS='|' read -r url dest shallow || [[ -n "${url}" ]]; do
      url="${url#"${url%%[![:space:]]*}"}"
      url="${url%"${url##*[![:space:]]}"}"
      dest="${dest#"${dest%%[![:space:]]*}"}"
      dest="${dest%"${dest##*[![:space:]]}"}"
      shallow="${shallow#"${shallow%%[![:space:]]*}"}"
      shallow="${shallow%"${shallow##*[![:space:]]}"}"
      [[ -n "${url}" && "${url}" != \#* ]] || continue
      clone_or_sync_repo "${url}" "${dest}" "${shallow}"
      chown -R "${TARGET_USER}:${TARGET_USER}" "${dest}"
    done <"${repos_file}"
  fi
}

stage_verify() {
  ensure_gum_or_prompt_fallback
  load_or_prompt_target_user >/dev/null

  local target_home
  local user_tool_path
  local user_gopath

  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  user_gopath="${target_home}/.local/share/go"
  user_tool_path="${target_home}/.local/share/mise/shims:${target_home}/.local/bin:${user_gopath}/bin:${target_home}/.cargo/bin:/usr/local/go/bin:${PATH}"

  [[ -f "${target_home}/.bashrc.d/51-golang.sh" ]] || { log_error "Go PATH drop-in not deployed"; return 1; }
  [[ -f "${target_home}/.bashrc.d/52-cargo.sh" ]] || { log_error "Cargo PATH drop-in not deployed"; return 1; }
  run_in_target_home "${target_home}" env PATH="${user_tool_path}" bash -c 'cd "$HOME" && command -v cargo' >/dev/null 2>&1 || { log_error "cargo not available for target user"; return 1; }
  command -v gum >/dev/null 2>&1 || { log_error "gum not available"; return 1; }
  run_in_target_home "${target_home}" env PATH="${user_tool_path}" GOPATH="${user_gopath}" bash -c 'cd "$HOME" && command -v gopls' >/dev/null 2>&1 || { log_error "gopls not available for target user"; return 1; }
  [[ -d "/opt/tools/PayloadsAllTheThings/.git" ]] || { log_error "PayloadsAllTheThings not cloned"; return 1; }

  log_info "tools-runtimes stage verified"
  return 0
}
