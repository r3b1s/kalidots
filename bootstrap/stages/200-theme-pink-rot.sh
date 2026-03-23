#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="theme-pink-rot"
stage_description="Apply pink-rot color theme to desktop applications"
stage_profiles=("theme")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

THEME_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/theme-policy.env"
PINK_ROT_WALLPAPER_URL="https://raw.githubusercontent.com/r3b1s/media-assets/main/backgrounds/malenia.jpg"

theme_i3_config() {
  local i3_config="$1"
  [[ -f "${i3_config}" ]] || { log_warn "i3 config not found — run desktop profile first"; return 0; }

  # Replace color variable values
  sed -i \
    -e 's/^set \$bg-color .*/set $bg-color #050007/' \
    -e 's/^set \$text-color .*/set $text-color #f17e97/' \
    -e 's/^set \$inactive-bg .*/set $inactive-bg #050007/' \
    -e 's/^set \$inactive-text .*/set $inactive-text #a85869/' \
    -e 's/^set \$urgent-bg .*/set $urgent-bg #8F0936/' \
    -e 's/^set \$indicator .*/set $indicator #D40D40/' \
    "${i3_config}"

  # Insert bar colors if not already present
  if ! grep -q 'colors {' "${i3_config}"; then
    sed -i '/^bar {/,/^}/ {
      /^}/ i\
  colors {\
    background #050007\
    statusline #f17e97\
    separator #a85869\
    focused_workspace #D40D40 #D40D40 #050007\
    inactive_workspace #050007 #050007 #a85869\
    urgent_workspace #8F0936 #8F0936 #f17e97\
  }
    }' "${i3_config}"
  fi
}

install_pink_rot_wallpaper() {
  local target_home="$1"
  local wallpaper_tmp=""
  local wallpaper_path="${target_home}/.wallpaper"

  PACKAGE_POLICY_FILE="${THEME_POLICY_FILE}"
  load_package_policy

  if [[ "${PACKAGE_POLICY_ALLOW_EXTERNAL:-}" != "1" ]]; then
    log_error "Theme policy forbids external wallpaper downloads."
    return 1
  fi

  if [[ ",${PACKAGE_POLICY_EXTERNAL_EXCEPTIONS:-}," != *",theme-wallpaper,"* ]]; then
    log_error "Theme policy must allow external exception theme-wallpaper."
    return 1
  fi

  wallpaper_tmp="$(mktemp)"
  if ! curl -fL --retry 3 --output "${wallpaper_tmp}" "${PINK_ROT_WALLPAPER_URL}"; then
    rm -f "${wallpaper_tmp}"
    log_error "Failed to download pink-rot wallpaper from ${PINK_ROT_WALLPAPER_URL}"
    return 1
  fi

  install -m 644 -o "${TARGET_USER}" -g "${TARGET_USER}" "${wallpaper_tmp}" "${wallpaper_path}"
  rm -f "${wallpaper_tmp}"

  if [[ -n "${DISPLAY:-}" ]]; then
    runuser -u "${TARGET_USER}" -- env \
      DISPLAY="${DISPLAY}" \
      XAUTHORITY="${XAUTHORITY:-${target_home}/.Xauthority}" \
      feh --bg-fill "${wallpaper_path}" >/dev/null 2>&1 || \
      log_warn "Wallpaper downloaded, but live wallpaper refresh via feh failed; it will apply on next i3 start."
  fi
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  # 1. Alacritty — full themed replacement
  install_user_dir ".config/alacritty"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/alacritty.toml" \
    ".config/alacritty/alacritty.toml"

  # 2. i3 — sed color variables + bar colors
  theme_i3_config "${target_home}/.config/i3/config"

  # 3. Rofi — themed config
  install_user_dir ".config/rofi"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/rofi.rasi" \
    ".config/rofi/config.rasi"

  # 4. i3status-rust — custom theme + themed config
  install_user_dir ".config/i3status-rust/themes"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/i3status-rs-theme.toml" \
    ".config/i3status-rust/themes/pink-rot.toml"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/i3status-rs-config.toml" \
    ".config/i3status-rust/config.toml"

  # 5. dunst — notification colors
  install_user_dir ".config/dunst"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/dunstrc" \
    ".config/dunst/dunstrc"

  # 6. btop — system monitor theme
  install_user_dir ".config/btop/themes"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/btop.theme" \
    ".config/btop/themes/pink-rot.theme"

  # 7. Starship prompt — themed colors
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/starship.toml" \
    ".config/starship.toml"

  # 8. GTK / Thunar — dark theme
  apt-get install -y -qq arc-theme 2>/dev/null || log_warn "arc-theme not available in repos"
  install_user_dir ".config/gtk-3.0"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/gtk3-settings.ini" \
    ".config/gtk-3.0/settings.ini"

  # 9. Wallpaper for i3 via ~/.wallpaper, which the desktop i3 config loads with feh.
  install_pink_rot_wallpaper "${target_home}"

  # 10. Neovim — theme-specific colorscheme overlay for LazyVim
  if [[ -d "${target_home}/.config/nvim" ]]; then
    install_user_dir ".config/nvim/colors"
    install_user_dir ".config/nvim/lua/plugins"
    install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/nvim/colors/kalidots.lua" \
      ".config/nvim/colors/kalidots.lua"
    install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/nvim/lua/plugins/kalidots-theme.lua" \
      ".config/nvim/lua/plugins/kalidots-theme.lua"
  else
    log_warn "Neovim config not found — skipping pink-rot Neovim theme overlay"
  fi
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  # Verify themed alacritty
  [[ -f "${target_home}/.config/alacritty/alacritty.toml" ]] || { log_error "Alacritty config not deployed"; return 1; }
  grep -q '#050007' "${target_home}/.config/alacritty/alacritty.toml" || { log_error "Alacritty missing pink-rot colors"; return 1; }

  # Verify i3 colors were themed
  local i3_config="${target_home}/.config/i3/config"
  if [[ -f "${i3_config}" ]]; then
    grep -q '#050007' "${i3_config}" || { log_error "i3 config missing pink-rot bg color"; return 1; }
    grep -q '#D40D40' "${i3_config}" || { log_error "i3 config missing pink-rot indicator color"; return 1; }
    # Verify placeholders were not broken
    grep -q '__TARGET_HOME__' "${i3_config}" && { log_error "i3 config has unresolved placeholders"; return 1; }
  fi

  # Verify other theme files
  [[ -f "${target_home}/.config/rofi/config.rasi" ]] || { log_error "Rofi theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/i3status-rust/themes/pink-rot.toml" ]] || { log_error "i3status-rs theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/dunst/dunstrc" ]] || { log_error "dunst config not deployed"; return 1; }
  [[ -f "${target_home}/.config/btop/themes/pink-rot.theme" ]] || { log_error "btop theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/starship.toml" ]] || { log_error "Starship theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/gtk-3.0/settings.ini" ]] || { log_error "GTK settings not deployed"; return 1; }
  [[ -s "${target_home}/.wallpaper" ]] || { log_error "Wallpaper not downloaded to ${target_home}/.wallpaper"; return 1; }

  if [[ -d "${target_home}/.config/nvim" ]]; then
    [[ -f "${target_home}/.config/nvim/colors/kalidots.lua" ]] || { log_error "Neovim pink-rot colorscheme not deployed"; return 1; }
    [[ -f "${target_home}/.config/nvim/lua/plugins/kalidots-theme.lua" ]] || { log_error "Neovim pink-rot LazyVim override not deployed"; return 1; }
  fi
}
