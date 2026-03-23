#!/usr/bin/env bash
set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/kalidots-display-hotplug-watch.lock"
enable_marker="${HOME}/.config/kalidots/qemu-hyprland-screen-resize-fix.enabled"
poll_interval="${DISPLAY_RESIZE_POLL_INTERVAL:-2}"

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

  current_mode="$(current_output_mode "${output}")"
  preferred_mode="$(preferred_output_mode "${output}")"

  [[ -n "${current_mode}" ]] || return 0
  [[ -n "${preferred_mode}" ]] || return 0
  [[ "${current_mode}" != "${preferred_mode}" ]] || return 0

  xrandr --output "${output}" --mode "${preferred_mode}" >/dev/null 2>&1 || true
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
