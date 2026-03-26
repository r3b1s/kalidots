#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="browser-qutebrowser"
stage_description="Install qutebrowser via PyPI with mise-managed Python"
stage_profiles=("desktop")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

run_in_target_home() {
  local target_home="$1"
  shift
  runuser -u "${TARGET_USER}" -- env HOME="${target_home}" "$@"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  local mise_shims="${target_home}/.local/share/mise/shims"
  local user_path="${mise_shims}:${target_home}/.local/bin:${PATH}"

  # Install qutebrowser + dependencies via mise-managed pip
  log_info "Installing qutebrowser via pip for ${TARGET_USER}"
  run_in_target_home "${target_home}" env PATH="${user_path}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'cd "$HOME" && pip install qutebrowser PyQtWebEngine adblock'

  # Create system wrapper
  cat > /usr/local/bin/qutebrowser <<WRAPPER
#!/usr/bin/env bash
export PATH="${mise_shims}:\${PATH}"
exec python -m qutebrowser "\$@"
WRAPPER
  chmod 755 /usr/local/bin/qutebrowser

  # Create .desktop file
  cat > /usr/share/applications/qutebrowser.desktop <<'DESKTOP'
[Desktop Entry]
Name=qutebrowser
Comment=A keyboard-driven web browser
Exec=/usr/local/bin/qutebrowser %u
Terminal=false
Type=Application
Icon=qutebrowser
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP

  # Deploy config
  install_user_dir ".config/qutebrowser"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/qutebrowser/config.py" ".config/qutebrowser/config.py"
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  [[ -x /usr/local/bin/qutebrowser ]] || { log_error "qutebrowser wrapper not installed"; return 1; }
  [[ -f /usr/share/applications/qutebrowser.desktop ]] || { log_error "qutebrowser .desktop file missing"; return 1; }
  [[ -f "${target_home}/.config/qutebrowser/config.py" ]] || { log_error "qutebrowser config not deployed"; return 1; }

  log_info "browser-qutebrowser stage verified"
  return 0
}
