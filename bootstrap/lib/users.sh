#!/usr/bin/env bash

# shellcheck disable=SC2034
readonly REQUIRED_GROUPS_FILE="${BOOTSTRAP_ROOT}/files/user/required-groups.txt"
readonly MIGRATION_CHECKLIST_FILE="${BOOTSTRAP_ROOT}/files/user/migration-checklist.txt"

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

json_string() {
  jq -Rn --arg value "$1" '$value'
}

prompt_with_fallback() {
  local prompt_text="$1"
  local placeholder="$2"
  local secret="${3:-no}"
  local value=""

  if command -v gum >/dev/null 2>&1; then
    if [[ "${secret}" == "yes" ]]; then
      value="$(gum input --password --placeholder "${placeholder}")"
    else
      value="$(gum input --placeholder "${placeholder}")"
    fi
  else
    printf '%s: ' "${prompt_text}" >&2
    if [[ "${secret}" == "yes" ]]; then
      IFS= read -rs value
      printf '\n' >&2
    else
      IFS= read -r value
    fi
  fi

  printf '%s\n' "${value}"
}

prompt_target_username() {
  local username=""

  while true; do
    username="$(prompt_with_fallback "Primary username" "primary username")"
    username="$(trim_whitespace "${username}")"

    if [[ -z "${username}" ]]; then
      log_warn "Primary username cannot be blank."
      continue
    fi

    if [[ -n "${BOOTSTRAP_USER:-}" && "${username}" == "${BOOTSTRAP_USER}" ]]; then
      log_warn "Primary username must differ from bootstrap user ${BOOTSTRAP_USER}."
      continue
    fi

    printf '%s\n' "${username}"
    return 0
  done
}

prompt_target_password() {
  local password=""

  while true; do
    password="$(prompt_with_fallback "Primary password" "primary password" "yes")"
    if [[ -z "${password}" ]]; then
      log_warn "Primary password cannot be blank."
      continue
    fi

    printf '%s\n' "${password}"
    return 0
  done
}

load_or_prompt_target_user() {
  local stored_target_user=""

  stored_target_user="$(state_get_value '.runtime.target_user' 2>/dev/null || true)"

  if [[ "${stored_target_user}" != "null" && -n "${stored_target_user}" ]]; then
    TARGET_USER="$(jq -r '.' <<<"${stored_target_user}")"
    printf '%s\n' "${TARGET_USER}"
    return 0
  fi

  if [[ -n "${TARGET_USER:-}" ]]; then
    TARGET_USER="$(trim_whitespace "${TARGET_USER}")"
  else
    TARGET_USER="$(prompt_target_username)"
  fi

  if [[ -z "${TARGET_USER}" ]]; then
    log_error "Target user could not be determined."
    return 1
  fi

  if [[ -n "${BOOTSTRAP_USER:-}" && "${TARGET_USER}" == "${BOOTSTRAP_USER}" ]]; then
    log_error "Target user must differ from bootstrap user ${BOOTSTRAP_USER}."
    return 1
  fi

  state_set_value '.runtime.target_user' "$(json_string "${TARGET_USER}")"
  printf '%s\n' "${TARGET_USER}"
}

create_target_user() {
  local username="$1"
  local password="$2"
  local uid="$3"

  adduser --uid "$uid" --home "/home/$username" --shell /bin/bash --disabled-password --comment "" "$username"
  printf '%s:%s\n' "$username" "$password" | chpasswd
}

ensure_target_groups() {
  local username="$1"
  local groups_file="$2"
  local group_name

  if [[ ! -f "${groups_file}" ]]; then
    log_error "Required groups file not found: ${groups_file}"
    return 1
  fi

  while IFS= read -r group_name || [[ -n "${group_name}" ]]; do
    group_name="$(trim_whitespace "${group_name}")"
    [[ -n "${group_name}" ]] || continue

    if [[ "${group_name}" == "input" ]] && ! getent group input >/dev/null 2>&1; then
      log_info "Skipping optional group input; group does not exist on this system."
      continue
    fi

    if ! getent group "${group_name}" >/dev/null 2>&1; then
      log_warn "Skipping missing group ${group_name}."
      continue
    fi

    adduser "$username" "$group_name" >/dev/null
  done <"${groups_file}"
}

verify_target_user_login() {
  local username="$1"

  # shellcheck disable=SC2016
  runuser --login -u "$username" -- bash -lc 'id && test -w "$HOME" && test "$SHELL" = /bin/bash'
}

verify_migration_checklist() {
  local bootstrap_user="$1"
  local target_user="$2"
  local checklist_file="$3"
  local groups_file="$4"
  local checklist_item
  local group_name
  local inventory_output=""

  if [[ ! -f "${checklist_file}" ]]; then
    log_error "Migration checklist not found: ${checklist_file}"
    return 1
  fi

  while IFS= read -r checklist_item || [[ -n "${checklist_item}" ]]; do
    checklist_item="$(trim_whitespace "${checklist_item}")"
    [[ -n "${checklist_item}" ]] || continue

    case "${checklist_item}" in
      "verify login shell is /bin/bash")
        if [[ "$(getent passwd "${target_user}" | cut -d: -f7)" != "/bin/bash" ]]; then
          log_error "Target user ${target_user} does not have /bin/bash as the login shell."
          return 1
        fi
        ;;
      "verify home directory is writable")
        # shellcheck disable=SC2016
        if ! runuser --login -u "${target_user}" -- bash -lc 'test -w "$HOME"'; then
          log_error "Target user ${target_user} home directory is not writable."
          return 1
        fi
        ;;
      "verify sudo group membership")
        if ! id -nG "${target_user}" | grep -qw sudo; then
          log_error "Target user ${target_user} is not in the sudo group."
          return 1
        fi
        ;;
      "verify required groups from bootstrap/files/user/required-groups.txt")
        while IFS= read -r group_name || [[ -n "${group_name}" ]]; do
          group_name="$(trim_whitespace "${group_name}")"
          [[ -n "${group_name}" ]] || continue

          if [[ "${group_name}" == "input" ]] && ! getent group input >/dev/null 2>&1; then
            continue
          fi

          if ! id -nG "${target_user}" | grep -qw "${group_name}"; then
            log_error "Target user ${target_user} is missing required group ${group_name}."
            return 1
          fi
        done <"${groups_file}"
        ;;
      "inventory files owned by ${BOOTSTRAP_USER} outside /home/${BOOTSTRAP_USER}")
        inventory_output="$(
          find / \
            \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \
            -path "/home/${bootstrap_user}" -prune -o \
            -user "${bootstrap_user}" -print
        )"

        if [[ -n "${inventory_output}" ]]; then
          log_error "Bootstrap user ${bootstrap_user} still owns files outside /home/${bootstrap_user}:"
          printf '%s\n' "${inventory_output}" >&2
          return 1
        fi
        ;;
      *)
        log_error "Unknown migration checklist item: ${checklist_item}"
        return 1
        ;;
    esac
  done <"${checklist_file}"
}

remove_bootstrap_user() {
  deluser --remove-home "$1"
}
