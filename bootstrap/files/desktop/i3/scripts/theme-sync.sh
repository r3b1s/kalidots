#!/usr/bin/env bash
set -euo pipefail

mode="apply"
if [[ "${1:-}" == "--watch" ]]; then
  mode="watch"
fi

cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/kalidots"
state_file="${cache_dir}/theme-sync.state"
lock_dir="${XDG_RUNTIME_DIR:-/tmp}/kalidots-theme-sync.lock"
theme_override_file="${HOME}/.config/kalidots/gtk-theme.override"
icon_override_file="${HOME}/.config/kalidots/icon-theme.override"

trim_quotes() {
  local value="${1:-}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "${value}"
}

trim_whitespace() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

read_gsettings_value() {
  local key="$1"
  if command -v gsettings >/dev/null 2>&1; then
    gsettings get org.gnome.desktop.interface "${key}" 2>/dev/null | head -n 1 || true
  fi
}

read_ini_value() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 0
  awk -F= -v wanted="${key}" '
    $1 == wanted {
      print substr($0, index($0, "=") + 1)
    }
  ' "${file}" | tail -n 1
}

theme_signature() {
  local gtk_settings="${HOME}/.config/gtk-3.0/settings.ini"
  local theme_name
  local icon_theme
  local theme_override
  local font_name
  local color_scheme
  local prefer_dark
  local mode_name

  theme_name="$(trim_quotes "$(read_gsettings_value gtk-theme)")"
  icon_theme="$(trim_quotes "$(read_gsettings_value icon-theme)")"
  font_name="$(trim_quotes "$(read_gsettings_value font-name)")"
  color_scheme="$(trim_quotes "$(read_gsettings_value color-scheme)")"

  if [[ -z "${theme_name}" ]]; then
    theme_name="$(read_ini_value "${gtk_settings}" "gtk-theme-name")"
  fi
  if [[ -f "${theme_override_file}" ]]; then
    theme_override="$(trim_whitespace "$(cat "${theme_override_file}")")"
    if [[ -n "${theme_override}" ]]; then
      theme_name="${theme_override}"
    fi
  fi
  if [[ -f "${icon_override_file}" ]]; then
    icon_theme="$(trim_whitespace "$(cat "${icon_override_file}")")"
  fi
  if [[ -z "${icon_theme}" ]]; then
    icon_theme="$(read_ini_value "${gtk_settings}" "gtk-icon-theme-name")"
  fi
  if [[ -z "${font_name}" ]]; then
    font_name="$(read_ini_value "${gtk_settings}" "gtk-font-name")"
  fi
  if [[ -z "${color_scheme}" ]]; then
    color_scheme="$(read_ini_value "${gtk_settings}" "gtk-color-scheme")"
  fi
  prefer_dark="$(read_ini_value "${gtk_settings}" "gtk-application-prefer-dark-theme")"

  if [[ "${color_scheme}" == "prefer-dark" || "${color_scheme}" == "dark" ]]; then
    mode_name="dark"
  elif [[ "${color_scheme}" == "prefer-light" || "${color_scheme}" == "light" ]]; then
    mode_name="light"
  elif [[ "${prefer_dark}" == "true" ]]; then
    mode_name="dark"
  elif [[ -n "${theme_name}" && "${theme_name,,}" == *dark* ]]; then
    mode_name="dark"
  else
    mode_name="dark"
  fi

  if [[ -z "${theme_name}" ]]; then
    if [[ "${mode_name}" == "dark" ]]; then
      theme_name="Arc-Dark"
    else
      theme_name="Arc"
    fi
  fi
  if [[ -z "${icon_theme}" ]]; then
    icon_theme="Adwaita"
  fi
  if [[ -z "${font_name}" ]]; then
    font_name="Sans 10"
  fi

  printf '%s|%s|%s|%s\n' "${mode_name}" "${theme_name}" "${icon_theme}" "${font_name}"
}

write_if_changed() {
  local dest="$1"
  local content="$2"
  local tmp

  tmp="$(mktemp)"
  printf '%s' "${content}" > "${tmp}"
  if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
    rm -f "${tmp}"
    return 1
  fi
  install -D -m 644 "${tmp}" "${dest}"
  rm -f "${tmp}"
  return 0
}

set_xfconf_value() {
  local property="$1"
  local value="$2"

  command -v xfconf-query >/dev/null 2>&1 || return 0

  if xfconf-query -c xsettings -p "${property}" >/dev/null 2>&1; then
    xfconf-query -c xsettings -p "${property}" -s "${value}" >/dev/null 2>&1 || true
  else
    xfconf-query -c xsettings -p "${property}" -n -t string -s "${value}" >/dev/null 2>&1 || true
  fi
}

sync_xfce_xsettings() {
  local theme_name="$1"
  local icon_theme="$2"
  local font_name="$3"

  set_xfconf_value "/Net/ThemeName" "${theme_name}"
  set_xfconf_value "/Net/IconThemeName" "${icon_theme}"
  set_xfconf_value "/Gtk/FontName" "${font_name}"
}

apply_theme() {
  local signature
  local mode_name
  local theme_name
  local icon_theme
  local font_name
  local dark_bool
  local gtk_content
  local gtk2_content
  local xsettings_content

  install -d "${cache_dir}" "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0" "${HOME}/.config/xsettingsd"

  signature="$(theme_signature)"
  if [[ -f "${state_file}" ]] \
    && [[ -f "${HOME}/.config/gtk-3.0/settings.ini" ]] \
    && [[ -f "${HOME}/.config/gtk-4.0/settings.ini" ]] \
    && [[ -f "${HOME}/.gtkrc-2.0" ]] \
    && [[ -f "${HOME}/.config/xsettingsd/xsettingsd.conf" ]] \
    && [[ "$(cat "${state_file}")" == "${signature}" ]]; then
    return 0
  fi

  IFS='|' read -r mode_name theme_name icon_theme font_name <<<"${signature}"
  if [[ "${mode_name}" == "dark" ]]; then
    dark_bool="true"
  else
    dark_bool="false"
  fi

  gtk_content="$(cat <<EOF
[Settings]
gtk-theme-name=${theme_name}
gtk-icon-theme-name=${icon_theme}
gtk-application-prefer-dark-theme=${dark_bool}
gtk-font-name=${font_name}
EOF
)"

  gtk2_content="$(cat <<EOF
gtk-theme-name="${theme_name}"
gtk-icon-theme-name="${icon_theme}"
gtk-font-name="${font_name}"
gtk-application-prefer-dark-theme=${dark_bool}
EOF
)"

  xsettings_content="$(cat <<EOF
Net/ThemeName "${theme_name}"
Net/IconThemeName "${icon_theme}"
Gtk/FontName "${font_name}"
EOF
)"

  write_if_changed "${HOME}/.config/gtk-3.0/settings.ini" "${gtk_content}" || true
  write_if_changed "${HOME}/.config/gtk-4.0/settings.ini" "${gtk_content}" || true
  write_if_changed "${HOME}/.gtkrc-2.0" "${gtk2_content}" || true
  write_if_changed "${HOME}/.config/xsettingsd/xsettingsd.conf" "${xsettings_content}" || true
  sync_xfce_xsettings "${theme_name}" "${icon_theme}" "${font_name}"
  printf '%s\n' "${signature}" > "${state_file}"

  if [[ -n "${DISPLAY:-}" ]] && command -v xsettingsd >/dev/null 2>&1; then
    if pgrep -u "${USER}" -x xsettingsd >/dev/null 2>&1; then
      pkill -HUP -u "${USER}" -x xsettingsd >/dev/null 2>&1 || true
    elif [[ "${mode}" == "apply" ]]; then
      xsettingsd >/dev/null 2>&1 &
    fi
  fi

  return 0
}

watch_loop() {
  if ! mkdir "${lock_dir}" 2>/dev/null; then
    exit 0
  fi
  trap 'rmdir "${lock_dir}" 2>/dev/null || true' EXIT

  while true; do
    apply_theme || true
    sleep 5
  done
}

case "${mode}" in
  apply)
    apply_theme || true
    ;;
  watch)
    watch_loop
    ;;
esac
