#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="browser-firefox"
stage_description="Configure Firefox profiles, addons, bookmarks, and enterprise policy"
stage_profiles=("desktop")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

readonly -a OPERATOR_ADDONS=(
  flagfox
  multi-account-containers
  foxytab
  foxyproxy-standard
  hack-tools
  hackontext
  privacy-badger17
  user-agent-string-switcher-2
  wappalyzer
  web-archives
  owasp-penetration-testing-kit
)

install_firefox_policy() {
  install -d -m 755 /etc/firefox/policies
  install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/firefox/policies.json" /etc/firefox/policies/policies.json

  if [[ -d /usr/lib/firefox-esr ]]; then
    install -d -m 755 /usr/lib/firefox-esr/distribution
    install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/firefox/policies.json" /usr/lib/firefox-esr/distribution/policies.json
  fi

  if [[ -d /usr/lib/firefox ]]; then
    install -d -m 755 /usr/lib/firefox/distribution
    install -m 644 "${BOOTSTRAP_ROOT}/files/desktop/firefox/policies.json" /usr/lib/firefox/distribution/policies.json
  fi
}

ensure_profiles_ini() {
  local target_home="$1"
  local firefox_root="${target_home}/.mozilla/firefox"
  local profiles_ini="${firefox_root}/profiles.ini"
  local tmp_file

  install_user_dir ".mozilla"
  install_user_dir ".mozilla/firefox"

  if [[ ! -f "${profiles_ini}" ]]; then
    tmp_file="$(mktemp)"
    cat > "${tmp_file}" <<'EOF'
[General]
StartWithLastProfile=1
Version=2
EOF
    install_user_file "${tmp_file}" ".mozilla/firefox/profiles.ini"
    rm -f "${tmp_file}"
  fi
}

register_profile() {
  local target_home="$1"
  local profile_name="$2"
  local is_default="${3:-0}"
  local profiles_ini="${target_home}/.mozilla/firefox/profiles.ini"
  local next_index

  install_user_dir ".mozilla/firefox/${profile_name}"

  if grep -q "^Name=${profile_name}$" "${profiles_ini}" 2>/dev/null; then
    return 0
  fi

  next_index="$(
    awk -F'[][]' '
      /^\[Profile[0-9]+\]$/ {
        gsub(/^Profile/, "", $2)
        if ($2 + 1 > max) { max = $2 + 1 }
      }
      END { print max + 0 }
    ' "${profiles_ini}"
  )"

  cat >> "${profiles_ini}" <<EOF

[Profile${next_index}]
Name=${profile_name}
IsRelative=1
Path=${profile_name}
Default=${is_default}
EOF
  chown "${TARGET_USER}:${TARGET_USER}" "${profiles_ini}"
}

download_addon_xpi() {
  local slug="$1"
  local profile_dir="$2"
  local tmp_xpi tmp_extract addon_id

  log_info "Installing Firefox addon: ${slug}"
  tmp_xpi="$(mktemp --suffix=.xpi)"
  if ! curl -fSL -o "${tmp_xpi}" "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi" 2>/dev/null; then
    log_warn "Failed to download addon ${slug}; skipping"
    rm -f "${tmp_xpi}"
    return 0
  fi

  tmp_extract="$(mktemp -d)"
  unzip -qo "${tmp_xpi}" manifest.json -d "${tmp_extract}" 2>/dev/null || true

  addon_id=""
  if [[ -f "${tmp_extract}/manifest.json" ]]; then
    addon_id="$(jq -r '.browser_specific_settings.gecko.id // .applications.gecko.id // empty' "${tmp_extract}/manifest.json" 2>/dev/null)"
  fi

  if [[ -z "${addon_id}" ]]; then
    log_warn "Could not determine addon ID for ${slug}; skipping"
    rm -f "${tmp_xpi}"
    rm -rf "${tmp_extract}"
    return 0
  fi

  install -d -m 755 "${profile_dir}/extensions"
  install -m 644 "${tmp_xpi}" "${profile_dir}/extensions/${addon_id}.xpi"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${profile_dir}/extensions"

  rm -f "${tmp_xpi}"
  rm -rf "${tmp_extract}"
}

setup_operator_profile() {
  local target_home="$1"
  local profile_dir="${target_home}/.mozilla/firefox/operator"
  local slug

  # Import SecurityBookmarks
  local bookmarks_dir
  bookmarks_dir="$(mktemp -d)"
  if git clone --depth 1 https://github.com/r3b1s/SecurityBookmarks "${bookmarks_dir}" 2>/dev/null; then
    local html_file
    html_file="$(find "${bookmarks_dir}" -maxdepth 2 -name '*.html' -type f | head -1)"
    if [[ -n "${html_file}" ]]; then
      install -m 644 "${html_file}" "${profile_dir}/bookmarks.html"
      chown "${TARGET_USER}:${TARGET_USER}" "${profile_dir}/bookmarks.html"

      # Set user.js to import bookmarks on first launch
      local user_js="${profile_dir}/user.js"
      printf 'user_pref("browser.places.importBookmarksHTML", true);\n' >> "${user_js}"
      chown "${TARGET_USER}:${TARGET_USER}" "${user_js}"
    fi
  fi
  rm -rf "${bookmarks_dir}"

  # Install addons
  for slug in "${OPERATOR_ADDONS[@]}"; do
    download_addon_xpi "${slug}" "${profile_dir}"
  done
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  install_firefox_policy
  ensure_profiles_ini "${target_home}"
  register_profile "${target_home}" "operator" "1"
  register_profile "${target_home}" "regular" "0"
  setup_operator_profile "${target_home}"
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  [[ -f /etc/firefox/policies/policies.json ]] || { log_error "Firefox enterprise policy not installed"; return 1; }
  grep -q '"DisableTelemetry": true' /etc/firefox/policies/policies.json || { log_error "Firefox telemetry policy missing"; return 1; }
  [[ -d "${target_home}/.mozilla/firefox/operator" ]] || { log_error "Firefox operator profile directory not created"; return 1; }
  [[ -d "${target_home}/.mozilla/firefox/regular" ]] || { log_error "Firefox regular profile directory not created"; return 1; }
  [[ -f "${target_home}/.mozilla/firefox/profiles.ini" ]] || { log_error "Firefox profiles.ini missing"; return 1; }
  grep -q '^Name=operator$' "${target_home}/.mozilla/firefox/profiles.ini" || { log_error "Firefox operator profile not registered"; return 1; }
  grep -q '^Name=regular$' "${target_home}/.mozilla/firefox/profiles.ini" || { log_error "Firefox regular profile not registered"; return 1; }
  grep -q '^Default=1$' "${target_home}/.mozilla/firefox/profiles.ini" || { log_error "Operator profile not set as default"; return 1; }
  [[ -d "${target_home}/.mozilla/firefox/operator/extensions" ]] || { log_error "Firefox operator extensions not installed"; return 1; }
  if [[ -d /usr/lib/firefox-esr ]]; then
    [[ -f /usr/lib/firefox-esr/distribution/policies.json ]] || { log_error "Firefox ESR distribution policy missing"; return 1; }
  fi

  log_info "browser-firefox stage verified"
  return 0
}
