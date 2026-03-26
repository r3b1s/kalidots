#!/usr/bin/env bash
set -euo pipefail

# Cycle border thickness: 0, 1, 2, 4

STATE_FILE="/tmp/i3-border-state"
PRESETS=(0 1 2 4)

focused_workspace_window_ids() {
  i3-msg -t get_tree | jq -r '
    .. | objects
    | select(.type? == "workspace" and .focused == true)
    | .. | objects
    | select(.window? != null)
    | .id
  '
}

apply_border_width() {
  local width="$1"
  local window_id=""

  while IFS= read -r window_id; do
    [[ -n "${window_id}" ]] || continue
    i3-msg "[con_id=${window_id}]" "border pixel ${width}" >/dev/null
  done < <(focused_workspace_window_ids)
}

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
apply_border_width "${next}"
printf '%s' "${next}" > "${STATE_FILE}"
notify-send -t 5000 "Borders" "Border thickness set to ${next}px"
