#!/usr/bin/env bash
set -euo pipefail

rm -rf "${XDG_RUNTIME_DIR:?}/clipmenu"*
notify-send "Clipboard" "History cleared"
