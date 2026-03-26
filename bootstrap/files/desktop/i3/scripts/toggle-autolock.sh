#!/usr/bin/env bash
set -euo pipefail

STATEFILE="/tmp/i3-autolock-disabled"

if xautolock -toggle 2>/dev/null; then
  if [[ -f "${STATEFILE}" ]]; then
    rm -f "${STATEFILE}"
    notify-send -t 5000 "Auto-lock" "Turned on"
  else
    touch "${STATEFILE}"
    notify-send -t 5000 "Auto-lock" "Turned off"
  fi
else
  notify-send -t 5000 "Auto-lock" "xautolock is not running"
fi
