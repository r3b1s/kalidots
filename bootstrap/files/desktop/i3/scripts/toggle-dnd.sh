#!/usr/bin/env bash
set -euo pipefail

dunstctl set-paused toggle

if [ "$(dunstctl is-paused)" = "true" ]; then
  dunstctl set-paused false
  notify-send -t 5000 "Do Not Disturb" "Enabled"
  sleep 1
  dunstctl set-paused true
else
  notify-send -t 5000 "Do Not Disturb" "Disabled"
fi
