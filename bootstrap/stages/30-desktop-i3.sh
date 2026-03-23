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
  if command -v i3status-rs >/dev/null 2>&1; then
    sed -i 's|status_command i3status$|status_command i3status-rs|' "${tmp_config}"
  fi

  install_user_dir ".config/i3"
  install_user_file "${tmp_config}" ".config/i3/config"
  rm -f "${tmp_config}"

  install_user_dir ".config/picom"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/picom/picom-transparent.conf" \
    ".config/picom/picom-transparent.conf"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/picom/picom-opaque.conf" \
    ".config/picom/picom-opaque.conf"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/picom/picom-transparent.conf" \
    ".config/picom/picom.conf"

  # Deploy helper scripts
  install_user_dir ".config/i3/scripts"
  local script
  for script in "${BOOTSTRAP_ROOT}/files/desktop/i3/scripts/"*.sh; do
    [[ -f "${script}" ]] || continue
    install_user_file "${script}" ".config/i3/scripts/$(basename "${script}")" 755
  done

  # Build and install clipmenu from source (not in Kali repos)
  if ! command -v clipmenud >/dev/null 2>&1; then
    log_info "Building clipmenu from source"
    local clipmenu_build
    clipmenu_build="$(mktemp -d)"
    git clone --depth 1 https://github.com/cdown/clipmenu.git "${clipmenu_build}"
    make -C "${clipmenu_build}"
    make -C "${clipmenu_build}" install PREFIX=/usr/local
    rm -rf "${clipmenu_build}"
  fi

  # Enable VM guest agents for clipboard sharing and display auto-resize
  if command -v spice-vdagentd >/dev/null 2>&1; then
    systemctl enable spice-vdagentd 2>/dev/null || true
  fi
  if command -v qemu-ga >/dev/null 2>&1; then
    systemctl enable qemu-guest-agent 2>/dev/null || true
  fi

  # Flatpak setup for KeePassXC
  if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y --noninteractive flathub org.keepassxc.KeePassXC || log_warn "KeePassXC flatpak install failed — may need manual install"
  else
    log_warn "flatpak not available — skipping KeePassXC install"
  fi
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  command -v i3 >/dev/null 2>&1 || { log_error "i3 not found in PATH"; return 1; }
  command -v rofi >/dev/null 2>&1 || { log_error "rofi not found in PATH"; return 1; }
  command -v alacritty >/dev/null 2>&1 || { log_error "alacritty not found in PATH"; return 1; }
  command -v clipmenud >/dev/null 2>&1 || { log_error "clipmenud not found in PATH"; return 1; }

  [[ -f "${target_home}/.config/i3/config" ]] || { log_error "i3 config not deployed"; return 1; }
  [[ -d "${target_home}/.config/i3/scripts" ]] || { log_error "i3 scripts directory not deployed"; return 1; }
  [[ -f "${target_home}/.config/picom/picom.conf" ]] || { log_error "picom active config not deployed"; return 1; }
  [[ -f "${target_home}/.config/picom/picom-transparent.conf" ]] || { log_error "picom transparent profile not deployed"; return 1; }
  [[ -f "${target_home}/.config/picom/picom-opaque.conf" ]] || { log_error "picom opaque profile not deployed"; return 1; }
  grep -q 'bindsym $mod+h focus left' "${target_home}/.config/i3/config" || { log_error "i3 config missing hjkl bindings"; return 1; }
  grep -q 'toggle-transparency.sh' "${target_home}/.config/i3/config" || { log_error "i3 config missing transparency toggle binding"; return 1; }
  grep -q 'picom --config' "${target_home}/.config/i3/config" || { log_error "i3 config missing picom config startup"; return 1; }
  if command -v i3status-rs >/dev/null 2>&1; then
    grep -q 'status_command i3status-rs' "${target_home}/.config/i3/config" || { log_error "i3 config should use i3status-rs when available"; return 1; }
  fi
  grep -q '__TARGET_HOME__' "${target_home}/.config/i3/config" && { log_error "i3 config still has unresolved placeholders"; return 1; }

  # Verify key scripts are deployed and executable
  local required_scripts=(toggle-transparency.sh toggle-maximize.sh cycle-gaps.sh cycle-borders.sh scratchpad-launch.sh power-menu.sh screen-record.sh)
  for script in "${required_scripts[@]}"; do
    [[ -x "${target_home}/.config/i3/scripts/${script}" ]] || { log_error "Script not deployed or not executable: ${script}"; return 1; }
  done
}
