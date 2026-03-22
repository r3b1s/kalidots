#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="desktop-i3"
stage_description="Install i3 window manager with curated keybindings and directory shortcuts"
stage_profiles=("desktop")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

stage_apply() {
  load_or_prompt_target_user >/dev/null

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/desktop-policy.env"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/desktop-apt.txt"

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  # Deploy i3 config with resolved home path
  local tmp_config
  tmp_config="$(mktemp)"
  sed "s|__TARGET_HOME__|${target_home}|g" \
    "${BOOTSTRAP_ROOT}/files/desktop/i3/config" > "${tmp_config}"

  install_user_dir ".config/i3"
  install_user_file "${tmp_config}" ".config/i3/config"
  rm -f "${tmp_config}"
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  command -v i3 >/dev/null 2>&1 || { log_error "i3 not found in PATH"; return 1; }
  command -v rofi >/dev/null 2>&1 || { log_error "rofi not found in PATH"; return 1; }
  command -v alacritty >/dev/null 2>&1 || { log_error "alacritty not found in PATH"; return 1; }

  [[ -f "${target_home}/.config/i3/config" ]] || { log_error "i3 config not deployed"; return 1; }
  grep -q 'bindsym $mod+h focus left' "${target_home}/.config/i3/config" || { log_error "i3 config missing hjkl bindings"; return 1; }
  grep -q '__TARGET_HOME__' "${target_home}/.config/i3/config" && { log_error "i3 config still has unresolved placeholders"; return 1; }
}
