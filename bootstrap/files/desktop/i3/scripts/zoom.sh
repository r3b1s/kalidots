#!/usr/bin/env bash
set -euo pipefail

# Zoom via xrandr scale. Args: "in" or "reset"

ACTION="${1:-in}"
PRIMARY="$(xrandr --query | awk '/ primary/ {print $1}')"

case "${ACTION}" in
  in)
    SCALE="$(xrandr --verbose | awk "/${PRIMARY}/ {found=1} found && /Transform:/ {getline; print \$1; exit}")"
    SCALE="${SCALE:-1.0}"
    NEW_SCALE="$(echo "${SCALE} * 1.25" | bc)"
    xrandr --output "${PRIMARY}" --scale "${NEW_SCALE}x${NEW_SCALE}"
    notify-send -t 5000 "Zoom" "${NEW_SCALE}x"
    ;;
  reset)
    xrandr --output "${PRIMARY}" --scale "1x1"
    notify-send -t 5000 "Zoom" "Reset to 1x"
    ;;
  *)
    echo "Usage: $0 {in|reset}" >&2
    exit 1
    ;;
esac
