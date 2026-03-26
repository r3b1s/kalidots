#!/usr/bin/env bash
set -euo pipefail

rm -rf "${XDG_RUNTIME_DIR:?}/clipmenu"*
notify-send -t 5000 "Clipboard" "History cleared"
