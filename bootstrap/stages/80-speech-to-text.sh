#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="speech-to-text"
stage_description="Install voxtype speech-to-text with ydotool"
stage_profiles=("speech")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

readonly MANIFEST_DIR="${HOME}/.config/kalidots"
readonly MANIFEST_FILE="${MANIFEST_DIR}/update-manifest.json"

register_in_manifest() {
  local name="$1"
  local source="$2"
  local method="$3"
  local binary_path="$4"
  local version="$5"

  [[ -f "${MANIFEST_FILE}" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  jq --arg name "${name}" --arg source "${source}" --arg method "${method}" \
     --arg path "${binary_path}" --arg ver "${version}" \
    '(.tools // []) as $tools |
     if ($tools | map(.name) | index($name)) then
       .tools |= map(if .name == $name then .current_version = $ver else . end)
     else
       .tools += [{"name": $name, "source": $source, "install_method": $method, "binary_path": $path, "current_version": $ver}]
     end' "${MANIFEST_FILE}" > "${tmp}" && mv "${tmp}" "${MANIFEST_FILE}"
}

install_voxtype() {
  if command -v voxtype >/dev/null 2>&1; then
    log_info "voxtype already installed"
    return 0
  fi

  log_info "Installing voxtype from GitHub releases"
  local api_url="https://api.github.com/repos/peteonrails/voxtype/releases/latest"
  local release_json download_url version tmp_deb

  release_json="$(curl -fSs "${api_url}")" || { log_error "Failed to query voxtype releases"; return 1; }
  version="$(printf '%s' "${release_json}" | jq -r '.tag_name')"
  download_url="$(printf '%s' "${release_json}" | jq -r '.assets[] | select(.name | test("\\.deb$")) | .browser_download_url' | head -1)"

  if [[ -z "${download_url}" ]]; then
    log_error "No .deb found in voxtype latest release"
    return 1
  fi

  tmp_deb="$(mktemp --suffix=.deb)"
  curl -fSL -o "${tmp_deb}" "${download_url}" || { rm -f "${tmp_deb}"; return 1; }
  dpkg -i "${tmp_deb}" || apt-get install -fy
  rm -f "${tmp_deb}"

  register_in_manifest "voxtype" "github:peteonrails/voxtype" "deb" "/usr/bin/voxtype" "${version}"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/speech-policy.env"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/speech-apt.txt"
  install_voxtype

  # Deploy voxtype config (hotkey disabled — i3 binding handles toggle)
  install_user_dir ".config/voxtype"
  local tmp_conf
  tmp_conf="$(mktemp)"
  cat > "${tmp_conf}" <<'EOF'
hotkey_enabled = false
EOF
  install_user_file "${tmp_conf}" ".config/voxtype/config.toml"
  rm -f "${tmp_conf}"

  # Download whisper model
  log_info "Downloading whisper tiny.en model for ${TARGET_USER}"
  runuser -u "${TARGET_USER}" -- env HOME="${target_home}" \
    bash -c 'cd "$HOME" && voxtype model download tiny.en' || log_warn "Whisper model download failed; can be retried later"
}

stage_verify() {
  command -v voxtype >/dev/null 2>&1 || { log_error "voxtype not found"; return 1; }
  command -v ydotool >/dev/null 2>&1 || { log_error "ydotool not found"; return 1; }

  load_or_prompt_target_user >/dev/null
  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -f "${target_home}/.config/voxtype/config.toml" ]] || { log_error "voxtype config not deployed"; return 1; }

  log_info "speech-to-text stage verified"
  return 0
}
