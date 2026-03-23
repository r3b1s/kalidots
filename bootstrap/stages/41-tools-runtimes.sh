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
  local bootstrap_home="/root"
  local bootstrap_gopath="${bootstrap_home}/.local/share/go"
  local bootstrap_path="${bootstrap_gopath}/bin:/usr/local/go/bin:${PATH}"

  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$(state_get_value '.runtime.target_user // empty')" != "" ]]; then
    return 0
  fi

  if [[ -n "${TARGET_USER:-}" ]]; then
    return 0
  fi

  if command -v go >/dev/null 2>&1; then
    log_info "gum not found before target-user prompt; installing fallback copy via go install"
    install -d -m 0755 "${bootstrap_gopath}"
    env PATH="${bootstrap_path}" GOPATH="${bootstrap_gopath}" HOME="${bootstrap_home}" bash -lc 'go install github.com/charmbracelet/gum@latest'
    export PATH="${bootstrap_gopath}/bin:${PATH}"
  fi

  if ! command -v gum >/dev/null 2>&1; then
    log_info "gum unavailable; continuing with shell prompt fallback from users.sh"
  fi
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

  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  user_gopath="${target_home}/.local/share/go"

  install_user_dir ".bashrc.d"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc.d/51-golang.sh" ".bashrc.d/51-golang.sh"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc.d/52-cargo.sh" ".bashrc.d/52-cargo.sh"
  install_user_dir ".local"
  install_user_dir ".local/share"
  install_user_dir ".local/share/go"

  user_tool_path="${target_home}/.local/bin:${user_gopath}/bin:${target_home}/.cargo/bin:/usr/local/go/bin:${PATH}"

  if command -v rustup >/dev/null 2>&1; then
    if ! runuser -u "${TARGET_USER}" -- rustup toolchain list 2>/dev/null | grep -q stable; then
      log_info "Installing stable Rust toolchain for ${TARGET_USER}"
      runuser -u "${TARGET_USER}" -- rustup default stable
    fi
  fi

  if ! command -v gum >/dev/null 2>&1; then
    log_info "gum not found after target-user resolution; installing via go install for downstream interactive commands"
    runuser -u "${TARGET_USER}" -- env PATH="${user_tool_path}" GOPATH="${user_gopath}" HOME="${target_home}" bash -lc 'go install github.com/charmbracelet/gum@latest'
  else
    log_info "gum already available: $(gum --version)"
  fi

  if command -v go >/dev/null 2>&1 || runuser -u "${TARGET_USER}" -- env PATH="${user_tool_path}" bash -c 'command -v go' >/dev/null 2>&1; then
    log_info "Installing Go tools for ${TARGET_USER}"
    runuser -u "${TARGET_USER}" -- env PATH="${user_tool_path}" GOPATH="${user_gopath}" HOME="${target_home}" bash -c 'go install golang.org/x/tools/gopls@latest'
  fi

  if command -v pipx >/dev/null 2>&1; then
    log_info "Installing Python tools via pipx for ${TARGET_USER}"
    runuser -u "${TARGET_USER}" -- pipx install pwntools || log_warn "pwntools pipx install failed; may already be installed"
    runuser -u "${TARGET_USER}" -- pipx ensurepath
  fi

  if command -v gem >/dev/null 2>&1; then
    if ! gem list -i bundler >/dev/null 2>&1; then
      log_info "Installing bundler gem"
      gem install bundler --no-document
    fi
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
  user_tool_path="${target_home}/.local/bin:${user_gopath}/bin:${target_home}/.cargo/bin:/usr/local/go/bin:${PATH}"

  [[ -f "${target_home}/.bashrc.d/51-golang.sh" ]] || { log_error "Go PATH drop-in not deployed"; return 1; }
  [[ -f "${target_home}/.bashrc.d/52-cargo.sh" ]] || { log_error "Cargo PATH drop-in not deployed"; return 1; }
  runuser -u "${TARGET_USER}" -- env PATH="${user_tool_path}" HOME="${target_home}" bash -c 'command -v cargo' >/dev/null 2>&1 || { log_error "cargo not available for target user"; return 1; }
  command -v gum >/dev/null 2>&1 || { log_error "gum not available"; return 1; }
  runuser -u "${TARGET_USER}" -- env PATH="${user_tool_path}" GOPATH="${user_gopath}" HOME="${target_home}" bash -c 'command -v gopls' >/dev/null 2>&1 || { log_error "gopls not available for target user"; return 1; }
  runuser -u "${TARGET_USER}" -- env PATH="${user_tool_path}" HOME="${target_home}" bash -c 'command -v pwn' >/dev/null 2>&1 || { log_error "pwntools entrypoint not available for target user"; return 1; }
  [[ -d "/opt/tools/PayloadsAllTheThings/.git" ]] || { log_error "PayloadsAllTheThings not cloned"; return 1; }

  log_info "tools-runtimes stage verified"
  return 0
}
