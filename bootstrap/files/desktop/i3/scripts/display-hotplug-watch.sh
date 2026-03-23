#!/usr/bin/env bash
set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/kalidots-display-hotplug-watch.lock"

cleanup() {
  rmdir "${lock_dir}" 2>/dev/null || true
}

apply_layout() {
  sleep 1
  xrandr --auto >/dev/null 2>&1 || true
}

if ! mkdir "${lock_dir}" 2>/dev/null; then
  exit 0
fi
trap cleanup EXIT

command -v xev >/dev/null 2>&1 || exit 0
command -v xrandr >/dev/null 2>&1 || exit 0
[[ -n "${DISPLAY:-}" ]] || exit 0

apply_layout

LC_ALL=C xev -root -event randr 2>/dev/null | while IFS= read -r line; do
  case "${line}" in
    *RRScreenChangeNotifyEvent*|*XRROutputChangeNotifyEvent*|*XRRCrtcChangeNotifyEvent*)
      apply_layout
      ;;
  esac
done
