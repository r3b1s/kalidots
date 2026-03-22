#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="bootstrap-user-cleanup"
stage_description="Remove the bootstrap user after migration has already been verified"
stage_profiles=()

# shellcheck disable=SC1091
# shellcheck source=../lib/users.sh
source "${BOOTSTRAP_ROOT}/lib/users.sh"

cleanup_stage_explicitly_selected() {
  local selected_stage_id

  for selected_stage_id in "${SELECTED_STAGE_IDS[@]}"; do
    if [[ "${selected_stage_id}" == "bootstrap-user-cleanup" ]]; then
      return 0
    fi
  done

  return 1
}

stage_apply() {
  local target_user_json="null"
  local target_user=""
  local migration_status=""

  if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
    log_error "BOOTSTRAP_USER must be provided via --bootstrap-user or environment."
    return 1
  fi

  if ! cleanup_stage_explicitly_selected; then
    log_info "Bootstrap user removal is a separate manual cleanup step. Re-run with --stage bootstrap-user-cleanup."
    return 0
  fi

  migration_status="$(state_get_stage_status "user-migration")"
  if [[ "${migration_status}" != "verified" ]]; then
    log_error "Cannot remove ${BOOTSTRAP_USER}; user-migration must already be verified."
    return 1
  fi

  target_user_json="$(state_get_value '.runtime.target_user' 2>/dev/null || true)"
  if [[ "${target_user_json}" == "null" || -z "${target_user_json}" ]]; then
    log_error "No recorded target user found in installer state."
    return 1
  fi
  target_user="$(jq -r '.' <<<"${target_user_json}")"

  verify_migration_checklist "${BOOTSTRAP_USER}" "${target_user}" \
    "bootstrap/files/user/migration-checklist.txt" \
    "bootstrap/files/user/required-groups.txt"

  if [[ "${ASSUME_YES:-false}" != "true" ]]; then
    gum confirm "Remove bootstrap user $BOOTSTRAP_USER after verification?"
  fi

  remove_bootstrap_user "$BOOTSTRAP_USER"
}

stage_verify() {
  local cleanup_status

  cleanup_status="$(id "${BOOTSTRAP_USER}" >/dev/null 2>&1; printf '%s' "$?")"
  if [[ "${cleanup_status}" -eq 0 ]]; then
    log_error "Bootstrap user ${BOOTSTRAP_USER} still exists after cleanup."
    return 1
  fi
}
