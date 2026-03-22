#!/usr/bin/env bash
set -euo pipefail

# Parse i3 config for bindsym lines and show in rofi
CONFIG="${HOME}/.config/i3/config"

grep '^bindsym' "${CONFIG}" \
  | sed 's/bindsym \+//' \
  | sed 's/ exec --no-startup-id / → /' \
  | sed 's/ exec / → /' \
  | sed 's/^\([^ ]*\) \(.*\)/\1 → \2/' \
  | rofi -dmenu -i -p "Keybindings" -no-custom
