#!/usr/bin/env bash
set -euo pipefail

# Cycle border thickness: 0, 1, 2, 4

STATE_FILE="/tmp/i3-border-state"
PRESETS=(0 1 2 4)

current=2
if [[ -f "${STATE_FILE}" ]]; then
  current="$(cat "${STATE_FILE}")"
fi

next_index=0
for i in "${!PRESETS[@]}"; do
  if [[ "${PRESETS[$i]}" -eq "${current}" ]]; then
    next_index=$(( (i + 1) % ${#PRESETS[@]} ))
    break
  fi
done

next="${PRESETS[$next_index]}"
i3-msg "border pixel ${next}"
printf '%s' "${next}" > "${STATE_FILE}"
notify-send "Borders" "Border thickness set to ${next}px"
