#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="kanata"
stage_description="Install Kanata keyboard remapper with uinput group, udev rule, and systemd service"
stage_profiles=("keyboard")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/log.sh"

KANATA_BINARY="/usr/local/bin/kanata"
KANATA_CONFIG_DIR="/etc/kanata"
KANATA_LAYOUT="${KANATA_CONFIG_DIR}/layout.kbd"
KANATA_RELEASE_URL="https://github.com/jtroo/kanata/releases/latest/download/kanata"
KANATA_ENTHIUM_REPO="https://github.com/r3b1s/kanata-enthium.git"
KANATA_ENTHIUM_DIR="${KANATA_CONFIG_DIR}/kanata-enthium"

install_kanata_binary() {
  # Prefer apt if available
  if apt-cache show kanata >/dev/null 2>&1; then
    log_info "Installing kanata from apt"
    apt-get install -y kanata
    return 0
  fi

  # Fall back to pre-built binary from GitHub releases
  if [[ -x "${KANATA_BINARY}" ]]; then
    log_info "Kanata binary already present at ${KANATA_BINARY}"
    return 0
  fi

  log_info "Installing kanata from GitHub release (external exception: not in kali-rolling)"
  local tmp_binary
  tmp_binary="$(mktemp)"
  if ! curl -fSL -o "${tmp_binary}" "${KANATA_RELEASE_URL}"; then
    log_error "Failed to download kanata binary from ${KANATA_RELEASE_URL}"
    rm -f "${tmp_binary}"
    return 1
  fi
  install -m 755 "${tmp_binary}" "${KANATA_BINARY}"
  rm -f "${tmp_binary}"
}

setup_uinput_group() {
  # Must be a system group (GID < 1000) for systemd udev to honor the rule
  if ! getent group uinput >/dev/null 2>&1; then
    log_info "Creating uinput system group"
    groupadd --system uinput
  fi
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  # 1. Create uinput system group
  setup_uinput_group

  # 2. Add target user to uinput and input groups
  usermod -aG input,uinput "${TARGET_USER}"

  # 3. Deploy udev rule
  install -m 644 \
    "${BOOTSTRAP_ROOT}/files/systemd/99-kanata-uinput.rules" \
    /etc/udev/rules.d/99-kanata-uinput.rules
  udevadm control --reload-rules
  udevadm trigger

  # 4. Load uinput module persistently
  echo "uinput" > /etc/modules-load.d/uinput.conf

  # 5. Deploy layout file
  mkdir -p "${KANATA_CONFIG_DIR}"

  if [[ -n "${KANATA_LAYOUT_FILE:-}" ]]; then
    # Explicit layout override via env var
    if [[ ! -f "${KANATA_LAYOUT_FILE}" ]]; then
      log_error "Kanata layout source not found: ${KANATA_LAYOUT_FILE}"
      return 1
    fi
    install -m 644 "${KANATA_LAYOUT_FILE}" "${KANATA_LAYOUT}"
  elif [[ "${ASSUME_YES:-}" != "true" ]] && command -v gum >/dev/null 2>&1 \
       && gum confirm "Install kanata-enthium layout from ${KANATA_ENTHIUM_REPO}?"; then
    log_info "Cloning kanata-enthium layout"
    if [[ -d "${KANATA_ENTHIUM_DIR}" ]]; then
      git -C "${KANATA_ENTHIUM_DIR}" pull --ff-only
    else
      git clone "${KANATA_ENTHIUM_REPO}" "${KANATA_ENTHIUM_DIR}"
    fi
    if [[ -f "${KANATA_ENTHIUM_DIR}/enthium.kbd" ]]; then
      ln -sf "${KANATA_ENTHIUM_DIR}/enthium.kbd" "${KANATA_LAYOUT}"
      log_info "Linked kanata-enthium layout to ${KANATA_LAYOUT}"
    else
      log_error "kanata-enthium repo cloned but enthium.kbd not found"
      return 1
    fi
  else
    # Default passthrough layout
    install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/kanata/layout.kbd" "${KANATA_LAYOUT}"
  fi

  # 6. Install kanata binary
  install_kanata_binary

  # 7. Deploy and enable systemd service (layout must exist first)
  install -m 644 "${BOOTSTRAP_ROOT}/files/systemd/kanata.service" \
    /lib/systemd/system/kanata.service
  systemctl daemon-reload
  systemctl enable kanata
}

stage_verify() {
  command -v kanata >/dev/null 2>&1 || { log_error "kanata binary not found in PATH"; return 1; }
  [[ -f "${KANATA_LAYOUT}" ]] || { log_error "kanata layout not deployed at ${KANATA_LAYOUT}"; return 1; }
  getent group uinput >/dev/null 2>&1 || { log_error "uinput group does not exist"; return 1; }

  # Verify uinput is a system group (GID < 1000)
  local uinput_gid
  uinput_gid="$(getent group uinput | cut -d: -f3)"
  if [[ "${uinput_gid}" -ge 1000 ]]; then
    log_error "uinput group GID ${uinput_gid} >= 1000; must be a system group for udev"
    return 1
  fi

  [[ -f /etc/udev/rules.d/99-kanata-uinput.rules ]] || { log_error "uinput udev rule not deployed"; return 1; }
  [[ -f /etc/modules-load.d/uinput.conf ]] || { log_error "uinput module-load config not deployed"; return 1; }
  systemctl is-enabled kanata >/dev/null 2>&1 || { log_error "kanata service not enabled"; return 1; }
}
