#!/usr/bin/env bash
set -euo pipefail

timestamp="$(date +%Y%m%d-%H%M%S)"
output="/tmp/screenshot-${timestamp}.png"

choice="$(
  printf '%s\n' \
    'Fullscreen' \
    'Screenshot Selection' \
    'Screenshot Selection To Clipboard' \
    | rofi -dmenu -i -p "Screenshot" -no-custom
)" || exit 0

case "${choice}" in
  Fullscreen)
    scrot "${output}"
    notify-send "Screenshot Saved" "${output}"
    ;;
  "Screenshot Selection")
    scrot -s "${output}"
    notify-send "Screenshot Saved" "${output}"
    ;;
  "Screenshot Selection To Clipboard")
    scrot -s -f "${output}" -e 'xclip -selection clipboard -t image/png < "$f"'
    notify-send "Screenshot" "Copied selection to clipboard"
    ;;
esac
