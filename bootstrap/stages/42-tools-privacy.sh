#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="tools-privacy"
stage_description="Apply telemetry opt-outs and flag tools with unknown telemetry posture"
stage_profiles=("tools")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/log.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

apply_telemetry_opt_outs() {
  local registry_file="${BOOTSTRAP_ROOT}/files/privacy/telemetry-registry.env"
  local key val status method

  if [[ ! -f "${registry_file}" ]]; then
    log_error "Telemetry registry not found: ${registry_file}"
    return 1
  fi

  while IFS='=' read -r key val || [[ -n "${key}" ]]; do
    key="${key#"${key%%[![:space:]]*}"}"
    [[ -n "${key}" && "${key}" != \#* ]] || continue
    IFS=':' read -r status method <<<"${val}"

    case "${status}" in
      off)
        log_info "Telemetry opt-out to apply: ${key} via ${method}"
        ;;
      off_by_design)
        log_info "Telemetry safe: ${key} (${method})"
        ;;
      unknown)
        log_warn "TELEMETRY UNKNOWN: ${key} - ${method}; flag for manual review"
        ;;
      on)
        log_warn "TELEMETRY ON: ${key} - opt-out not practical; documented as accepted risk"
        ;;
      *)
        log_warn "Unrecognized telemetry status for ${key}: ${status}"
        ;;
    esac
  done <"${registry_file}"
}

ensure_gum_or_prompt_fallback() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$(state_get_value '.runtime.target_user // empty')" != "" ]]; then
    return 0
  fi

  if [[ -n "${TARGET_USER:-}" ]]; then
    return 0
  fi

  if ! command -v gum >/dev/null 2>&1; then
    log_info "gum unavailable; continuing with shell prompt fallback from users.sh"
  fi
}

stage_apply() {
  ensure_gum_or_prompt_fallback
  load_or_prompt_target_user >/dev/null

  apply_telemetry_opt_outs

  if command -v go >/dev/null 2>&1; then
    log_info "Disabling Go toolchain telemetry for ${TARGET_USER}"
    runuser -u "${TARGET_USER}" -- go telemetry off
  fi
}

stage_verify() {
  ensure_gum_or_prompt_fallback
  load_or_prompt_target_user >/dev/null

  if [[ ! -f "${BOOTSTRAP_ROOT}/files/privacy/telemetry-registry.env" ]]; then
    log_error "Telemetry registry file not found"
    return 1
  fi

  if command -v go >/dev/null 2>&1; then
    local go_telemetry
    go_telemetry="$(runuser -u "${TARGET_USER}" -- go telemetry 2>/dev/null || true)"
    if [[ "${go_telemetry}" != *"off"* ]]; then
      log_error "Go telemetry is not disabled"
      return 1
    fi
  fi

  local unknown_count
  unknown_count=$(grep -c '=unknown:' "${BOOTSTRAP_ROOT}/files/privacy/telemetry-registry.env" || true)
  if [[ "${unknown_count}" -gt 0 ]]; then
    log_warn "${unknown_count} tool(s) have unknown telemetry posture (see telemetry-registry.env)"
  fi

  local registry_file="${BOOTSTRAP_ROOT}/files/privacy/telemetry-registry.env"
  local missing=0
  local package_name
  local telemetry_key

  grep -q '^TELEMETRY_GO=' "${registry_file}" || { log_error "Telemetry registry missing Go entry"; return 1; }
  grep -q '^TELEMETRY_GOPLS=' "${registry_file}" || { log_error "Telemetry registry missing gopls entry"; return 1; }
  grep -q '^TELEMETRY_PWNTOOLS=' "${registry_file}" || { log_error "Telemetry registry missing pwntools entry"; return 1; }
  grep -q '^TELEMETRY_BUNDLER=' "${registry_file}" || { log_error "Telemetry registry missing bundler entry"; return 1; }
  grep -q '^TELEMETRY_PAYLOADSALLTHETHINGS=' "${registry_file}" || { log_error "Telemetry registry missing PayloadsAllTheThings entry"; return 1; }

  while IFS= read -r package_name || [[ -n "${package_name}" ]]; do
    package_name="${package_name#"${package_name%%[![:space:]]*}"}"
    package_name="${package_name%"${package_name##*[![:space:]]}"}"
    [[ -n "${package_name}" && "${package_name}" != \#* ]] || continue

    telemetry_key="$(printf '%s' "${package_name}" | tr '[:lower:]-' '[:upper:]_')"
    if ! grep -q "^TELEMETRY_${telemetry_key}=" "${registry_file}"; then
      log_error "Telemetry registry missing package entry for ${package_name}"
      missing=1
    fi
  done < "${BOOTSTRAP_ROOT}/files/packages/tools-apt.txt"

  [[ "${missing}" -eq 0 ]] || return 1

  log_info "tools-privacy stage verified"
}
