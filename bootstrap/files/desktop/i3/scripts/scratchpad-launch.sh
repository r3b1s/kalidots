#!/usr/bin/env bash
set -euo pipefail

# Generic auto-launching scratchpad. Args: <mark> <launch-command...>
# If window with mark exists, toggle scratchpad visibility.
# Otherwise, launch the command, wait for the window, mark it, and show it.

MARK="$1"
shift
LAUNCH_CMD="$*"

# Try to show existing scratchpad window
if i3-msg "[con_mark=\"${MARK}\"]" scratchpad show 2>/dev/null | grep -q '"success":true'; then
  exit 0
fi

# Record existing window IDs so we can detect the new one
BEFORE="$(i3-msg -t get_tree | jq -r '.. | .id? // empty' | sort)"

# Launch the application
eval "${LAUNCH_CMD}" &
disown

# Wait for a new window to appear (up to 5 seconds)
for _ in $(seq 1 50); do
  sleep 0.1
  AFTER="$(i3-msg -t get_tree | jq -r '.. | .id? // empty' | sort)"
  NEW_ID="$(comm -13 <(echo "${BEFORE}") <(echo "${AFTER}") | tail -1)"
  if [[ -n "${NEW_ID}" ]]; then
    i3-msg "[con_id=${NEW_ID}] mark ${MARK}; [con_mark=\"${MARK}\"] move scratchpad; [con_mark=\"${MARK}\"] scratchpad show" 2>/dev/null && exit 0
  fi
done

notify-send "Scratchpad" "Failed to capture window for ${MARK}"
exit 1
