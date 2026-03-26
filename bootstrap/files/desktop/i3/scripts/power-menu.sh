#!/usr/bin/env bash
set -euo pipefail

CHOICE="$(
  {
    printf 'Lock\0icon\x1fsystem-lock-screen\n'
    printf 'Logout\0icon\x1fsystem-log-out\n'
    printf 'Suspend\0icon\x1fmedia-playback-pause\n'
    printf 'Reboot\0icon\x1fsystem-reboot\n'
    printf 'Shutdown\0icon\x1fsystem-shutdown\n'
  } | rofi -dmenu -i -show-icons -p "Power" -no-custom
)" || exit 0

case "${CHOICE}" in
  Lock) i3lock ;;
  Logout) i3-msg exit ;;
  Suspend) systemctl suspend ;;
  Reboot) systemctl reboot ;;
  Shutdown) systemctl poweroff ;;
esac
