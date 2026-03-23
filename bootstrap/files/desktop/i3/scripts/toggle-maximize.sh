#!/usr/bin/env bash
set -euo pipefail

# Toggle between normal gaps/borders and zero gaps/borders on focused workspace.
# Uses a state file to track current mode.

STATE_FILE="/tmp/i3-maximize-state"

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

if [[ -f "${STATE_FILE}" ]]; then
  i3-msg "gaps inner current set 8; gaps outer current set 2" >/dev/null
  apply_border_width 2
  rm -f "${STATE_FILE}"
else
  i3-msg "gaps inner current set 0; gaps outer current set 0" >/dev/null
  apply_border_width 0
  touch "${STATE_FILE}"
fi
