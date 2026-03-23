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
PINK_ROT_GTK_THEME="Kali-Pink-Dark"
PINK_ROT_ICON_THEME="Flat-Remix-Pink-Dark"
PINK_ROT_INDICATOR_COLOR="#D10A0A"
PINK_ROT_I3_WALLPAPER_URL="https://raw.githubusercontent.com/r3b1s/media-assets/main/backgrounds/malenia.jpg"
PINK_ROT_XFCE_WALLPAPER_URL="https://raw.githubusercontent.com/r3b1s/media-assets/main/backgrounds/radahn.png"

firefox_profile_paths() {
  local target_home="$1"
  local profiles_ini="${target_home}/.mozilla/firefox/profiles.ini"
  local path
  local is_relative=1

  [[ -f "${profiles_ini}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      IsRelative=*)
        is_relative="${line#IsRelative=}"
        ;;
      Path=*)
        path="${line#Path=}"
        if [[ "${is_relative}" == "1" ]]; then
          printf '%s\n' "${target_home}/.mozilla/firefox/${path}"
        else
          printf '%s\n' "${path}"
        fi
        is_relative=1
        ;;
    esac
  done < "${profiles_ini}"
}

apply_firefox_theme() {
  local target_home="$1"
  local profile_dir
  local user_js
  local pref_line='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

  while IFS= read -r profile_dir; do
    [[ -n "${profile_dir}" ]] || continue
    install -d -m 755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${profile_dir}/chrome"
    install -m 644 -o "${TARGET_USER}" -g "${TARGET_USER}" \
      "${BOOTSTRAP_ROOT}/files/theme/pink-rot/firefox/userChrome.css" \
      "${profile_dir}/chrome/userChrome.css"
    install -m 644 -o "${TARGET_USER}" -g "${TARGET_USER}" \
      "${BOOTSTRAP_ROOT}/files/theme/pink-rot/firefox/userContent.css" \
      "${profile_dir}/chrome/userContent.css"

    user_js="${profile_dir}/user.js"
    if [[ -f "${user_js}" ]] && grep -q 'toolkit.legacyUserProfileCustomizations.stylesheets' "${user_js}"; then
      sed -i 's|^user_pref("toolkit\.legacyUserProfileCustomizations\.stylesheets".*|user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);|' "${user_js}"
    else
      printf '%s\n' "${pref_line}" >> "${user_js}"
    fi
    chown "${TARGET_USER}:${TARGET_USER}" "${user_js}"
  done < <(firefox_profile_paths "${target_home}")
}

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
    -e "s/^set \\$indicator .*/set \\$indicator ${PINK_ROT_INDICATOR_COLOR}/" \
    -e '/^bar {/,/^}/ s/^[[:space:]]*background .*/    background #050007/' \
    -e '/^bar {/,/^}/ s/^[[:space:]]*statusline .*/    statusline #f17e97/' \
    -e '/^bar {/,/^}/ s/^[[:space:]]*separator .*/    separator #7f0809/' \
    -e "/^bar {/,/^}/ s/^[[:space:]]*focused_workspace .*/    focused_workspace ${PINK_ROT_INDICATOR_COLOR} ${PINK_ROT_INDICATOR_COLOR} #050007/" \
    -e '/^bar {/,/^}/ s/^[[:space:]]*inactive_workspace .*/    inactive_workspace #050007 #050007 #a85869/' \
    -e '/^bar {/,/^}/ s/^[[:space:]]*urgent_workspace .*/    urgent_workspace #8F0936 #8F0936 #f17e97/' \
    "${i3_config}"

  # Insert bar colors if not already present
  if ! grep -q 'colors {' "${i3_config}"; then
    sed -i '/^bar {/,/^}/ {
      /^}/ i\
  colors {\
    background #050007\
    statusline #f17e97\
    separator #7f0809\
    focused_workspace '"${PINK_ROT_INDICATOR_COLOR}"' '"${PINK_ROT_INDICATOR_COLOR}"' #050007\
    inactive_workspace #050007 #050007 #a85869\
    urgent_workspace #8F0936 #8F0936 #f17e97\
  }
    }' "${i3_config}"
  fi
}

refresh_i3_theme_runtime() {
  local target_home="$1"

  [[ -n "${DISPLAY:-}" ]] || return 0
  command -v i3-msg >/dev/null 2>&1 || return 0

  runuser -u "${TARGET_USER}" -- env \
    HOME="${target_home}" \
    DISPLAY="${DISPLAY}" \
    XAUTHORITY="${XAUTHORITY:-${target_home}/.Xauthority}" \
    i3-msg reload >/dev/null 2>&1 || true

  pkill -u "${TARGET_USER}" -x i3status-rs >/dev/null 2>&1 || true
}

download_theme_asset() {
  local asset_url="$1"
  local dest_path="$2"
  local description="$3"
  local asset_tmp=""

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

  asset_tmp="$(mktemp)"
  if ! curl -fL --retry 3 --output "${asset_tmp}" "${asset_url}"; then
    rm -f "${asset_tmp}"
    log_error "Failed to download ${description} from ${asset_url}"
    return 1
  fi

  install -D -m 644 -o "${TARGET_USER}" -g "${TARGET_USER}" "${asset_tmp}" "${dest_path}"
  rm -f "${asset_tmp}"
}

install_pink_rot_i3_wallpaper() {
  local target_home="$1"
  local wallpaper_path="${target_home}/.wallpaper"

  download_theme_asset "${PINK_ROT_I3_WALLPAPER_URL}" "${wallpaper_path}" "pink-rot i3 wallpaper"

  if [[ -n "${DISPLAY:-}" ]]; then
    runuser -u "${TARGET_USER}" -- env \
      DISPLAY="${DISPLAY}" \
      XAUTHORITY="${XAUTHORITY:-${target_home}/.Xauthority}" \
      feh --bg-fill "${wallpaper_path}" >/dev/null 2>&1 || \
      log_warn "Wallpaper downloaded, but live wallpaper refresh via feh failed; it will apply on next i3 start."
  fi
}

configure_pink_rot_gtk_theme_override() {
  local target_home="$1"
  local marker_dir="${target_home}/.config/kalidots"
  local theme_override_file="${marker_dir}/gtk-theme.override"
  local icon_override_file="${marker_dir}/icon-theme.override"

  install -d -m 755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${marker_dir}"
  printf '%s\n' "${PINK_ROT_GTK_THEME}" > "${theme_override_file}"
  chown "${TARGET_USER}:${TARGET_USER}" "${theme_override_file}"
  chmod 644 "${theme_override_file}"
  printf '%s\n' "${PINK_ROT_ICON_THEME}" > "${icon_override_file}"
  chown "${TARGET_USER}:${TARGET_USER}" "${icon_override_file}"
  chmod 644 "${icon_override_file}"
  rm -rf "${target_home}/.local/share/icons/Breeze Chameleon Dark"
}

install_xfce_sync_files() {
  local target_home="$1"
  local tmp_script=""
  local tmp_desktop=""

  install_user_dir ".config/kalidots"
  install_user_dir ".config/autostart"

  tmp_script="$(mktemp)"
  sed "s|__TARGET_HOME__|${target_home}|g" \
    "${BOOTSTRAP_ROOT}/files/theme/pink-rot/xfce-pink-rot-sync.sh" > "${tmp_script}"
  install_user_file "${tmp_script}" ".config/kalidots/pink-rot-xfce-sync.sh" 755
  rm -f "${tmp_script}"

  tmp_desktop="$(mktemp)"
  sed "s|__TARGET_HOME__|${target_home}|g" \
    "${BOOTSTRAP_ROOT}/files/theme/pink-rot/xfce-pink-rot.desktop" > "${tmp_desktop}"
  install_user_file "${tmp_desktop}" ".config/autostart/kalidots-pink-rot-xfce.desktop"
  rm -f "${tmp_desktop}"
}

install_pink_rot_xfce_wallpaper() {
  local target_home="$1"
  local wallpaper_path="${target_home}/downloads/pink-rot-radahn.png"

  install_user_dir "downloads"
  download_theme_asset "${PINK_ROT_XFCE_WALLPAPER_URL}" "${wallpaper_path}" "pink-rot Xfce wallpaper"

  if [[ -x "${target_home}/.config/kalidots/pink-rot-xfce-sync.sh" ]]; then
    runuser -u "${TARGET_USER}" -- env HOME="${target_home}" "${target_home}/.config/kalidots/pink-rot-xfce-sync.sh" || \
      log_warn "Xfce pink-rot sync did not complete; settings should apply on the next Xfce session start."
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
  install_user_dir ".config/i3status"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/i3status.conf" \
    ".config/i3status/config"

  # 5. dunst — notification colors
  install_user_dir ".config/dunst"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/dunstrc" \
    ".config/dunst/dunstrc"

  # 6. btop — system monitor theme
  install_user_dir ".config/btop"
  install_user_dir ".config/btop/themes"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/btop.conf" \
    ".config/btop/btop.conf"
  install_user_file "${BOOTSTRAP_ROOT}/files/theme/pink-rot/btop.theme" \
    ".config/btop/themes/pink-rot.theme"

  # 7. GTK / Thunar — keep the current system theme mode in sync
  install_user_dir ".config/gtk-3.0"
  install_user_dir ".config/gtk-4.0"
  install_user_dir ".config/xsettingsd"
  install_user_dir ".config/kalidots"
  configure_pink_rot_gtk_theme_override "${target_home}"
  install_xfce_sync_files "${target_home}"
  if [[ -x "${target_home}/.config/i3/scripts/theme-sync.sh" ]]; then
    runuser -u "${TARGET_USER}" -- env HOME="${target_home}" "${target_home}/.config/i3/scripts/theme-sync.sh"
  fi

  # 8. Wallpapers. Keep i3 on malenia.jpg; set Xfce to the Radahn wallpaper.
  install_pink_rot_i3_wallpaper "${target_home}"
  install_pink_rot_xfce_wallpaper "${target_home}"
  refresh_i3_theme_runtime "${target_home}"

  # 9. Neovim — theme-specific colorscheme overlay for LazyVim
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

  # 10. Firefox — apply theme CSS to all profiles and enable chrome stylesheets here only.
  apply_firefox_theme "${target_home}"
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
    grep -q "${PINK_ROT_INDICATOR_COLOR}" "${i3_config}" || { log_error "i3 config missing pink-rot indicator color"; return 1; }
    # Verify placeholders were not broken
    grep -q '__TARGET_HOME__' "${i3_config}" && { log_error "i3 config has unresolved placeholders"; return 1; }
  fi

  # Verify other theme files
  [[ -f "${target_home}/.config/rofi/config.rasi" ]] || { log_error "Rofi theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/i3status-rust/themes/pink-rot.toml" ]] || { log_error "i3status-rs theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/i3status/config" ]] || { log_error "i3status fallback theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/dunst/dunstrc" ]] || { log_error "dunst config not deployed"; return 1; }
  [[ -f "${target_home}/.config/btop/btop.conf" ]] || { log_error "btop config not deployed"; return 1; }
  [[ -f "${target_home}/.config/btop/themes/pink-rot.theme" ]] || { log_error "btop theme not deployed"; return 1; }
  [[ -f "${target_home}/.config/gtk-3.0/settings.ini" ]] || { log_error "GTK 3 settings not deployed"; return 1; }
  [[ -f "${target_home}/.config/gtk-4.0/settings.ini" ]] || { log_error "GTK 4 settings not deployed"; return 1; }
  [[ -f "${target_home}/.config/xsettingsd/xsettingsd.conf" ]] || { log_error "xsettingsd config not deployed"; return 1; }
  grep -q "gtk-theme-name=${PINK_ROT_GTK_THEME}" "${target_home}/.config/gtk-3.0/settings.ini" || { log_error "GTK theme not switched to ${PINK_ROT_GTK_THEME}"; return 1; }
  grep -q "gtk-icon-theme-name=${PINK_ROT_ICON_THEME}" "${target_home}/.config/gtk-3.0/settings.ini" || { log_error "GTK icon theme not switched to ${PINK_ROT_ICON_THEME}"; return 1; }
  [[ -f "${target_home}/.config/kalidots/gtk-theme.override" ]] || { log_error "GTK theme override marker missing"; return 1; }
  [[ -f "${target_home}/.config/kalidots/icon-theme.override" ]] || { log_error "Icon theme override marker missing"; return 1; }
  grep -qx "${PINK_ROT_GTK_THEME}" "${target_home}/.config/kalidots/gtk-theme.override" || { log_error "GTK theme override marker incorrect"; return 1; }
  grep -qx "${PINK_ROT_ICON_THEME}" "${target_home}/.config/kalidots/icon-theme.override" || { log_error "Icon theme override marker incorrect"; return 1; }
  [[ -s "${target_home}/.wallpaper" ]] || { log_error "i3 wallpaper not downloaded to ${target_home}/.wallpaper"; return 1; }
  [[ -s "${target_home}/downloads/pink-rot-radahn.png" ]] || { log_error "Xfce wallpaper not downloaded"; return 1; }
  [[ -x "${target_home}/.config/kalidots/pink-rot-xfce-sync.sh" ]] || { log_error "Xfce pink-rot sync script not deployed"; return 1; }
  [[ -f "${target_home}/.config/autostart/kalidots-pink-rot-xfce.desktop" ]] || { log_error "Xfce pink-rot autostart entry not deployed"; return 1; }
  [[ -f "${target_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" ]] || { log_error "Xfce desktop wallpaper XML not deployed"; return 1; }

  if [[ -d "${target_home}/.config/nvim" ]]; then
    [[ -f "${target_home}/.config/nvim/colors/kalidots.lua" ]] || { log_error "Neovim pink-rot colorscheme not deployed"; return 1; }
    [[ -f "${target_home}/.config/nvim/lua/plugins/kalidots-theme.lua" ]] || { log_error "Neovim pink-rot LazyVim override not deployed"; return 1; }
    grep -q '#050007' "${target_home}/.config/nvim/colors/kalidots.lua" || { log_error "Neovim theme background not dark enough"; return 1; }
    grep -q '#d40d40' "${target_home}/.config/nvim/colors/kalidots.lua" || { log_error "Neovim theme accent not updated"; return 1; }
  fi

  local operator_profile="${target_home}/.mozilla/firefox/operator"
  [[ -f "${operator_profile}/chrome/userChrome.css" ]] || { log_error "Firefox userChrome.css not deployed"; return 1; }
  [[ -f "${operator_profile}/chrome/userContent.css" ]] || { log_error "Firefox userContent.css not deployed"; return 1; }
  [[ -f "${operator_profile}/user.js" ]] || { log_error "Firefox theme-stage user.js not deployed"; return 1; }
  grep -q 'toolkit.legacyUserProfileCustomizations.stylesheets", true' "${operator_profile}/user.js" || { log_error "Firefox userChrome pref not enabled in theme stage"; return 1; }
}
