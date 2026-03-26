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

ensure_mise_python_available() {
  local target_home="$1"
  local mise_shims="${target_home}/.local/share/mise/shims"
  local user_path="${mise_shims}:${target_home}/.local/bin:${PATH}"

  if ! command -v mise >/dev/null 2>&1; then
    log_error "mise is not installed; browser-qutebrowser must run after repos-external"
    return 1
  fi

  if ! run_in_target_home "${target_home}" env PATH="${user_path}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'cd "$HOME" && command -v python >/dev/null 2>&1'; then
    log_error "mise-managed python is not available for ${TARGET_USER}; run the tools profile first"
    return 1
  fi
}

get_mise_python_scripts_dir() {
  local target_home="$1"
  local mise_shims="${target_home}/.local/share/mise/shims"
  local user_path="${mise_shims}:${target_home}/.local/bin:${PATH}"

  run_in_target_home "${target_home}" env PATH="${user_path}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'cd "$HOME" && python -c "import sysconfig; print(sysconfig.get_path(\"scripts\"))"'
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  local mise_shims="${target_home}/.local/share/mise/shims"
  local user_path="${mise_shims}:${target_home}/.local/bin:${PATH}"
  local python_scripts_dir
  local user_qutebrowser_bin

  ensure_mise_python_available "${target_home}"
  python_scripts_dir="$(get_mise_python_scripts_dir "${target_home}")"
  user_qutebrowser_bin="${python_scripts_dir}/qutebrowser"

  # Install qutebrowser + dependencies via mise-managed pip
  log_info "Installing qutebrowser via mise-managed python for ${TARGET_USER}"
  run_in_target_home "${target_home}" env PATH="${user_path}" MISE_USE_VERSIONS_HOST=0 \
    bash -c "cd \"\$HOME\" && python -m pip install --upgrade pip && python -m pip uninstall -y PyQt5 PyQtWebEngine >/dev/null 2>&1 || true && python -m pip install qutebrowser PyQt6 PyQt6-WebEngine adblock"

  # Create system wrapper
  cat > /usr/local/bin/qutebrowser <<WRAPPER
#!/usr/bin/env bash
export PATH="${mise_shims}:\${PATH}"
export QT_API=pyqt6
exec "${user_qutebrowser_bin}" "\$@"
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
  local mise_shims
  local python_scripts_dir
  local user_qutebrowser_bin
  local user_path
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  mise_shims="${target_home}/.local/share/mise/shims"
  user_path="${mise_shims}:${target_home}/.local/bin:${PATH}"

  ensure_mise_python_available "${target_home}"
  python_scripts_dir="$(get_mise_python_scripts_dir "${target_home}")"
  user_qutebrowser_bin="${python_scripts_dir}/qutebrowser"

  [[ -x /usr/local/bin/qutebrowser ]] || { log_error "qutebrowser wrapper not installed"; return 1; }
  [[ -f /usr/share/applications/qutebrowser.desktop ]] || { log_error "qutebrowser .desktop file missing"; return 1; }
  [[ -f "${target_home}/.config/qutebrowser/config.py" ]] || { log_error "qutebrowser config not deployed"; return 1; }
  [[ -x "${user_qutebrowser_bin}" ]] || { log_error "qutebrowser user entrypoint not installed"; return 1; }
  run_in_target_home "${target_home}" env PATH="${user_path}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'cd "$HOME" && python -c "import qutebrowser"' >/dev/null 2>&1 \
    || { log_error "qutebrowser package is not importable from mise-managed python"; return 1; }
  run_in_target_home "${target_home}" env PATH="${user_path}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'cd "$HOME" && python -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec(\"PyQt6\") and importlib.util.find_spec(\"PyQt6.QtWebEngineWidgets\") else 1)"' >/dev/null 2>&1 \
    || { log_error "PyQt6 WebEngine is not installed for qutebrowser"; return 1; }

  log_info "browser-qutebrowser stage verified"
  return 0
}
