#!/usr/bin/env bash
set -euo pipefail

if command -v i3status-rs >/dev/null 2>&1 && [[ -f "${HOME}/.config/i3status-rust/config.toml" ]]; then
  exec i3status-rs "${HOME}/.config/i3status-rust/config.toml"
fi

if [[ -f "${HOME}/.config/i3status/config" ]]; then
  exec i3status -c "${HOME}/.config/i3status/config"
fi

exec i3status
