#!/usr/bin/env bash
set -euo pipefail

if command -v i3status-rs >/dev/null 2>&1 && [[ -f "${HOME}/.config/i3status-rust/config.toml" ]]; then
  exec i3status-rs "${HOME}/.config/i3status-rust/config.toml"
fi

exec i3status
