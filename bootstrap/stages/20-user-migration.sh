#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="user-migration"
stage_description="Create and verify the target primary user"
stage_profiles=("base")

# shellcheck disable=SC1091
# shellcheck source=../lib/users.sh
source "${BOOTSTRAP_ROOT}/lib/users.sh"

stage_apply() {
  local recorded_target_uid_json="null"
  local recorded_target_uid=""
  local current_uid=""
  local target_uid=10001

  if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
    log_error "BOOTSTRAP_USER must be provided via --bootstrap-user or environment."
    return 1
  fi

  TARGET_USER="$(load_or_prompt_target_user)"

  recorded_target_uid_json="$(state_get_value '.runtime.target_uid' 2>/dev/null || true)"
  if [[ "${recorded_target_uid_json}" != "null" && -n "${recorded_target_uid_json}" ]]; then
    recorded_target_uid="$(jq -r '.' <<<"${recorded_target_uid_json}")"
  fi

  if [[ -n "${recorded_target_uid}" ]]; then
    target_uid="${recorded_target_uid}"
  fi

  state_set_value '.runtime.target_user' "$(json_string "${TARGET_USER}")"
  state_set_value '.runtime.target_uid' "${target_uid}"

  if id "${TARGET_USER}" >/dev/null 2>&1; then
    current_uid="$(id -u "${TARGET_USER}")"

    # resumable state: keep using the recorded target account when UID is stable.
    if [[ -n "${recorded_target_uid}" && "${current_uid}" != "${recorded_target_uid}" ]]; then
      log_error "Existing user ${TARGET_USER} conflicts with recorded target UID ${recorded_target_uid}."
      return 1
    fi

    if [[ "${current_uid}" -le 10000 ]]; then
      log_error "Existing user ${TARGET_USER} has UID ${current_uid}; expected UID greater than 10000."
      return 1
    fi

    ensure_target_groups "${TARGET_USER}" "bootstrap/files/user/required-groups.txt"
    return 0
  fi

  TARGET_PASSWORD="$(prompt_target_password)"
  create_target_user "${TARGET_USER}" "${TARGET_PASSWORD}" "${target_uid}"
  ensure_target_groups "${TARGET_USER}" "bootstrap/files/user/required-groups.txt"
}

stage_verify() {
  if [[ -z "${BOOTSTRAP_USER:-}" ]]; then
    log_error "BOOTSTRAP_USER must be provided via --bootstrap-user or environment."
    return 1
  fi

  TARGET_USER="$(load_or_prompt_target_user)"

  verify_target_user_login "${TARGET_USER}"

  if [[ "$(id -u "$TARGET_USER")" -le 10000 ]]; then
    log_error "Target user ${TARGET_USER} must have a UID greater than 10000."
    return 1
  fi

  if ! id -nG "$TARGET_USER" | grep -qw sudo; then
    log_error "Target user ${TARGET_USER} is not in the sudo group."
    return 1
  fi

  verify_migration_checklist "$BOOTSTRAP_USER" "$TARGET_USER" \
    "bootstrap/files/user/migration-checklist.txt" \
    "bootstrap/files/user/required-groups.txt"
}
