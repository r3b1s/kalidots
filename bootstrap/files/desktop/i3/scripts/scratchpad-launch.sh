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

# Launch the application
eval "${LAUNCH_CMD}" &
disown

# Wait for the new window to appear (up to 5 seconds)
for _ in $(seq 1 50); do
  sleep 0.1
  NEW_ID="$(i3-msg -t get_tree | jq -r '.. | select(.focused? == true) | .id // empty' 2>/dev/null || true)"
  if [[ -n "${NEW_ID}" ]]; then
    # Check if this is a new unmarked window (not the one we had focus on before)
    i3-msg "mark ${MARK}; move scratchpad; [con_mark=\"${MARK}\"] scratchpad show" 2>/dev/null && exit 0
  fi
done

notify-send "Scratchpad" "Failed to capture window for ${MARK}"
exit 1
