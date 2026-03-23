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

resolve_bootstrap_user_for_cleanup() {
  local stored_bootstrap_user_json="null"
  local stored_bootstrap_user=""

  if [[ -n "${BOOTSTRAP_USER:-}" ]]; then
    printf '%s\n' "${BOOTSTRAP_USER}"
    return 0
  fi

  stored_bootstrap_user_json="$(state_get_value '.runtime.bootstrap_user' 2>/dev/null || true)"
  if [[ "${stored_bootstrap_user_json}" != "null" && -n "${stored_bootstrap_user_json}" ]]; then
    stored_bootstrap_user="$(jq -r '.' <<<"${stored_bootstrap_user_json}")"
  fi

  BOOTSTRAP_USER="$(prompt_with_fallback "Bootstrap user to remove" "${stored_bootstrap_user:-old bootstrap username}")"
  BOOTSTRAP_USER="$(trim_whitespace "${BOOTSTRAP_USER}")"

  if [[ -z "${BOOTSTRAP_USER}" ]]; then
    log_error "Bootstrap user could not be determined."
    return 1
  fi

  printf '%s\n' "${BOOTSTRAP_USER}"
}

stage_apply() {
  local target_user_json="null"
  local target_user=""
  local migration_status=""

  if ! cleanup_stage_explicitly_selected; then
    log_info "Bootstrap user removal is a separate manual cleanup step. Re-run with --stage bootstrap-user-cleanup."
    return 0
  fi

  resolve_bootstrap_user_for_cleanup >/dev/null

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

  resolve_bootstrap_user_for_cleanup >/dev/null

  cleanup_status="$(id "${BOOTSTRAP_USER}" >/dev/null 2>&1; printf '%s' "$?")"
  if [[ "${cleanup_status}" -eq 0 ]]; then
    log_error "Bootstrap user ${BOOTSTRAP_USER} still exists after cleanup."
    return 1
  fi
}
