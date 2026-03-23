#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/picom"
ACTIVE_CONFIG="${CONFIG_DIR}/picom.conf"
TRANSPARENT_CONFIG="${CONFIG_DIR}/picom-transparent.conf"
OPAQUE_CONFIG="${CONFIG_DIR}/picom-opaque.conf"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/kalidots"
STATE_FILE="${STATE_DIR}/picom-mode"

mkdir -p "${STATE_DIR}"

if [[ ! -f "${TRANSPARENT_CONFIG}" || ! -f "${OPAQUE_CONFIG}" ]]; then
  notify-send "Transparency" "Picom profiles are missing"
  exit 1
fi

current_mode="transparent"
if [[ -f "${STATE_FILE}" ]]; then
  current_mode="$(cat "${STATE_FILE}")"
fi

next_mode="opaque"
next_profile="${OPAQUE_CONFIG}"
if [[ "${current_mode}" == "opaque" ]]; then
  next_mode="transparent"
  next_profile="${TRANSPARENT_CONFIG}"
fi

install -D -m 644 "${next_profile}" "${ACTIVE_CONFIG}"
printf '%s\n' "${next_mode}" > "${STATE_FILE}"

pkill -x picom 2>/dev/null || true
picom --config "${ACTIVE_CONFIG}" -b

notify-send "Transparency" "Window transparency ${next_mode}"
