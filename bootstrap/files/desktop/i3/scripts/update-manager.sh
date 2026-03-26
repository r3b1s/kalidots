#!/usr/bin/env bash
set -euo pipefail

# Centralized update manager for kalidots
# Handles apt, flatpak, and manifest-tracked GitHub tools

MANIFEST="${HOME}/.config/kalidots/update-manifest.json"
TERM_CMD="${TERMINAL:-alacritty}"

notify() {
  notify-send -t 5000 "Update Manager" "$1" 2>/dev/null || true
}

confirm() {
  local prompt="$1"
  if command -v gum >/dev/null 2>&1; then
    gum confirm "${prompt}"
  else
    printf '%s [y/N]: ' "${prompt}" >&2
    local answer
    read -r answer
    [[ "${answer}" =~ ^[Yy] ]]
  fi
}

update_apt() {
  printf '\n=== APT Updates ===\n'
  sudo apt-get update -y
  local upgradable
  upgradable="$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)"
  if [[ "${upgradable}" -gt 0 ]]; then
    printf '%d packages upgradable\n' "${upgradable}"
    if confirm "Run apt upgrade?"; then
      sudo apt-get upgrade -y
    fi
  else
    printf 'All apt packages up to date.\n'
  fi
}

update_flatpak() {
  if ! command -v flatpak >/dev/null 2>&1; then
    return 0
  fi

  printf '\n=== Flatpak Updates ===\n'
  local updates
  updates="$(flatpak remote-ls --updates 2>/dev/null | wc -l || true)"
  if [[ "${updates}" -gt 0 ]]; then
    printf '%d Flatpak updates available\n' "${updates}"
    if confirm "Update Flatpak apps?"; then
      flatpak update -y
    fi
  else
    printf 'All Flatpak apps up to date.\n'
  fi
}

check_github_tool() {
  local name="$1"
  local source="$2"
  local current_version="$3"
  local repo

  repo="${source#github:}"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local latest_version

  latest_version="$(curl -fSs "${api_url}" 2>/dev/null | jq -r '.tag_name // empty')" || return 1
  if [[ -z "${latest_version}" ]]; then
    return 1
  fi

  if [[ "${latest_version}" != "${current_version}" ]]; then
    printf '%s' "${latest_version}"
  fi
}

update_manifest_tools() {
  if [[ ! -f "${MANIFEST}" ]]; then
    return 0
  fi

  printf '\n=== Manifest-Tracked Tools ===\n'
  local tool_count
  tool_count="$(jq '.tools | length' "${MANIFEST}" 2>/dev/null || echo 0)"
  if [[ "${tool_count}" -eq 0 ]]; then
    printf 'No tools in update manifest.\n'
    return 0
  fi

  local i name source method binary_path current_version latest_version
  local -a outdated_names=()
  local -a outdated_latest=()

  for ((i = 0; i < tool_count; i++)); do
    name="$(jq -r ".tools[${i}].name" "${MANIFEST}")"
    source="$(jq -r ".tools[${i}].source" "${MANIFEST}")"
    current_version="$(jq -r ".tools[${i}].current_version" "${MANIFEST}")"

    printf 'Checking %s... ' "${name}"
    latest_version="$(check_github_tool "${name}" "${source}" "${current_version}" 2>/dev/null)" || {
      printf 'check failed\n'
      continue
    }

    if [[ -n "${latest_version}" ]]; then
      printf 'update available: %s -> %s\n' "${current_version}" "${latest_version}"
      outdated_names+=("${name}")
      outdated_latest+=("${latest_version}")
    else
      printf 'up to date (%s)\n' "${current_version}"
    fi
  done

  if [[ ${#outdated_names[@]} -eq 0 ]]; then
    printf '\nAll manifest tools up to date.\n'
    return 0
  fi

  printf '\n%d tool(s) have updates available.\n' "${#outdated_names[@]}"
  printf 'Manual update required for these tools — re-run the relevant bootstrap stage.\n'

  local j
  for j in "${!outdated_names[@]}"; do
    printf '  - %s -> %s\n' "${outdated_names[j]}" "${outdated_latest[j]}"
  done
}

main() {
  printf '╔══════════════════════════════════╗\n'
  printf '║     kalidots Update Manager      ║\n'
  printf '╚══════════════════════════════════╝\n'

  update_apt
  update_flatpak
  update_manifest_tools

  printf '\n=== Update check complete ===\n'
  printf 'Press Enter to close...'
  read -r
}

main "$@"
