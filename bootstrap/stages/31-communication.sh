#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="communication"
stage_description="Install communication applications (Discord, Vesktop, Telegram, Element, Signal)"
stage_profiles=("apps")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

install_flatpak_app() {
  local app_id="$1"
  local name="$2"

  if flatpak list --app 2>/dev/null | grep -q "${app_id}"; then
    log_info "${name} already installed via Flatpak"
    return 0
  fi

  log_info "Installing ${name} via Flatpak"
  flatpak install -y flathub "${app_id}" || { log_warn "${name} Flatpak install failed"; return 1; }
}

install_element() {
  if command -v element-desktop >/dev/null 2>&1; then
    log_info "Element already installed"
    return 0
  fi

  log_warn "Element adds an external apt repository (packages.element.io)"
  log_info "Adding Element apt repository"

  install -dm 755 /etc/apt/keyrings
  curl -fSs https://packages.element.io/debian/element-io-archive-keyring.gpg \
    | tee /etc/apt/keyrings/element-io-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" \
    | tee /etc/apt/sources.list.d/element-io.list >/dev/null
  apt-get update -y
  apt-get install -y element-desktop
}

install_signal() {
  if command -v signal-desktop >/dev/null 2>&1; then
    log_info "Signal already installed"
    return 0
  fi

  log_warn "Signal adds an external apt repository (updates.signal.org)"
  log_info "Adding Signal apt repository"

  install -dm 755 /etc/apt/keyrings
  curl -fSs https://updates.signal.org/desktop/apt/keys.asc \
    | gpg --dearmor | tee /etc/apt/keyrings/signal-desktop-keyring.gpg >/dev/null
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" \
    | tee /etc/apt/sources.list.d/signal-desktop.list >/dev/null
  apt-get update -y
  apt-get install -y signal-desktop
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  if ! command -v flatpak >/dev/null 2>&1; then
    log_warn "flatpak not available; Flatpak-based apps will be skipped"
  fi

  local -a options=(
    "Discord (Flatpak)"
    "Vesktop/Vencord (Flatpak)"
    "Telegram (Flatpak)"
    "Element (apt - external repo)"
    "Signal (apt - external repo)"
  )
  local -a choices=()

  if command -v gum >/dev/null 2>&1; then
    mapfile -t choices < <(
      gum choose --no-limit --header "Select communication apps to install" "${options[@]}"
    )
  else
    printf 'Select communication apps (comma-separated):\n' >&2
    local i
    for i in "${!options[@]}"; do
      printf '  %d. %s\n' "$((i + 1))" "${options[i]}" >&2
    done
    printf 'Choice: ' >&2
    local input
    IFS= read -r input
    IFS=',' read -r -a choices <<<"${input}"
  fi

  local choice
  for choice in "${choices[@]}"; do
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    case "${choice}" in
      *Discord*) install_flatpak_app "com.discordapp.Discord" "Discord" ;;
      *Vesktop*|*Vencord*) install_flatpak_app "dev.vencord.Vesktop" "Vesktop" ;;
      *Telegram*) install_flatpak_app "org.telegram.desktop" "Telegram" ;;
      *Element*) install_element ;;
      *Signal*) install_signal ;;
    esac
  done
}

stage_verify() {
  # Communication apps are optional; verify is permissive
  log_info "communication stage verified"
  return 0
}
