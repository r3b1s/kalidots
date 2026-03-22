#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="secrets-import"
stage_description="Import local SSH and KeePassXC material with ownership and permission validation"
stage_profiles=("secrets")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/secrets.sh"

require_path_owner_mode() {
  local target_path="$1"
  local expected_owner="$2"
  local expected_mode="$3"
  local actual_owner
  local actual_mode

  [[ -e "${target_path}" ]] || {
    log_error "Missing expected path: ${target_path}"
    return 1
  }

  actual_mode="$(stat -c %a "${target_path}")"
  actual_owner="$(stat -c %U "${target_path}")"

  [[ "${actual_mode}" == "${expected_mode}" ]] || {
    log_error "Unexpected mode for ${target_path}: ${actual_mode} (expected ${expected_mode})"
    return 1
  }

  [[ "${actual_owner}" == "${expected_owner}" ]] || {
    log_error "Unexpected owner for ${target_path}: ${actual_owner} (expected ${expected_owner})"
    return 1
  }
}

stage_apply() {
  local target_home
  local ssh_source
  local ssh_handler
  local keepass_source
  local keepass_handler
  local keepass_keyfile

  load_or_prompt_target_user >/dev/null
  target_home="$(get_target_home_or_fail)"

  if [[ -n "${SSH_IMPORT_SOURCE+x}" ]]; then
    ssh_source="$(trim_whitespace "${SSH_IMPORT_SOURCE}")"
  else
    ssh_source="$(trim_whitespace "$(prompt_with_fallback "SSH import path" "local ssh directory (blank to skip)")")"
  fi

  if [[ -n "${KEEPASSXC_DB_SOURCE+x}" ]]; then
    keepass_source="$(trim_whitespace "${KEEPASSXC_DB_SOURCE}")"
  else
    keepass_source="$(trim_whitespace "$(prompt_with_fallback "KeePassXC database path" "vault.kdbx path (blank to skip)")")"
  fi

  if [[ -n "${KEEPASSXC_KEYFILE_SOURCE+x}" ]]; then
    keepass_keyfile="$(trim_whitespace "${KEEPASSXC_KEYFILE_SOURCE}")"
  else
    keepass_keyfile="$(trim_whitespace "$(prompt_with_fallback "KeePassXC key file path" "optional key file path (blank to skip)")")"
  fi

  if [[ -n "${ssh_source}" ]]; then
    ssh_handler="$(detect_secret_handler "${ssh_source}")" || return 1
    [[ "${ssh_handler}" == "ssh-dir" ]] || {
      log_error "Unsupported SSH import handler: ${ssh_handler}"
      return 1
    }
    import_ssh_directory "${ssh_source}" "${target_home}"
  fi

  if [[ -n "${keepass_source}" ]]; then
    keepass_handler="$(detect_secret_handler "${keepass_source}")" || return 1
    [[ "${keepass_handler}" == "keepassxc-db" ]] || {
      log_error "Unsupported KeePassXC import handler: ${keepass_handler}"
      return 1
    }
    import_keepassxc_database "${keepass_source}" "${keepass_keyfile:-}" "${target_home}"
  fi
}

stage_verify() {
  local target_home
  local ssh_dir
  local keepass_dir
  local ssh_private_key
  local ssh_public_path

  # Imported KeePassXC artifact names come from policy: vault.kdbx and vault.key.
  load_or_prompt_target_user >/dev/null
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -n "${target_home}" ]] || {
    log_error "Could not resolve home directory for ${TARGET_USER}."
    return 1
  }

  ssh_dir="${target_home}/${SSH_DEST_DIR}"
  if [[ -n "${SSH_IMPORT_SOURCE:-}" || -d "${ssh_dir}" ]]; then
    require_path_owner_mode "${ssh_dir}" "${TARGET_USER}" "700" || return 1

    while IFS= read -r -d '' ssh_private_key; do
      require_path_owner_mode "${ssh_private_key}" "${TARGET_USER}" "600" || return 1
      ssh-keygen -l -f "${ssh_private_key}" >/dev/null 2>&1 || {
        log_error "ssh-keygen -l -f failed for ${ssh_private_key}"
        return 1
      }
    done < <(find "${ssh_dir}" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print0)

    for ssh_public_path in \
      "${ssh_dir}/config" \
      "${ssh_dir}/known_hosts" \
      "${ssh_dir}/authorized_keys"; do
      if [[ -f "${ssh_public_path}" ]]; then
        require_path_owner_mode "${ssh_public_path}" "${TARGET_USER}" "644" || return 1
      fi
    done

    while IFS= read -r -d '' ssh_public_path; do
      require_path_owner_mode "${ssh_public_path}" "${TARGET_USER}" "644" || return 1
    done < <(find "${ssh_dir}" -maxdepth 1 -type f -name '*.pub' -print0)
  fi

  keepass_dir="${target_home}/${KEEPASSXC_DEST_DIR}"
  if [[ -n "${KEEPASSXC_DB_SOURCE:-}" || -f "${keepass_dir}/${KEEPASSXC_DB_NAME}" ]]; then
    require_path_owner_mode "${keepass_dir}/${KEEPASSXC_DB_NAME}" "${TARGET_USER}" "600" || return 1
  fi

  if [[ -f "${keepass_dir}/${KEEPASSXC_KEYFILE_NAME}" ]]; then
    require_path_owner_mode "${keepass_dir}/${KEEPASSXC_KEYFILE_NAME}" "${TARGET_USER}" "600" || return 1
  fi

  return 0
}
