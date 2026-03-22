#!/usr/bin/env bash
set -euo pipefail

# Toggle between normal gaps/borders and zero gaps/borders on focused workspace.
# Uses a state file to track current mode.

STATE_FILE="/tmp/i3-maximize-state"

if [[ -f "${STATE_FILE}" ]]; then
  i3-msg "gaps inner current set 8; gaps outer current set 2; border pixel 2"
  rm -f "${STATE_FILE}"
else
  i3-msg "gaps inner current set 0; gaps outer current set 0; border pixel 0"
  touch "${STATE_FILE}"
fi
