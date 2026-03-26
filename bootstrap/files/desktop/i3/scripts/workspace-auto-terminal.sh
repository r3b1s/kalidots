#!/usr/bin/env bash
set -euo pipefail

# Auto-launch alacritty when the terminal workspace is focused with no windows.
# Subscribes to i3 workspace events; killed and restarted by exec_always.

WS_NAME="⌨️"

# Kill previous instance
SCRIPT_NAME="$(basename "$0")"
pgrep -f "${SCRIPT_NAME}" | grep -v "$$" | xargs -r kill 2>/dev/null || true

i3-msg -t subscribe '["workspace"]' | while read -r event; do
  change="$(printf '%s' "${event}" | jq -r '.change // empty')"
  current="$(printf '%s' "${event}" | jq -r '.current.name // empty')"

  if [[ "${change}" == "focus" && "${current}" == "${WS_NAME}" ]]; then
    # Check if workspace has any child windows
    num_nodes="$(i3-msg -t get_tree | jq --arg ws "${WS_NAME}" '
      .. | select(.type? == "workspace" and .name? == $ws) |
      [.. | select(.window? != null and .window? > 0)] | length
    ')"
    if [[ "${num_nodes}" -eq 0 ]]; then
      alacritty &
      disown
    fi
  fi
done
