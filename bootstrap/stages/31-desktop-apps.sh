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

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  # Deploy Rofi config
  install_user_dir ".config/rofi"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/rofi/config.rasi" ".config/rofi/config.rasi"

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

  # Ensure .bashrc sources drop-ins
  local bashrc="${target_home}/.bashrc"
  local drop_in_marker="# Source bashrc.d drop-ins"
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
  [[ -f "${target_home}/.config/alacritty/alacritty.toml" ]] || { log_error "Alacritty config not deployed"; return 1; }
  [[ -f "${target_home}/.inputrc" ]] || { log_error "inputrc not deployed"; return 1; }
  grep -q "set editing-mode vi" "${target_home}/.inputrc" || { log_error "inputrc missing vi-mode"; return 1; }
  [[ -f "${target_home}/.bashrc.d/50-starship.sh" ]] || { log_error "Starship bashrc drop-in not deployed"; return 1; }
  command -v starship >/dev/null 2>&1 || { log_error "starship binary not found"; return 1; }
  [[ -f "${target_home}/.config/starship.toml" ]] || { log_error "Starship config not deployed"; return 1; }
}
