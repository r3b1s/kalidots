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

manifest_file_path() {
  printf '%s\n' "${HOME}/.config/kalidots/update-manifest.json"
}

register_in_manifest() {
  local name="$1"
  local source="$2"
  local method="$3"
  local binary_path="$4"
  local version="$5"
  local manifest_file

  manifest_file="$(manifest_file_path)"

  [[ -f "${manifest_file}" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  jq --arg name "${name}" --arg source "${source}" --arg method "${method}" \
     --arg path "${binary_path}" --arg ver "${version}" \
    '(.tools // []) as $tools |
     if ($tools | map(.name) | index($name)) then
       .tools |= map(if .name == $name then .current_version = $ver else . end)
     else
       .tools += [{"name": $name, "source": $source, "install_method": $method, "binary_path": $path, "current_version": $ver}]
     end' "${manifest_file}" > "${tmp}" && mv "${tmp}" "${manifest_file}"
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

write_voxtype_config() {
  local target_home="$1"
  local tmp_conf
  local rendered_default=false

  tmp_conf="$(mktemp)"

  if runuser -u "${TARGET_USER}" -- env HOME="${target_home}" \
    bash -c 'cd "$HOME" && voxtype setup --show-config' >"${tmp_conf}" 2>/dev/null; then
    rendered_default=true
  else
    cat > "${tmp_conf}" <<'EOF'
state_file = "auto"

[hotkey]
enabled = false
key = "SCROLLLOCK"

[audio]
device = "default"
sample_rate = 16000
max_duration_secs = 600

[audio.feedback]
enabled = true
theme = "default"
volume = 0.7

[whisper]
model = "tiny.en"
language = "en"
translate = false
on_demand_loading = true

[output]
mode = "type"
fallback_to_clipboard = true
type_delay_ms = 1

[output.notification]
on_recording_start = false
on_recording_stop = false
on_transcription = true
EOF
  fi

  if [[ "${rendered_default}" == "true" ]]; then
    if grep -q '^state_file *= *' "${tmp_conf}"; then
      sed -i 's/^state_file *= *.*/state_file = "auto"/' "${tmp_conf}"
    else
      printf 'state_file = "auto"\n\n%s' "$(cat "${tmp_conf}")" > "${tmp_conf}.new"
      mv "${tmp_conf}.new" "${tmp_conf}"
    fi

    if grep -q '^\[hotkey\]' "${tmp_conf}"; then
      awk '
        BEGIN { in_hotkey = 0; enabled_written = 0 }
        /^\[hotkey\]/ {
          in_hotkey = 1
          print
          next
        }
        /^\[/ {
          if (in_hotkey && !enabled_written) {
            print "enabled = false"
            enabled_written = 1
          }
          in_hotkey = 0
        }
        in_hotkey && /^enabled *= */ {
          if (!enabled_written) {
            print "enabled = false"
            enabled_written = 1
          }
          next
        }
        { print }
        END {
          if (in_hotkey && !enabled_written) {
            print "enabled = false"
          }
        }
      ' "${tmp_conf}" > "${tmp_conf}.new"
      mv "${tmp_conf}.new" "${tmp_conf}"
    else
      cat >> "${tmp_conf}" <<'EOF'

[hotkey]
enabled = false
EOF
    fi
  fi

  install_user_dir ".config/voxtype"
  install_user_file "${tmp_conf}" ".config/voxtype/config.toml"
  rm -f "${tmp_conf}"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/speech-policy.env"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/speech-apt.txt"
  install_voxtype

  # Deploy voxtype config with built-in hotkey disabled; i3 owns the toggle binding.
  write_voxtype_config "${target_home}"

  # Download a default Whisper model non-interactively
  log_info "Downloading whisper tiny.en model for ${TARGET_USER}"
  runuser -u "${TARGET_USER}" -- env HOME="${target_home}" \
    bash -c 'cd "$HOME" && voxtype setup --download --model tiny.en --quiet' \
    || log_warn "Whisper model download failed; retry with: voxtype setup --download --model tiny.en --quiet"
}

stage_verify() {
  command -v voxtype >/dev/null 2>&1 || { log_error "voxtype not found"; return 1; }
  command -v ydotool >/dev/null 2>&1 || { log_error "ydotool not found"; return 1; }

  load_or_prompt_target_user >/dev/null
  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -f "${target_home}/.config/voxtype/config.toml" ]] || { log_error "voxtype config not deployed"; return 1; }
  runuser -u "${TARGET_USER}" -- env HOME="${target_home}" \
    bash -c 'cd "$HOME" && voxtype setup --help >/dev/null 2>&1' \
    || { log_error "voxtype config is invalid or voxtype cannot read it"; return 1; }

  log_info "speech-to-text stage verified"
  return 0
}
