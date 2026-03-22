#!/usr/bin/env bash

PACKAGE_POLICY_FILE="${PACKAGE_POLICY_FILE:-${BOOTSTRAP_ROOT:-.}/files/packages/base-policy.env}"

load_package_policy() {
  if [[ ! -f "${PACKAGE_POLICY_FILE}" ]]; then
    log_error "Package policy file not found: ${PACKAGE_POLICY_FILE}"
    return 1
  fi

  # shellcheck disable=SC1090
  source "${PACKAGE_POLICY_FILE}"
}

apt_package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

ensure_apt_packages() {
  local manifest_path="$1"
  local line
  local package_name
  local apt_updated=false
  local -a missing_packages=()

  if [[ ! -f "${manifest_path}" ]]; then
    log_error "Package manifest not found: ${manifest_path}"
    return 1
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -n "${line}" ]] || continue
    [[ "${line}" == \#* ]] && continue

    package_name="${line}"

    if apt_package_installed "${package_name}"; then
      log_info "Apt package already installed: ${package_name}"
      continue
    fi

    log_info "Apt package queued for install: ${package_name}"
    missing_packages+=("${package_name}")
  done <"${manifest_path}"

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    log_info "All apt packages from ${manifest_path} are already installed."
    return 0
  fi

  if [[ "${apt_updated}" == false ]]; then
    log_info "Running apt-get update before package installation."
    apt-get update
    apt_updated=true
  fi

  log_info "Installing missing apt packages: ${missing_packages[*]}"
  apt-get install -y --no-install-recommends "${missing_packages[@]}"
}
