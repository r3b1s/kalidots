#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="note-taking"
stage_description="Install note-taking applications (Obsidian, Joplin, CherryTree)"
stage_profiles=("apps")

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

download_github_appimage() {
  local repo="$1"
  local dest_dir="$2"
  local dest_name="$3"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local release_json download_url version checksum_url

  release_json="$(curl -fSs "${api_url}")" || { log_error "Failed to query ${repo} releases"; return 1; }
  version="$(printf '%s' "${release_json}" | jq -r '.tag_name')"
  download_url="$(printf '%s' "${release_json}" | jq -r '.assets[] | select(.name | test("AppImage$"; "i")) | .browser_download_url' | head -1)"

  if [[ -z "${download_url}" ]]; then
    log_error "No AppImage found in ${repo} latest release"
    return 1
  fi

  log_info "Downloading ${dest_name} ${version} from ${repo}"
  install -d -m 755 "${dest_dir}"

  local tmp_file
  tmp_file="$(mktemp)"
  curl -fSL -o "${tmp_file}" "${download_url}" || { rm -f "${tmp_file}"; return 1; }

  # Try to verify SHA256 if checksum file exists
  checksum_url="$(printf '%s' "${release_json}" | jq -r '.assets[] | select(.name | test("SHA256"; "i")) | .browser_download_url' | head -1)"
  if [[ -n "${checksum_url}" ]]; then
    local checksum_file
    checksum_file="$(mktemp)"
    if curl -fSL -o "${checksum_file}" "${checksum_url}" 2>/dev/null; then
      local expected_hash actual_hash appimage_name
      appimage_name="$(basename "${download_url}")"
      expected_hash="$(grep "${appimage_name}" "${checksum_file}" | awk '{print $1}')"
      actual_hash="$(sha256sum "${tmp_file}" | awk '{print $1}')"
      if [[ -n "${expected_hash}" && "${expected_hash}" != "${actual_hash}" ]]; then
        log_error "SHA256 mismatch for ${dest_name}: expected ${expected_hash}, got ${actual_hash}"
        rm -f "${tmp_file}" "${checksum_file}"
        return 1
      fi
      log_info "SHA256 verified for ${dest_name}"
    fi
    rm -f "${checksum_file}"
  fi

  install -m 755 "${tmp_file}" "${dest_dir}/${dest_name}"
  rm -f "${tmp_file}"

  printf '%s\n' "${version}"
}

install_obsidian() {
  local target_home="$1"
  local version

  version="$(download_github_appimage "obsidianmd/obsidian-releases" "/opt/obsidian" "Obsidian.AppImage")" || return 1

  # Create .desktop file
  cat > /usr/share/applications/obsidian.desktop <<'DESKTOP'
[Desktop Entry]
Name=Obsidian
Comment=Knowledge base and note-taking
Exec=/opt/obsidian/Obsidian.AppImage --no-sandbox %u
Terminal=false
Type=Application
Icon=obsidian
Categories=Office;
MimeType=x-scheme-handler/obsidian;
DESKTOP

  # Deploy default vault
  local vault_dir="${target_home}/notes/obsidian-vault"
  install_user_dir "notes"
  install_user_dir "notes/obsidian-vault"
  if [[ -d "${BOOTSTRAP_ROOT}/files/note-taking/obsidian/default-vault" ]]; then
    cp -r "${BOOTSTRAP_ROOT}/files/note-taking/obsidian/default-vault/." "${vault_dir}/"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${vault_dir}"
  fi

  register_in_manifest "obsidian" "github:obsidianmd/obsidian-releases" "appimage" "/opt/obsidian/Obsidian.AppImage" "${version}"
}

install_joplin() {
  local version

  version="$(download_github_appimage "laurent22/joplin" "/opt/joplin" "Joplin.AppImage")" || return 1

  cat > /usr/share/applications/joplin.desktop <<'DESKTOP'
[Desktop Entry]
Name=Joplin
Comment=Open source note-taking and to-do application
Exec=/opt/joplin/Joplin.AppImage --no-sandbox %u
Terminal=false
Type=Application
Icon=joplin
Categories=Office;
DESKTOP

  register_in_manifest "joplin" "github:laurent22/joplin" "appimage" "/opt/joplin/Joplin.AppImage" "${version}"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  local -a choices=()

  if command -v gum >/dev/null 2>&1; then
    mapfile -t choices < <(
      gum choose --no-limit --header "Select note-taking apps to install" "obsidian" "joplin" "cherrytree"
    )
  else
    printf 'Select note-taking apps (comma-separated: obsidian, joplin, cherrytree): ' >&2
    local input
    IFS= read -r input
    IFS=',' read -r -a choices <<<"${input}"
  fi

  local choice
  for choice in "${choices[@]}"; do
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    case "${choice}" in
      obsidian) install_obsidian "${target_home}" ;;
      joplin) install_joplin ;;
      cherrytree) apt-get install -y cherrytree ;;
    esac
  done
}

stage_verify() {
  # At least one note-taking app should be available
  local found=false
  [[ -x /opt/obsidian/Obsidian.AppImage ]] && found=true
  [[ -x /opt/joplin/Joplin.AppImage ]] && found=true
  command -v cherrytree >/dev/null 2>&1 && found=true

  if [[ "${found}" != "true" ]]; then
    log_warn "No note-taking applications installed (user may have selected none)"
  fi

  log_info "note-taking stage verified"
  return 0
}
