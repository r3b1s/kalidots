#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="desktop-apps"
stage_description="Configure Rofi, Alacritty, shell ergonomics, Starship prompt, and status bar"
stage_profiles=("desktop")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

configure_operator_home_dirs() {
  local target_home="$1"
  local tmp_file
  local dir
  local -a operator_dirs=(
    "downloads"
    "engagements"
    "loot"
    "payloads"
    "reports"
    "notes"
    "screenshots"
    "recordings"
    ".local/share/go"
  )
  local -a legacy_dirs=(
    "Desktop"
    "Documents"
    "Downloads"
    "Music"
    "Pictures"
    "Public"
    "Templates"
    "Videos"
  )

  for dir in "${operator_dirs[@]}"; do
    install_user_dir "${dir}"
  done

  tmp_file="$(mktemp)"
  cat > "${tmp_file}" <<'EOF'
XDG_DESKTOP_DIR="$HOME/engagements"
XDG_DOWNLOAD_DIR="$HOME/downloads"
XDG_TEMPLATES_DIR="$HOME"
XDG_PUBLICSHARE_DIR="$HOME"
XDG_DOCUMENTS_DIR="$HOME/notes"
XDG_MUSIC_DIR="$HOME"
XDG_PICTURES_DIR="$HOME/screenshots"
XDG_VIDEOS_DIR="$HOME/recordings"
EOF
  install_user_dir ".config"
  install_user_file "${tmp_file}" ".config/user-dirs.dirs"
  rm -f "${tmp_file}"

  for dir in "${legacy_dirs[@]}"; do
    rmdir "${target_home}/${dir}" 2>/dev/null || true
  done
}

ensure_firefox_operator_profile() {
  local target_home="$1"
  local firefox_root="${target_home}/.mozilla/firefox"
  local profiles_ini="${firefox_root}/profiles.ini"
  local tmp_file
  local next_index

  install_user_dir ".mozilla"
  install_user_dir ".mozilla/firefox"
  install_user_dir ".mozilla/firefox/operator"

  if [[ ! -f "${profiles_ini}" ]]; then
    tmp_file="$(mktemp)"
    cat > "${tmp_file}" <<'EOF'
[General]
StartWithLastProfile=1
Version=2
EOF
    install_user_file "${tmp_file}" ".mozilla/firefox/profiles.ini"
    rm -f "${tmp_file}"
  fi

  if grep -q '^Name=operator$' "${profiles_ini}" 2>/dev/null; then
    return 0
  fi

  next_index="$(
    awk -F'[][]' '
      /^\[Profile[0-9]+\]$/ {
        gsub(/^Profile/, "", $2)
        if ($2 + 1 > max) {
          max = $2 + 1
        }
      }
      END { print max + 0 }
    ' "${profiles_ini}"
  )"

  cat >> "${profiles_ini}" <<EOF

[Profile${next_index}]
Name=operator
IsRelative=1
Path=operator
Default=0
EOF
  chown "${TARGET_USER}:${TARGET_USER}" "${profiles_ini}"
}

install_firefox_policy() {
  install -d -m 755 /etc/firefox/policies
  install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/firefox/policies.json" /etc/firefox/policies/policies.json

  if [[ -d /usr/lib/firefox-esr ]]; then
    install -d -m 755 /usr/lib/firefox-esr/distribution
    install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/firefox/policies.json" /usr/lib/firefox-esr/distribution/policies.json
  fi

  if [[ -d /usr/lib/firefox ]]; then
    install -d -m 755 /usr/lib/firefox/distribution
    install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/firefox/policies.json" /usr/lib/firefox/distribution/policies.json
  fi
}

install_i3status_rs() {
  if command -v i3status-rs >/dev/null 2>&1; then
    log_info "i3status-rs already installed"
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    log_warn "cargo not available — skipping i3status-rs build (install tools profile for Rust toolchain)"
    return 0
  fi

  # Ensure a default toolchain is set (rustup may be installed without one)
  if command -v rustup >/dev/null 2>&1 && ! rustup toolchain list 2>/dev/null | grep -q default; then
    log_info "Setting up stable Rust toolchain for i3status-rs build"
    rustup default stable
  fi

  log_info "Building i3status-rs from source"
  local build_dir
  build_dir="$(mktemp -d)"
  git clone --depth 1 https://github.com/greshake/i3status-rust.git "${build_dir}"
  cargo install --path "${build_dir}" --locked --root /usr/local
  # Deploy icons and themes to system share
  if [[ -d "${build_dir}/files" ]]; then
    install -d /usr/local/share/i3status-rust
    cp -r "${build_dir}/files/"* /usr/local/share/i3status-rust/
  fi
  rm -rf "${build_dir}"
}

install_nerd_font() {
  local font_dir="/usr/local/share/fonts/NerdFonts"
  if [[ -d "${font_dir}" ]] && ls "${font_dir}"/*.ttf >/dev/null 2>&1; then
    log_info "JetBrainsMono Nerd Font already installed"
    return 0
  fi

  log_info "Installing JetBrainsMono Nerd Font"
  local tmp_zip
  tmp_zip="$(mktemp)"
  if ! curl -fSL -o "${tmp_zip}" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"; then
    log_warn "Failed to download Nerd Font — terminal may render poorly"
    rm -f "${tmp_zip}"
    return 0
  fi
  install -d "${font_dir}"
  tar -xf "${tmp_zip}" -C "${font_dir}"
  rm -f "${tmp_zip}"
  fc-cache -f "${font_dir}"
}

install_starship() {
  if command -v starship >/dev/null 2>&1; then
    log_info "Starship already installed: $(starship --version | head -1)"
    return 0
  fi

  log_info "Installing Starship via install.sh (external exception: not in kali-rolling)"
  curl -sS https://starship.rs/install.sh | sh -s -- --yes
}

upgrade_i3_bar_config() {
  local target_home="$1"
  local i3_config="${target_home}/.config/i3/config"

  [[ -f "${i3_config}" ]] || return 0

  if command -v i3status-rs >/dev/null 2>&1; then
    log_info "i3status-rs found; upgrading bar config"
    sed -i 's|status_command i3status$|status_command i3status-rs|' "${i3_config}"
  else
    log_info "i3status-rs not found; keeping i3status fallback"
  fi
}

ensure_user_shell_startup_chain() {
  local target_home="$1"
  local bashrc="${target_home}/.bashrc"
  local bash_profile="${target_home}/.bash_profile"
  local profile="${target_home}/.profile"
  local drop_in_marker="# Source bashrc.d drop-ins"
  local bashrc_source_marker="# Source .bashrc for interactive shells"

  if ! grep -qF "${drop_in_marker}" "${bashrc}" 2>/dev/null; then
    cat >> "${bashrc}" <<'BASHRC_DROPIN'

# Source bashrc.d drop-ins
if [[ -d "${HOME}/.bashrc.d" ]]; then
  for _dropin in "${HOME}/.bashrc.d"/*.sh; do
    [[ -r "${_dropin}" ]] && source "${_dropin}"
  done
  unset _dropin
fi
BASHRC_DROPIN
    chown "${TARGET_USER}:${TARGET_USER}" "${bashrc}"
  fi

  if ! grep -qF "${bashrc_source_marker}" "${bash_profile}" 2>/dev/null; then
    cat >> "${bash_profile}" <<'BASH_PROFILE_DROPIN'

# Source .bashrc for interactive shells
if [[ -f "${HOME}/.bashrc" ]]; then
  source "${HOME}/.bashrc"
fi
BASH_PROFILE_DROPIN
    chown "${TARGET_USER}:${TARGET_USER}" "${bash_profile}"
  fi

  if ! grep -qF "${bashrc_source_marker}" "${profile}" 2>/dev/null; then
    cat >> "${profile}" <<'PROFILE_DROPIN'

# Source .bashrc for interactive shells
if [ -n "${BASH_VERSION:-}" ] && [ -f "${HOME}/.bashrc" ]; then
  . "${HOME}/.bashrc"
fi
PROFILE_DROPIN
    chown "${TARGET_USER}:${TARGET_USER}" "${profile}"
  fi
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  # Deploy Rofi config
  install_user_dir ".config/rofi"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/rofi/config.rasi" ".config/rofi/config.rasi"

  configure_operator_home_dirs "${target_home}"
  ensure_firefox_operator_profile "${target_home}"
  install_firefox_policy

  # Install Nerd Font for Alacritty
  install_nerd_font

  # Deploy Alacritty config
  install_user_dir ".config/alacritty"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/alacritty/alacritty.toml" ".config/alacritty/alacritty.toml"

  # Deploy shell ergonomics
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/inputrc" ".inputrc"

  # Deploy bashrc drop-in
  install_user_dir ".bashrc.d"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc.d/50-starship.sh" ".bashrc.d/50-starship.sh"

  ensure_user_shell_startup_chain "${target_home}"

  # Install Starship (external exception)
  install_starship

  # Deploy Starship config
  install_user_dir ".config"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/starship.toml" ".config/starship.toml"

  # Build i3status-rs if cargo is available
  install_i3status_rs

  # Deploy i3status-rs built-in icons/themes to user XDG config (highest priority lookup)
  if [[ -d /usr/local/share/i3status-rust ]]; then
    install_user_dir ".config/i3status-rust/icons"
    install_user_dir ".config/i3status-rust/themes"
    local f
    for f in /usr/local/share/i3status-rust/icons/*.toml; do
      [[ -f "$f" ]] || continue
      install_user_file "$f" ".config/i3status-rust/icons/$(basename "$f")"
    done
    for f in /usr/local/share/i3status-rust/themes/*.toml; do
      [[ -f "$f" ]] || continue
      install_user_file "$f" ".config/i3status-rust/themes/$(basename "$f")"
    done
  fi

  # Deploy i3status-rs config
  install_user_dir ".config/i3status-rust"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/i3status-rust/config.toml" ".config/i3status-rust/config.toml"

  # Upgrade bar config if i3status-rs is available
  upgrade_i3_bar_config "${target_home}"
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  [[ -f "${target_home}/.config/rofi/config.rasi" ]] || { log_error "Rofi config not deployed"; return 1; }
  [[ -d "${target_home}/downloads" ]] || { log_error "downloads directory not created"; return 1; }
  [[ -d "${target_home}/engagements" ]] || { log_error "engagements directory not created"; return 1; }
  [[ -d "${target_home}/loot" ]] || { log_error "loot directory not created"; return 1; }
  [[ -d "${target_home}/payloads" ]] || { log_error "payloads directory not created"; return 1; }
  [[ -d "${target_home}/reports" ]] || { log_error "reports directory not created"; return 1; }
  [[ -d "${target_home}/notes" ]] || { log_error "notes directory not created"; return 1; }
  [[ -d "${target_home}/screenshots" ]] || { log_error "screenshots directory not created"; return 1; }
  [[ -d "${target_home}/recordings" ]] || { log_error "recordings directory not created"; return 1; }
  [[ -d "${target_home}/.local/share/go" ]] || { log_error "Go data directory not created"; return 1; }
  [[ -f "${target_home}/.config/user-dirs.dirs" ]] || { log_error "XDG user dirs not configured"; return 1; }
  grep -q 'XDG_DOWNLOAD_DIR="\$HOME/downloads"' "${target_home}/.config/user-dirs.dirs" || { log_error "downloads XDG mapping missing"; return 1; }
  [[ -f "${target_home}/.config/alacritty/alacritty.toml" ]] || { log_error "Alacritty config not deployed"; return 1; }
  [[ -f "${target_home}/.inputrc" ]] || { log_error "inputrc not deployed"; return 1; }
  grep -q "set editing-mode vi" "${target_home}/.inputrc" || { log_error "inputrc missing vi-mode"; return 1; }
  [[ -f "${target_home}/.bashrc.d/50-starship.sh" ]] || { log_error "Starship bashrc drop-in not deployed"; return 1; }
  grep -q 'Source bashrc.d drop-ins' "${target_home}/.bashrc" || { log_error ".bashrc does not source bashrc.d drop-ins"; return 1; }
  if [[ -f "${target_home}/.bash_profile" ]]; then
    grep -q 'Source .bashrc for interactive shells' "${target_home}/.bash_profile" || { log_error ".bash_profile does not source .bashrc"; return 1; }
  elif [[ -f "${target_home}/.profile" ]]; then
    grep -q 'Source .bashrc for interactive shells' "${target_home}/.profile" || { log_error ".profile does not source .bashrc"; return 1; }
  else
    log_error "No login-shell startup file found for target user"
    return 1
  fi
  command -v starship >/dev/null 2>&1 || { log_error "starship binary not found"; return 1; }
  [[ -f "${target_home}/.config/starship.toml" ]] || { log_error "Starship config not deployed"; return 1; }
  grep -q 'git:' "${target_home}/.config/starship.toml" || { log_error "Starship config missing git branch segment"; return 1; }
  [[ -d "${target_home}/.mozilla/firefox/operator" ]] || { log_error "Firefox operator profile directory not created"; return 1; }
  [[ -f "${target_home}/.mozilla/firefox/profiles.ini" ]] || { log_error "Firefox profiles.ini missing"; return 1; }
  grep -q '^Name=operator$' "${target_home}/.mozilla/firefox/profiles.ini" || { log_error "Firefox operator profile not registered"; return 1; }
  [[ -f /etc/firefox/policies/policies.json ]] || { log_error "Firefox enterprise policy not installed"; return 1; }
  grep -q '"DisableTelemetry": true' /etc/firefox/policies/policies.json || { log_error "Firefox telemetry policy missing"; return 1; }
  if [[ -d /usr/lib/firefox-esr ]]; then
    [[ -f /usr/lib/firefox-esr/distribution/policies.json ]] || { log_error "Firefox ESR distribution policy missing"; return 1; }
  fi
}
