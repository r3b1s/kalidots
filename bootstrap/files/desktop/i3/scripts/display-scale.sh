#!/usr/bin/env bash
set -euo pipefail

# Adjust display scale via xrandr. Args: "in" or "out"

DIRECTION="${1:-in}"
PRIMARY="$(xrandr --query | awk '/ primary/ {print $1}')"
CURRENT="$(xrandr --query | awk "/${PRIMARY}/ {for(i=1;i<=NF;i++) if(\$i ~ /^[0-9]+x[0-9]+\\+/) {print \$i; exit}}")"

# Get current scale (default 1.0)
SCALE="$(xrandr --verbose | awk "/${PRIMARY}/ {found=1} found && /Transform:/ {getline; print \$1; exit}")"
SCALE="${SCALE:-1.0}"

case "${DIRECTION}" in
  in)  NEW_SCALE="$(echo "${SCALE} + 0.1" | bc)" ;;
  out) NEW_SCALE="$(echo "${SCALE} - 0.1" | bc)" ;;
  *)   echo "Usage: $0 {in|out}" >&2; exit 1 ;;
esac

xrandr --output "${PRIMARY}" --scale "${NEW_SCALE}x${NEW_SCALE}"
notify-send "Display Scale" "${NEW_SCALE}x"
