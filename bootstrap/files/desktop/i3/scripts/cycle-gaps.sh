#!/usr/bin/env bash
set -euo pipefail

# Cycle through gap presets: 0, 4, 8, 16, 24

STATE_FILE="/tmp/i3-gaps-state"
PRESETS=(0 4 8 16 24)

current=0
if [[ -f "${STATE_FILE}" ]]; then
  current="$(cat "${STATE_FILE}")"
fi

# Find current index and advance
next_index=0
for i in "${!PRESETS[@]}"; do
  if [[ "${PRESETS[$i]}" -eq "${current}" ]]; then
    next_index=$(( (i + 1) % ${#PRESETS[@]} ))
    break
  fi
done

next="${PRESETS[$next_index]}"
i3-msg "gaps inner current set ${next}"
printf '%s' "${next}" > "${STATE_FILE}"
notify-send "Gaps" "Inner gaps set to ${next}px"
