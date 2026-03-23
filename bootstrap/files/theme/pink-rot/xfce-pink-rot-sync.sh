#!/usr/bin/env bash
set -euo pipefail

theme_name="Kali-Pink-Dark"
icon_theme="Flat-Remix-Pink-Dark"
wallpaper_path="__TARGET_HOME__/.local/share/backgrounds/pink-rot-radahn.png"

set_xfconf_string() {
  local channel="$1"
  local property="$2"
  local value="$3"

  if xfconf-query -c "${channel}" -p "${property}" >/dev/null 2>&1; then
    xfconf-query -c "${channel}" -p "${property}" -s "${value}" >/dev/null 2>&1 || true
  else
    xfconf-query -c "${channel}" -p "${property}" -n -t string -s "${value}" >/dev/null 2>&1 || true
  fi
}

set_xfconf_int() {
  local channel="$1"
  local property="$2"
  local value="$3"

  if xfconf-query -c "${channel}" -p "${property}" >/dev/null 2>&1; then
    xfconf-query -c "${channel}" -p "${property}" -s "${value}" >/dev/null 2>&1 || true
  else
    xfconf-query -c "${channel}" -p "${property}" -n -t int -s "${value}" >/dev/null 2>&1 || true
  fi
}

apply_xsettings() {
  set_xfconf_string "xsettings" "/Net/ThemeName" "${theme_name}"
  set_xfconf_string "xsettings" "/Net/IconThemeName" "${icon_theme}"
}

apply_wallpaper() {
  local property=""
  local style_property=""
  local updated=0

  while IFS= read -r property; do
    [[ -n "${property}" ]] || continue
    set_xfconf_string "xfce4-desktop" "${property}" "${wallpaper_path}"
    style_property="${property%/last-image}/image-style"
    set_xfconf_int "xfce4-desktop" "${style_property}" "5"
    updated=1
  done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | awk '/\/last-image$/ { print }')

  if [[ "${updated}" -eq 0 ]]; then
    set_xfconf_string "xfce4-desktop" "/backdrop/screen0/monitor0/workspace0/last-image" "${wallpaper_path}"
    set_xfconf_int "xfce4-desktop" "/backdrop/screen0/monitor0/workspace0/image-style" "5"
    set_xfconf_string "xfce4-desktop" "/backdrop/screen0/monitor0/image-path" "${wallpaper_path}"
    set_xfconf_int "xfce4-desktop" "/backdrop/screen0/monitor0/image-style" "5"
  fi
}

main() {
  command -v xfconf-query >/dev/null 2>&1 || exit 0
  [[ -f "${wallpaper_path}" ]] || exit 0

  apply_xsettings
  apply_wallpaper
}

main "$@"
