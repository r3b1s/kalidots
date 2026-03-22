#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="system-base"
stage_description="Install bootstrap prerequisites and package policy scaffolding"
stage_profiles=("base")

# shellcheck disable=SC1091
# shellcheck source=../lib/packages.sh
source "${BOOTSTRAP_ROOT}/lib/packages.sh"

stage_apply() {
  load_package_policy

  if [[ "${PACKAGE_POLICY_PLATFORM:-}" != "kali" ]]; then
    log_error "Unsupported package policy platform: ${PACKAGE_POLICY_PLATFORM:-unset}"
    return 1
  fi

  ensure_apt_packages "bootstrap/files/packages/base-apt.txt"
  install -d -m 0755 ./.bootstrap
}

stage_verify() {
  load_package_policy

  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required for system-base verification."
    return 1
  fi

  if ! command -v adduser >/dev/null 2>&1; then
    log_error "adduser is required for system-base verification."
    return 1
  fi

  if ! command -v runuser >/dev/null 2>&1; then
    log_error "runuser is required for system-base verification."
    return 1
  fi

  if ! command -v gum >/dev/null 2>&1; then
    log_error "gum is required for system-base verification."
    return 1
  fi

  if [[ -f "${STATE_FILE}" ]]; then
    if ! jq -e . "${STATE_FILE}" >/dev/null; then
      log_error "State file is not valid JSON: ${STATE_FILE}"
      return 1
    fi
  fi

  if [[ "${PACKAGE_POLICY_ALLOW_EXTERNAL:-}" != "0" ]]; then
    log_error "PACKAGE_POLICY_ALLOW_EXTERNAL must remain 0 for base bootstrap."
    return 1
  fi
}
