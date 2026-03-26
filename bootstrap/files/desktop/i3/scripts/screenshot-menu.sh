#!/usr/bin/env bash
set -euo pipefail

timestamp="$(date +%Y%m%d-%H%M%S)"
output_dir="${HOME}/screenshots"
output="${output_dir}/screenshot-${timestamp}.png"
mode="${1:-menu}"

mkdir -p "${output_dir}"

if [[ "${mode}" == "menu" ]]; then
  choice="$(
    printf '%s\n' \
      'Fullscreen' \
      'Screenshot Selection' \
      'Screenshot Selection To Clipboard' \
      | rofi -dmenu -i -show-icons -p "Screenshot" -no-custom
  )" || exit 0
else
  case "${mode}" in
    fullscreen) choice="Fullscreen" ;;
    selection) choice="Screenshot Selection" ;;
    clipboard) choice="Screenshot Selection To Clipboard" ;;
    *) exit 1 ;;
  esac
fi

case "${choice}" in
  Fullscreen)
    scrot "${output}"
    notify-send -t 5000 "Screenshot Saved" "${output}"
    ;;
  "Screenshot Selection")
    scrot -s "${output}"
    notify-send -t 5000 "Screenshot Saved" "${output}"
    ;;
  "Screenshot Selection To Clipboard")
    scrot -s -f "/tmp/screenshot-${timestamp}.png" -e 'xclip -selection clipboard -t image/png < "$f" && rm -f "$f"'
    notify-send -t 5000 "Screenshot" "Copied selection to clipboard"
    ;;
esac
