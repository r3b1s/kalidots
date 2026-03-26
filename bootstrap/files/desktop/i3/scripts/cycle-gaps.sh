#!/usr/bin/env bash
set -euo pipefail

# Cycle through gap presets as inner:outer pairs.

STATE_FILE="/tmp/i3-gaps-state"
PRESETS=("0:0" "4:1" "8:2" "16:4" "24:6")

current="8:2"
if [[ -f "${STATE_FILE}" ]]; then
  current="$(cat "${STATE_FILE}")"
fi

# Find current index and advance
next_index=0
for i in "${!PRESETS[@]}"; do
  if [[ "${PRESETS[$i]}" == "${current}" ]]; then
    next_index=$(( (i + 1) % ${#PRESETS[@]} ))
    break
  fi
done

next="${PRESETS[$next_index]}"
next_inner="${next%%:*}"
next_outer="${next##*:}"

i3-msg "gaps inner current set ${next_inner}; gaps outer current set ${next_outer}" >/dev/null
printf '%s' "${next}" > "${STATE_FILE}"
notify-send -t 5000 "Gaps" "Inner gaps ${next_inner}px, outer gaps ${next_outer}px"
