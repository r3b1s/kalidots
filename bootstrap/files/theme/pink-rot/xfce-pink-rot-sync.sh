#!/usr/bin/env bash
set -euo pipefail

theme_name="Kali-Pink-Dark"
icon_theme="Flat-Remix-Pink-Dark"
wallpaper_path="__TARGET_HOME__/downloads/pink-rot-radahn.png"
desktop_xml_path="__TARGET_HOME__/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

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
  local single_property=""
  local updated=0

  while IFS= read -r property; do
    [[ -n "${property}" ]] || continue
    set_xfconf_string "xfce4-desktop" "${property}" "${wallpaper_path}"
    style_property="${property%/last-image}/image-style"
    single_property="${property%/last-image}/last-single-image"
    set_xfconf_int "xfce4-desktop" "${style_property}" "5"
    set_xfconf_string "xfce4-desktop" "${single_property}" "${wallpaper_path}"
    updated=1
  done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | awk '/\/last-image$/ { print }')

  if [[ "${updated}" -eq 0 ]]; then
    set_xfconf_string "xfce4-desktop" "/backdrop/screen0/monitor0/workspace0/last-image" "${wallpaper_path}"
    set_xfconf_string "xfce4-desktop" "/backdrop/screen0/monitor0/workspace0/last-single-image" "${wallpaper_path}"
    set_xfconf_int "xfce4-desktop" "/backdrop/screen0/monitor0/workspace0/image-style" "5"
    set_xfconf_string "xfce4-desktop" "/backdrop/screen0/monitor0/image-path" "${wallpaper_path}"
    set_xfconf_int "xfce4-desktop" "/backdrop/screen0/monitor0/image-style" "5"
  fi
}

persist_wallpaper_xml() {
  install -d -m 755 "$(dirname "${desktop_xml_path}")"

  if [[ -f "${desktop_xml_path}" ]]; then
    sed -i \
      -e "s|<property name=\"last-image\" type=\"string\" value=\"[^\"]*\" */>|<property name=\"last-image\" type=\"string\" value=\"${wallpaper_path}\"/>|g" \
      -e "s|<property name=\"last-single-image\" type=\"string\" value=\"[^\"]*\" */>|<property name=\"last-single-image\" type=\"string\" value=\"${wallpaper_path}\"/>|g" \
      -e 's|<property name="image-style" type="int" value="[0-9]*" */>|<property name="image-style" type="int" value="5"/>|g' \
      "${desktop_xml_path}"
      return 0
  fi

  cat > "${desktop_xml_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="${wallpaper_path}"/>
          <property name="last-single-image" type="string" value="${wallpaper_path}"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
}

main() {
  [[ -f "${wallpaper_path}" ]] || exit 0

  persist_wallpaper_xml

  command -v xfconf-query >/dev/null 2>&1 || exit 0
  apply_xsettings
  apply_wallpaper
}

main "$@"
