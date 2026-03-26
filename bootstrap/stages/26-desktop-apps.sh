#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="desktop-apps"
stage_description="Configure Rofi, Alacritty, zsh ergonomics, tmux, and status bar"
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

install_i3status_rs() {
  local target_home
  local cargo_home
  local rustup_home
  local cargo_bin
  local rustup_bin
  local user_path

  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  cargo_home="${target_home}/.cargo"
  rustup_home="${target_home}/.rustup"
  cargo_bin="${cargo_home}/bin/cargo"
  rustup_bin="${cargo_home}/bin/rustup"
  user_path="${cargo_home}/bin:${target_home}/.local/bin:${target_home}/.local/share/go/bin:/usr/local/go/bin:${PATH}"

  if command -v i3status-rs >/dev/null 2>&1; then
    log_info "i3status-rs already installed"
    return 0
  fi

  ensure_stable_rust_toolchain() {
    if [[ ! -x "${rustup_bin}" ]]; then
      log_info "Installing minimal Rust toolchain for ${TARGET_USER}"
      runuser -u "${TARGET_USER}" -- env \
        HOME="${target_home}" \
        CARGO_HOME="${cargo_home}" \
        RUSTUP_HOME="${rustup_home}" \
        PATH="${user_path}" \
        bash -lc 'curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none'
    fi

    log_info "Ensuring stable Rust toolchain for ${TARGET_USER}"
    if ! runuser -u "${TARGET_USER}" -- env \
      HOME="${target_home}" \
      CARGO_HOME="${cargo_home}" \
      RUSTUP_HOME="${rustup_home}" \
      PATH="${user_path}" \
      bash -lc 'cd "$HOME" && rustup set profile minimal && rustup toolchain install stable --profile minimal'; then
      log_warn "Stable Rust toolchain install failed; cleaning partial state and retrying once"
      runuser -u "${TARGET_USER}" -- env \
        HOME="${target_home}" \
        CARGO_HOME="${cargo_home}" \
        RUSTUP_HOME="${rustup_home}" \
        PATH="${user_path}" \
        bash -lc 'cd "$HOME" && rustup toolchain uninstall stable >/dev/null 2>&1 || true'
      runuser -u "${TARGET_USER}" -- env \
        HOME="${target_home}" \
        CARGO_HOME="${cargo_home}" \
        RUSTUP_HOME="${rustup_home}" \
        PATH="${user_path}" \
        bash -lc 'cd "$HOME" && rustup set profile minimal && rustup toolchain install stable --profile minimal'
    fi

    runuser -u "${TARGET_USER}" -- env \
      HOME="${target_home}" \
      CARGO_HOME="${cargo_home}" \
      RUSTUP_HOME="${rustup_home}" \
      PATH="${user_path}" \
      rustup default stable
  }

  if [[ ! -x "${cargo_bin}" ]] || [[ -x "${rustup_bin}" ]]; then
    ensure_stable_rust_toolchain
  fi

  if [[ ! -x "${cargo_bin}" ]]; then
    log_error "cargo unavailable after Rust toolchain bootstrap"
    return 1
  fi

  log_info "Building i3status-rs from source (manual install)"
  local build_dir
  build_dir="$(mktemp -d)"
  git clone --depth 1 https://github.com/greshake/i3status-rust.git "${build_dir}"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${build_dir}"
  runuser -u "${TARGET_USER}" -- env \
    HOME="${target_home}" \
    CARGO_HOME="${cargo_home}" \
    RUSTUP_HOME="${rustup_home}" \
    PATH="${user_path}" \
    cargo build --manifest-path "${build_dir}/Cargo.toml" --release --locked
  install -m 755 "${build_dir}/target/release/i3status-rs" /usr/local/bin/i3status-rs
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

upgrade_i3_bar_config() {
  local target_home="$1"

  [[ -f "${target_home}/.config/i3/config" ]] || return 0
  if command -v i3status-rs >/dev/null 2>&1; then
    log_info "i3status-rs available; status-command wrapper will prefer it"
  else
    log_info "i3status-rs unavailable; status-command wrapper will use themed i3status fallback"
  fi
}

configure_zsh_user() {
  local target_home="$1"
  local zsh_path

  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/zshrc" ".zshrc"
  zsh_path="$(command -v zsh)"
  usermod --shell "${zsh_path}" "${TARGET_USER}"
}

remove_starship() {
  local target_home="$1"

  rm -f "${target_home}/.bashrc.d/50-starship.sh" \
        "${target_home}/.config/starship.toml" \
        /usr/local/bin/starship
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  # Deploy Rofi config
  install_user_dir ".config/rofi"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/rofi/config.rasi" ".config/rofi/config.rasi"

  configure_operator_home_dirs "${target_home}"

  # Install Nerd Font for Alacritty
  install_nerd_font

  # Deploy Alacritty config
  install_user_dir ".config/alacritty"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/alacritty/alacritty.toml" ".config/alacritty/alacritty.toml"

  # Deploy tmux config
  install_user_dir ".config/tmux"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/tmux/tmux.conf" ".config/tmux/tmux.conf"

  # Deploy shell ergonomics
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc" ".bashrc"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/inputrc" ".inputrc"
  configure_zsh_user "${target_home}"
  remove_starship "${target_home}"
  install_user_dir ".config/gtk-3.0"
  install_user_dir ".config/gtk-4.0"
  install_user_dir ".config/xsettingsd"
  if [[ -x "${target_home}/.config/i3/scripts/theme-sync.sh" ]]; then
    runuser -u "${TARGET_USER}" -- env HOME="${target_home}" "${target_home}/.config/i3/scripts/theme-sync.sh"
  fi

  # Build i3status-rs from source, bootstrapping Rust if needed.
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
  install_user_dir ".config/i3status"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/i3status/config" ".config/i3status/config"

  upgrade_i3_bar_config "${target_home}"

  # Deploy update manager and manifest template
  install_user_dir ".config/kalidots"
  if [[ ! -f "${target_home}/.config/kalidots/update-manifest.json" ]]; then
    local manifest_tmp
    manifest_tmp="$(mktemp)"
    cat > "${manifest_tmp}" <<'MANIFEST'
{
  "schema_version": "1",
  "tools": []
}
MANIFEST
    install_user_file "${manifest_tmp}" ".config/kalidots/update-manifest.json"
    rm -f "${manifest_tmp}"
  fi
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
  [[ -f "${target_home}/.config/tmux/tmux.conf" ]] || { log_error "tmux config not deployed"; return 1; }
  [[ -f "${target_home}/.bashrc" ]] || { log_error ".bashrc not deployed"; return 1; }
  grep -q 'set -o vi' "${target_home}/.bashrc" || { log_error ".bashrc missing vi mode"; return 1; }
  [[ -f "${target_home}/.inputrc" ]] || { log_error "inputrc not deployed"; return 1; }
  grep -q "set editing-mode vi" "${target_home}/.inputrc" || { log_error "inputrc missing vi-mode"; return 1; }
  [[ -f "${target_home}/.zshrc" ]] || { log_error ".zshrc not deployed"; return 1; }
  grep -q 'bindkey -v' "${target_home}/.zshrc" || { log_error ".zshrc missing vi mode"; return 1; }
  [[ "$(getent passwd "${TARGET_USER}" | cut -d: -f7)" == "$(command -v zsh)" ]] || { log_error "Target user shell is not zsh"; return 1; }
  [[ -f "${target_home}/.config/gtk-3.0/settings.ini" ]] || { log_error "GTK 3 settings not deployed"; return 1; }
  [[ -f "${target_home}/.config/gtk-4.0/settings.ini" ]] || { log_error "GTK 4 settings not deployed"; return 1; }
  [[ -f "${target_home}/.config/xsettingsd/xsettingsd.conf" ]] || { log_error "xsettingsd config not deployed"; return 1; }
  [[ ! -f "${target_home}/.bashrc.d/50-starship.sh" ]] || { log_error "Starship bash drop-in should be removed"; return 1; }
  [[ ! -f "${target_home}/.config/starship.toml" ]] || { log_error "Starship config should be removed"; return 1; }
  command -v btop >/dev/null 2>&1 || { log_error "btop not found in PATH"; return 1; }
  [[ -f "${target_home}/.config/i3status/config" ]] || { log_error "i3status fallback config not deployed"; return 1; }
  command -v i3status-rs >/dev/null 2>&1 || { log_error "i3status-rs binary not found"; return 1; }
}
