#!/usr/bin/env bash
set -euo pipefail

CHOICE="$(printf '  Lock\n  Logout\n⏸  Suspend\n  Reboot\n⏻  Shutdown' | rofi -dmenu -i -p "Power")"

case "${CHOICE}" in
  *Lock*)     i3lock ;;
  *Logout*)   i3-msg exit ;;
  *Suspend*)  systemctl suspend ;;
  *Reboot*)   systemctl reboot ;;
  *Shutdown*) systemctl poweroff ;;
esac
