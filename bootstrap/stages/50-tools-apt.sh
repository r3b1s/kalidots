#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="tools-apt"
stage_description="Install security tooling apt packages with Kali-first source policy"
stage_profiles=("tools")

TOOLS_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/tools-policy.env"

# shellcheck disable=SC1091
# shellcheck source=../lib/packages.sh
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
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

install_reconftw() {
  load_or_prompt_target_user >/dev/null
  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  if command -v podman >/dev/null 2>&1; then
    log_info "Pulling reconftw container image for ${TARGET_USER}"
    if ! runuser -u "${TARGET_USER}" -- env HOME="${target_home}" XDG_RUNTIME_DIR="/run/user/$(id -u "${TARGET_USER}")" \
      podman pull docker.io/six2dez/reconftw:main; then
      log_warn "reconftw image pull failed; retrying with explicit amd64 platform"
      runuser -u "${TARGET_USER}" -- env HOME="${target_home}" XDG_RUNTIME_DIR="/run/user/$(id -u "${TARGET_USER}")" \
        podman pull --arch amd64 docker.io/six2dez/reconftw:main || log_warn "reconftw image pull failed"
    fi

    cat > /usr/local/bin/reconftw <<'WRAPPER'
#!/usr/bin/env bash
if ! podman image exists docker.io/six2dez/reconftw:main >/dev/null 2>&1; then
  podman pull --arch amd64 docker.io/six2dez/reconftw:main >/dev/null 2>&1 || {
    printf 'reconftw image is unavailable locally and pull failed\n' >&2
    exit 1
  }
fi
exec podman run --rm -it -v "$(pwd):/reconftw/Recon" docker.io/six2dez/reconftw:main "$@"
WRAPPER
    chmod 755 /usr/local/bin/reconftw
  else
    log_warn "podman not available; skipping reconftw container install"
  fi
}

install_opengrep() {
  if [[ -x /usr/local/bin/opengrep ]]; then
    log_info "opengrep already installed"
    return 0
  fi

  log_info "Installing opengrep from GitHub releases"
  local api_url="https://api.github.com/repos/opengrep/opengrep/releases/latest"
  local release_json download_url version tmp_file asset_name

  release_json="$(curl -fSs "${api_url}")" || { log_warn "Failed to query opengrep releases"; return 0; }
  version="$(printf '%s' "${release_json}" | jq -r '.tag_name')"
  asset_name="$(
    printf '%s' "${release_json}" | jq -r '
      .assets[]
      | select(
          (.name | test("(manylinux|linux).*(x86|x86_64|amd64)$"; "i"))
          and (.name | test("\\.(sig|cert)$"; "i") | not)
        )
      | .name
    ' | head -1
  )"
  download_url="$(printf '%s' "${release_json}" | jq -r --arg name "${asset_name}" '.assets[] | select(.name == $name) | .browser_download_url' | head -1)"

  if [[ -z "${download_url}" ]]; then
    log_warn "No opengrep Linux binary found in latest release"
    return 0
  fi

  tmp_file="$(mktemp)"
  curl -fSL -o "${tmp_file}" "${download_url}" || { rm -f "${tmp_file}"; log_warn "opengrep download failed"; return 0; }
  install -m 755 "${tmp_file}" /usr/local/bin/opengrep
  rm -f "${tmp_file}"

  register_in_manifest "opengrep" "github:opengrep/opengrep" "github_binary" "/usr/local/bin/opengrep" "${version}"
}

decompress_rockyou() {
  local rockyou_gz="/usr/share/wordlists/rockyou.txt.gz"
  local rockyou="/usr/share/wordlists/rockyou.txt"

  if [[ -f "${rockyou}" ]]; then
    log_info "rockyou.txt already decompressed"
    return 0
  fi

  if [[ -f "${rockyou_gz}" ]]; then
    log_info "Decompressing rockyou.txt.gz"
    gunzip -k "${rockyou_gz}"
  fi
}

stage_apply() {
  PACKAGE_POLICY_FILE="${TOOLS_POLICY_FILE}"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/tools-apt.txt"

  # Post-apt installs
  install_reconftw
  install_opengrep
  decompress_rockyou
}

stage_verify() {
  PACKAGE_POLICY_FILE="${TOOLS_POLICY_FILE}"
  load_package_policy

  command -v nmap >/dev/null 2>&1 || { log_error "nmap not found"; return 1; }
  command -v gobuster >/dev/null 2>&1 || { log_error "gobuster not found"; return 1; }
  command -v john >/dev/null 2>&1 || { log_error "john not found"; return 1; }
  command -v go >/dev/null 2>&1 || { log_error "go not found"; return 1; }
  command -v rustup >/dev/null 2>&1 || { log_error "rustup not found"; return 1; }

  log_info "tools-apt stage verified"
  return 0
}
