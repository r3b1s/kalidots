#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="ctf-htbtoolkit"
stage_description="Build and install htb-toolkit from source"
stage_profiles=("ctf")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

CTF_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/ctf-policy.env"
HTB_TOOLKIT_REPO_URL="https://github.com/D3vil0p3r/htb-toolkit.git"
HTB_TOOLKIT_REPO_DIR="/opt/ctf/htb-toolkit"
HTB_TOOLKIT_BINARY="/usr/local/bin/htb-toolkit"

ctf_policy_allows_external() {
  local exception_name="$1"

  PACKAGE_POLICY_FILE="${CTF_POLICY_FILE}"
  load_package_policy

  if [[ "${PACKAGE_POLICY_ALLOW_EXTERNAL:-}" != "1" ]]; then
    log_error "CTF policy forbids external source installs."
    return 1
  fi

  if [[ ",${PACKAGE_POLICY_EXTERNAL_EXCEPTIONS:-}," != *",${exception_name},"* ]]; then
    log_error "CTF policy must allow external exception ${exception_name}."
    return 1
  fi
}

clone_or_sync_htb_toolkit_repo() {
  if [[ -d "${HTB_TOOLKIT_REPO_DIR}/.git" ]]; then
    log_info "htb-toolkit repo already present at ${HTB_TOOLKIT_REPO_DIR}; pulling latest changes"
    git config --global --add safe.directory "${HTB_TOOLKIT_REPO_DIR}" 2>/dev/null || true
    git -C "${HTB_TOOLKIT_REPO_DIR}" pull --ff-only
    return 0
  fi

  log_info "Cloning htb-toolkit into ${HTB_TOOLKIT_REPO_DIR}"
  install -d -m 0755 "$(dirname "${HTB_TOOLKIT_REPO_DIR}")"
  git clone --depth 1 "${HTB_TOOLKIT_REPO_URL}" "${HTB_TOOLKIT_REPO_DIR}"
}

build_htb_toolkit() {
  local target_home="$1"

  chown -R "${TARGET_USER}:${TARGET_USER}" "${HTB_TOOLKIT_REPO_DIR}"
  runuser -u "${TARGET_USER}" -- env \
    HOME="${target_home}" \
    CARGO_HOME="${target_home}/.cargo" \
    PATH="/usr/local/bin:/usr/bin:/bin:${target_home}/.cargo/bin" \
    cargo build --manifest-path "${HTB_TOOLKIT_REPO_DIR}/Cargo.toml" --release --locked
}

install_htb_toolkit_binary() {
  install -m 0755 "${HTB_TOOLKIT_REPO_DIR}/target/release/htb-toolkit" "${HTB_TOOLKIT_BINARY}"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null
  ctf_policy_allows_external "htb-toolkit"

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/ctf-apt.txt"
  clone_or_sync_htb_toolkit_repo
  build_htb_toolkit "${target_home}"
  install_htb_toolkit_binary
}

stage_verify() {
  [[ -x "${HTB_TOOLKIT_BINARY}" ]] || { log_error "htb-toolkit binary not installed at ${HTB_TOOLKIT_BINARY}"; return 1; }
  [[ -d "${HTB_TOOLKIT_REPO_DIR}/.git" ]] || { log_error "htb-toolkit repo not present at ${HTB_TOOLKIT_REPO_DIR}"; return 1; }
  command -v htb-toolkit >/dev/null 2>&1 || { log_error "htb-toolkit not available in PATH"; return 1; }
  command -v cargo >/dev/null 2>&1 || { log_error "cargo not available"; return 1; }
  command -v openvpn >/dev/null 2>&1 || { log_error "openvpn not available"; return 1; }
}
