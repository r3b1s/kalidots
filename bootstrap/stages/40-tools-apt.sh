#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="tools-apt"
stage_description="Install security tooling apt packages with Kali-first source policy"
stage_profiles=("tools")

TOOLS_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/tools-policy.env"

# shellcheck disable=SC1091
# shellcheck source=../lib/packages.sh
source "${BOOTSTRAP_ROOT}/lib/packages.sh"

stage_apply() {
  PACKAGE_POLICY_FILE="${TOOLS_POLICY_FILE}"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/tools-apt.txt"
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
