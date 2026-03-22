#!/usr/bin/env bash
set -euo pipefail

if xautolock -toggle 2>/dev/null; then
  # xautolock doesn't report state, check if it's responding
  notify-send "Auto-lock" "Toggled"
else
  notify-send "Auto-lock" "xautolock is not running"
fi
