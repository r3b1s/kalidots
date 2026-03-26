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

prompt_enable_qemu_hyprland_resize_fix() {
  local stored_setting
  local answer=""

  stored_setting="$(state_get_value '.runtime.qemu_hyprland_screen_resize_fix // empty' 2>/dev/null || true)"
  if [[ -n "${stored_setting}" && "${stored_setting}" != "\"\"" ]]; then
    jq -r '.' <<<"${stored_setting}"
    return 0
  fi

  if [[ "${ASSUME_YES:-false}" == "true" ]]; then
    answer="false"
  elif command -v gum >/dev/null 2>&1; then
    if gum confirm "Enable qemu + hyprland screen resizing fix?"; then
      answer="true"
    else
      answer="false"
    fi
  else
    answer="$(prompt_with_fallback "Enable qemu + hyprland screen resizing fix? [y/N]" "y/N")"
    answer="$(trim_whitespace "${answer}")"
    case "${answer,,}" in
      y|yes|true)
        answer="true"
        ;;
      *)
        answer="false"
        ;;
    esac
  fi

  state_set_value '.runtime.qemu_hyprland_screen_resize_fix' "${answer}"
  printf '%s\n' "${answer}"
}

configure_qemu_hyprland_resize_fix() {
  local target_home="$1"
  local enabled="$2"
  local marker_dir="${target_home}/.config/kalidots"
  local marker_file="${marker_dir}/qemu-hyprland-screen-resize-fix.enabled"

  install -d -m 755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${marker_dir}"
  if [[ "${enabled}" == "true" ]]; then
    printf 'enabled\n' > "${marker_file}"
    chown "${TARGET_USER}:${TARGET_USER}" "${marker_file}"
    chmod 644 "${marker_file}"
  else
    rm -f "${marker_file}"
  fi
}

flatpak_app_installed() {
  local app_id="$1"

  flatpak info --columns=application "${app_id}" >/dev/null 2>&1
}

ensure_flatpak_app() {
  local remote_name="$1"
  local remote_url="$2"
  local app_id="$3"

  if flatpak_app_installed "${app_id}"; then
    log_info "Flatpak already installed: ${app_id}"
    return 0
  fi

  flatpak remote-add --if-not-exists "${remote_name}" "${remote_url}"
  flatpak install -y --noninteractive "${remote_name}" "${app_id}" || \
    log_warn "${app_id} flatpak install failed — may need manual install"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/desktop-policy.env"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/desktop-apt.txt"

  local target_home
  local qemu_hyprland_resize_fix_enabled
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  qemu_hyprland_resize_fix_enabled="$(prompt_enable_qemu_hyprland_resize_fix)"
  if [[ "${qemu_hyprland_resize_fix_enabled}" == "true" ]]; then
    ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/desktop-qemu-resize-fix-apt.txt"
  fi

  # Deploy i3 config with resolved home path
  local tmp_config
  tmp_config="$(mktemp)"
  sed "s|__TARGET_HOME__|${target_home}|g" \
    "${BOOTSTRAP_ROOT}/files/desktop/i3/config" > "${tmp_config}"

  install_user_dir ".config/i3"
  install_user_file "${tmp_config}" ".config/i3/config"
  rm -f "${tmp_config}"

  # Deploy helper scripts
  install_user_dir ".config/i3/scripts"
  local script
  for script in "${BOOTSTRAP_ROOT}/files/desktop/i3/scripts/"*.sh; do
    [[ -f "${script}" ]] || continue
    install_user_file "${script}" ".config/i3/scripts/$(basename "${script}")" 755
  done
  configure_qemu_hyprland_resize_fix "${target_home}" "${qemu_hyprland_resize_fix_enabled}"

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
    systemctl enable --now spice-vdagentd 2>/dev/null || true
  fi
  if command -v qemu-ga >/dev/null 2>&1; then
    systemctl enable --now qemu-guest-agent 2>/dev/null || true
  fi

  # Flatpak setup for KeePassXC
  if command -v flatpak >/dev/null 2>&1; then
    ensure_flatpak_app "flathub" "https://flathub.org/repo/flathub.flatpakrepo" "org.keepassxc.KeePassXC"
  else
    log_warn "flatpak not available — skipping KeePassXC install"
  fi
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  command -v i3 >/dev/null 2>&1 || { log_error "i3 not found in PATH"; return 1; }
  command -v autotiling >/dev/null 2>&1 || { log_error "autotiling not found in PATH"; return 1; }
  command -v rofi >/dev/null 2>&1 || { log_error "rofi not found in PATH"; return 1; }
  command -v alacritty >/dev/null 2>&1 || { log_error "alacritty not found in PATH"; return 1; }
  command -v clipmenud >/dev/null 2>&1 || { log_error "clipmenud not found in PATH"; return 1; }
  command -v xrandr >/dev/null 2>&1 || { log_error "xrandr not found in PATH"; return 1; }
  command -v xsettingsd >/dev/null 2>&1 || { log_error "xsettingsd not found in PATH"; return 1; }

  [[ -f "${target_home}/.config/i3/config" ]] || { log_error "i3 config not deployed"; return 1; }
  [[ -d "${target_home}/.config/i3/scripts" ]] || { log_error "i3 scripts directory not deployed"; return 1; }
  grep -q 'bindsym $mod+h focus left' "${target_home}/.config/i3/config" || { log_error "i3 config missing hjkl bindings"; return 1; }
  grep -q 'status_command $scripts/status-command.sh' "${target_home}/.config/i3/config" || { log_error "i3 config missing status wrapper"; return 1; }
  grep -q 'autotiling' "${target_home}/.config/i3/config" || { log_error "i3 config missing autotiling autostart"; return 1; }
  grep -q '__TARGET_HOME__' "${target_home}/.config/i3/config" && { log_error "i3 config still has unresolved placeholders"; return 1; }

  # Verify key scripts are deployed and executable
  local required_scripts=(status-command.sh toggle-maximize.sh cycle-gaps.sh cycle-borders.sh power-menu.sh screen-record.sh kali-menu.sh screenshot-menu.sh system-update.sh update-manager.sh workspace-auto-terminal.sh spice-display-init.sh display-hotplug-watch.sh theme-sync.sh)
  for script in "${required_scripts[@]}"; do
    [[ -x "${target_home}/.config/i3/scripts/${script}" ]] || { log_error "Script not deployed or not executable: ${script}"; return 1; }
  done

  local resize_fix_setting
  resize_fix_setting="$(state_get_value '.runtime.qemu_hyprland_screen_resize_fix // "false"' 2>/dev/null || true)"
  if [[ "${resize_fix_setting}" == "true" ]]; then
    [[ -f "${target_home}/.config/kalidots/qemu-hyprland-screen-resize-fix.enabled" ]] || {
      log_error "qemu + hyprland screen resizing fix marker not deployed"
      return 1
    }
  fi
}
