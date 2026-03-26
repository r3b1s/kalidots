#!/usr/bin/env bash
set -euo pipefail

# Parse i3 config for bindsym lines and show human-readable keybindings in rofi
CONFIG="${HOME}/.config/i3/config"

grep '^bindsym' "${CONFIG}" \
  | awk '{
      # Strip "bindsym" prefix
      $1 = ""
      sub(/^ +/, "")

      # Separate key combo from action
      key = $1
      $1 = ""
      sub(/^ +/, "")
      action = $0

      # Clean up action
      sub(/^exec --no-startup-id /, "", action)
      sub(/^exec /, "", action)

      # XF86 key translations
      gsub(/XF86AudioLowerVolume/, "Volume -", key)
      gsub(/XF86AudioRaiseVolume/, "Volume +", key)
      gsub(/XF86AudioMute/, "Mute", key)
      gsub(/XF86AudioMicMute/, "Mic Mute", key)
      gsub(/XF86AudioPlay/, "Play/Pause", key)
      gsub(/XF86AudioNext/, "Next Track", key)
      gsub(/XF86AudioPrev/, "Prev Track", key)

      # Modifier translations
      gsub(/\$mod/, "SUPER", key)
      gsub(/Mod4/, "SUPER", key)
      gsub(/Mod1/, "ALT", key)
      gsub(/Shift/, "SHIFT", key)
      gsub(/Ctrl/, "CTRL", key)

      # Capitalize single letter keys at end (a-z after last +)
      n = split(key, parts, "+")
      last = parts[n]
      if (length(last) == 1 && last ~ /[a-z]/) {
        parts[n] = toupper(last)
        key = parts[1]
        for (i = 2; i <= n; i++) key = key "+" parts[i]
      }

      # Space between combo keys
      gsub(/\+/, " + ", key)

      printf "%s → %s\n", key, action
    }' \
  | rofi -dmenu -i -p "Keybindings" -no-custom
