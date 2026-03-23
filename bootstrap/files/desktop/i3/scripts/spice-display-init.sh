#!/usr/bin/env bash
set -euo pipefail

# Start the SPICE X11 session agent for i3 and trigger an initial RandR sync.
# Clipboard can work even when display resize has not been initialized cleanly.

if ! command -v spice-vdagent >/dev/null 2>&1; then
  exit 0
fi

if ! pgrep -u "${USER}" -x spice-vdagent >/dev/null 2>&1; then
  spice-vdagent >/dev/null 2>&1 &
  disown || true
fi

# Give X11 and the agent a moment to settle before asking RandR to reprobe.
sleep 1

if command -v xrandr >/dev/null 2>&1; then
  output="$(
    xrandr --query 2>/dev/null | awk '
      / connected primary/ { print $1; exit }
      / connected/ && first == "" { first = $1 }
      END { if (first != "") print first }
    '
  )"

  if [[ -n "${output}" ]]; then
    xrandr --output "${output}" --auto >/dev/null 2>&1 || true
  fi
fi
