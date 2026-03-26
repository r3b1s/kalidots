#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="repos-external"
stage_description="Add external apt repos and install mise, netbird, and tailscale"
stage_profiles=("tools")

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

run_in_target_home() {
  local target_home="$1"
  shift
  runuser -u "${TARGET_USER}" -- env HOME="${target_home}" "$@"
}

choose_vpn_tools() {
  SELECTED_VPN_TOOLS=()

  if command -v gum >/dev/null 2>&1; then
    while IFS= read -r tool_name; do
      [[ -n "${tool_name}" ]] || continue
      SELECTED_VPN_TOOLS+=("${tool_name}")
    done < <(gum choose --no-limit --header "Select VPN tools to install" "netbird" "tailscale")
    return 0
  fi

  printf 'Select VPN tools to install (comma-separated: netbird,tailscale or blank for none): ' >&2
  local answer normalized tool_name
  read -r answer
  normalized="${answer// /}"
  IFS=',' read -r -a SELECTED_VPN_TOOLS <<<"${normalized}"

  for tool_name in "${SELECTED_VPN_TOOLS[@]}"; do
    case "${tool_name}" in
      ""|netbird|tailscale) ;;
      *)
        log_warn "Ignoring unknown VPN selection: ${tool_name}"
        ;;
    esac
  done
}

vpn_tool_selected() {
  local desired_tool="$1"
  local selected_tool

  for selected_tool in "${SELECTED_VPN_TOOLS[@]:-}"; do
    if [[ "${selected_tool}" == "${desired_tool}" ]]; then
      return 0
    fi
  done

  return 1
}

disable_service_if_present() {
  local service_name="$1"

  if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q "^${service_name}\.service"; then
    log_info "Leaving ${service_name}.service installed but disabled"
    systemctl disable --now "${service_name}.service" 2>/dev/null || log_warn "Could not fully disable ${service_name}.service"
  fi
}

add_mise_apt_repo() {
  if apt_package_installed mise; then
    log_info "mise already installed via apt"
    return 0
  fi

  log_info "Adding mise apt repository"
  install -dm 755 /etc/apt/keyrings
  curl -fSs https://mise.jdx.dev/gpg-key.pub | tee /etc/apt/keyrings/mise-archive-keyring.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.jdx.dev/deb stable main" \
    | tee /etc/apt/sources.list.d/mise.list >/dev/null
  apt-get update -y
  apt-get install -y mise
}

setup_mise_globals() {
  local target_home="$1"
  local mise_env="MISE_USE_VERSIONS_HOST=0"

  log_info "Installing global runtimes via mise for ${TARGET_USER}"
  run_in_target_home "${target_home}" env "${mise_env}" mise use --global node@lts
  run_in_target_home "${target_home}" env "${mise_env}" mise use --global python@latest
  log_info "Configuring mise to prefer precompiled Ruby for ${TARGET_USER}"
  run_in_target_home "${target_home}" env "${mise_env}" mise settings set ruby.compile false
  run_in_target_home "${target_home}" env "${mise_env}" mise use --global ruby@latest
}

install_netbird() {
  if command -v netbird >/dev/null 2>&1; then
    log_info "Netbird already installed"
    return 0
  fi

  if ! vpn_tool_selected "netbird"; then
    log_info "Skipping Netbird installation"
    return 0
  fi

  log_info "Adding Netbird apt repository"
  install -dm 755 /etc/apt/keyrings
  curl -fSs https://pkgs.netbird.io/debian/public.key \
    | gpg --dearmor | tee /etc/apt/keyrings/netbird-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main" \
    | tee /etc/apt/sources.list.d/netbird.list >/dev/null
  apt-get update -y
  apt-get install -y netbird netbird-ui
  disable_service_if_present "netbird"
}

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    log_info "Tailscale already installed"
    return 0
  fi

  if ! vpn_tool_selected "tailscale"; then
    log_info "Skipping Tailscale installation"
    return 0
  fi

  log_info "Installing Tailscale static binaries"
  local api_url="https://pkgs.tailscale.com/stable/"
  local tarball_url version tmp_tar tmp_dir

  # Get latest version from stable channel
  tarball_url="$(curl -fSs "${api_url}" | grep -oP 'tailscale_[0-9.]+_amd64\.tgz' | head -1)"
  if [[ -z "${tarball_url}" ]]; then
    log_error "Could not determine latest Tailscale version"
    return 1
  fi

  version="$(printf '%s' "${tarball_url}" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')"

  tmp_tar="$(mktemp)"
  tmp_dir="$(mktemp -d)"
  curl -fSL -o "${tmp_tar}" "${api_url}${tarball_url}"
  tar -xzf "${tmp_tar}" -C "${tmp_dir}" --strip-components=1

  install -m 755 "${tmp_dir}/tailscale" /usr/local/bin/tailscale
  install -m 755 "${tmp_dir}/tailscaled" /usr/local/bin/tailscaled

  # Create systemd unit
  cat > /etc/systemd/system/tailscaled.service <<'UNIT'
[Unit]
Description=Tailscale node agent
After=network-pre.target

[Service]
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

  install -d -m 700 /var/lib/tailscale
  systemctl daemon-reload
  disable_service_if_present "tailscaled"

  rm -rf "${tmp_tar}" "${tmp_dir}"

  register_in_manifest "tailscale" "github:tailscale/tailscale" "static_binary" "/usr/local/bin/tailscale" "${version}"
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/tools-policy.env"
  load_package_policy

  # Mise
  add_mise_apt_repo
  install_user_dir ".bashrc.d"
  install_user_file "${BOOTSTRAP_ROOT}/files/desktop/shell/bashrc.d/50-mise.sh" ".bashrc.d/50-mise.sh"
  setup_mise_globals "${target_home}"

  choose_vpn_tools

  # Netbird
  install_netbird

  # Tailscale
  install_tailscale
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home mise_shims
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  mise_shims="${target_home}/.local/share/mise/shims"

  command -v mise >/dev/null 2>&1 || { log_error "mise not found"; return 1; }
  [[ -f "${target_home}/.bashrc.d/50-mise.sh" ]] || { log_error "mise bashrc drop-in not deployed"; return 1; }

  run_in_target_home "${target_home}" env PATH="${mise_shims}:${PATH}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'command -v node' >/dev/null 2>&1 || { log_error "node not available via mise"; return 1; }
  run_in_target_home "${target_home}" env PATH="${mise_shims}:${PATH}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'command -v python' >/dev/null 2>&1 || { log_error "python not available via mise"; return 1; }
  run_in_target_home "${target_home}" env PATH="${mise_shims}:${PATH}" MISE_USE_VERSIONS_HOST=0 \
    bash -c 'command -v ruby' >/dev/null 2>&1 || { log_error "ruby not available via mise"; return 1; }

  log_info "repos-external stage verified"
  return 0
}
