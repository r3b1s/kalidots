#!/usr/bin/env bash
set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/kalidots-display-hotplug-watch.lock"
enable_marker="${HOME}/.config/kalidots/qemu-hyprland-screen-resize-fix.enabled"
poll_interval="${DISPLAY_RESIZE_POLL_INTERVAL:-2}"
wallpaper_path="${HOME}/.wallpaper"
wallpaper_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/kalidots"

restart_spice_vdagent() {
  command -v spice-vdagent >/dev/null 2>&1 || return 0

  pkill -x spice-vdagent >/dev/null 2>&1 || true
  spice-vdagent >/dev/null 2>&1 &
  disown || true
}

cleanup() {
  rmdir "${lock_dir}" 2>/dev/null || true
}

current_output_mode() {
  local output="$1"
  xrandr --query | awk -v output="${output}" '
    $1 == output && $2 == "connected" {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
          split($i, parts, "+")
          print parts[1]
          exit
        }
      }
    }
  '
}

preferred_output_mode() {
  local output="$1"
  xrandr --query | awk -v output="${output}" '
    $1 == output && $2 == "connected" {
      in_output = 1
      next
    }
    in_output && $0 ~ /^[^[:space:]]/ {
      exit
    }
    in_output && /\+/ {
      print $1
      exit
    }
  '
}

primary_output() {
  xrandr --query | awk '/ connected primary/ { print $1; exit }'
}

first_connected_output() {
  xrandr --query | awk '/ connected/ { print $1; exit }'
}

apply_layout_if_needed() {
  local output="$1"
  local current_mode
  local preferred_mode
  local screen_size
  local screen_width
  local screen_height
  local rendered_wallpaper

  current_mode="$(current_output_mode "${output}")"
  preferred_mode="$(preferred_output_mode "${output}")"

  [[ -n "${current_mode}" ]] || return 0
  [[ -n "${preferred_mode}" ]] || return 0
  [[ "${current_mode}" != "${preferred_mode}" ]] || return 0

  xrandr --output "${output}" --mode "${preferred_mode}" >/dev/null 2>&1 || true
  restart_spice_vdagent
  if [[ -f "${wallpaper_path}" ]] && command -v feh >/dev/null 2>&1; then
    screen_size="$(xrandr --current | awk '/ connected primary/ { split($3, a, "+"); print a[1]; exit } / connected/ { split($3, a, "+"); print a[1]; exit }')"
    screen_width="${screen_size%x*}"
    screen_height="${screen_size#*x}"
    if [[ -n "${screen_width}" ]] && [[ -n "${screen_height}" ]] && command -v convert >/dev/null 2>&1; then
      install -d "${wallpaper_cache_dir}"
      rendered_wallpaper="${wallpaper_cache_dir}/wallpaper-${screen_width}x${screen_height}.png"
      convert "${wallpaper_path}" \
        -resize "x${screen_height}" \
        -gravity center \
        -crop "${screen_width}x${screen_height}+0+0" \
        +repage \
        "${rendered_wallpaper}" >/dev/null 2>&1 || true
      if [[ -f "${rendered_wallpaper}" ]]; then
        feh --bg-center "${rendered_wallpaper}" >/dev/null 2>&1 || true
        return 0
      fi
    fi
    feh --bg-fill "${wallpaper_path}" >/dev/null 2>&1 || true
  fi
}

if ! mkdir "${lock_dir}" 2>/dev/null; then
  exit 0
fi
trap cleanup EXIT

command -v xrandr >/dev/null 2>&1 || exit 0
[[ -n "${DISPLAY:-}" ]] || exit 0
[[ -f "${enable_marker}" ]] || exit 0

while true; do
  output="$(primary_output)"
  if [[ -z "${output}" ]]; then
    output="$(first_connected_output)"
  fi
  if [[ -n "${output}" ]]; then
    apply_layout_if_needed "${output}"
  fi
  sleep "${poll_interval}"
done
