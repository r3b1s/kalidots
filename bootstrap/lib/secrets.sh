#!/usr/bin/env bash

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/log.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/files/secrets/import-policy.env"

# Default KeePassXC artifact names come from policy: vault.kdbx and vault.key.

get_target_home_or_fail() {
  local target_home

  if [[ -z "${TARGET_USER:-}" ]]; then
    log_error "TARGET_USER is not set."
    return 1
  fi

  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  if [[ -z "${target_home}" ]]; then
    log_error "Could not resolve home directory for ${TARGET_USER}."
    return 1
  fi

  printf '%s\n' "${target_home}"
}

require_secret_source_exists() {
  local source_path="$1"

  if [[ -z "${source_path}" ]]; then
    log_error "Secret source path cannot be blank."
    return 1
  fi

  if [[ ! -e "${source_path}" ]]; then
    log_error "Secret source does not exist: ${source_path}"
    return 1
  fi
}

detect_secret_handler() {
  local source_path="$1"

  require_secret_source_exists "${source_path}" || return 1

  if [[ -f "${source_path}" && "${source_path}" == *.kdbx ]]; then
    printf 'keepassxc-db\n'
    return 0
  fi

  if [[ -d "${source_path}" ]]; then
    printf 'ssh-dir\n'
    return 0
  fi

  log_error "Unsupported secret source type: ${source_path}"
  return 1
}

validate_ssh_private_key_file() {
  local key_path="$1"

  require_secret_source_exists "${key_path}" || return 1
  if [[ ! -f "${key_path}" ]]; then
    log_error "SSH key path is not a file: ${key_path}"
    return 1
  fi

  ssh-keygen -y -f "${key_path}" >/dev/null 2>&1 || {
    log_error "ssh-keygen -y validation failed for ${key_path}"
    return 1
  }
  ssh-keygen -l -f "${key_path}" >/dev/null 2>&1 || {
    log_error "ssh-keygen -l validation failed for ${key_path}"
    return 1
  }
}

normalize_ssh_permissions() {
  local ssh_dir="$1"

  if [[ ! -d "${ssh_dir}" ]]; then
    log_error "SSH destination directory does not exist: ${ssh_dir}"
    return 1
  fi

  chmod 0700 "${ssh_dir}" || return 1
  chown "${TARGET_USER}:${TARGET_USER}" "${ssh_dir}" || return 1

  while IFS= read -r -d '' private_key; do
    chmod 0600 "${private_key}" || return 1
    chown "${TARGET_USER}:${TARGET_USER}" "${private_key}" || return 1
  done < <(find "${ssh_dir}" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print0)

  while IFS= read -r -d '' public_file; do
    chmod 0644 "${public_file}" || return 1
    chown "${TARGET_USER}:${TARGET_USER}" "${public_file}" || return 1
  done < <(find "${ssh_dir}" -maxdepth 1 -type f \( -name '*.pub' -o -name 'config' -o -name 'known_hosts' -o -name 'authorized_keys' \) -print0)
}

import_ssh_directory() {
  local source_dir="$1"
  local target_home="$2"
  local dest_dir
  local file_name

  require_secret_source_exists "${source_dir}" || return 1
  if [[ ! -d "${source_dir}" ]]; then
    log_error "SSH import source is not a directory: ${source_dir}"
    return 1
  fi

  dest_dir="${target_home}/${SSH_DEST_DIR}"
  install -d -m 0700 -o "${TARGET_USER}" -g "${TARGET_USER}" "${dest_dir}" || return 1

  for file_name in config known_hosts authorized_keys; do
    if [[ -f "${source_dir}/${file_name}" ]]; then
      install -m 0644 -o "${TARGET_USER}" -g "${TARGET_USER}" "${source_dir}/${file_name}" "${dest_dir}/${file_name}" || return 1
    fi
  done

  while IFS= read -r -d '' private_key; do
    validate_ssh_private_key_file "${private_key}" || return 1
    install -m 0600 -o "${TARGET_USER}" -g "${TARGET_USER}" "${private_key}" "${dest_dir}/$(basename "${private_key}")" || return 1
  done < <(find "${source_dir}" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print0)

  while IFS= read -r -d '' public_key; do
    install -m 0644 -o "${TARGET_USER}" -g "${TARGET_USER}" "${public_key}" "${dest_dir}/$(basename "${public_key}")" || return 1
  done < <(find "${source_dir}" -maxdepth 1 -type f -name '*.pub' -print0)

  normalize_ssh_permissions "${dest_dir}"
}

import_keepassxc_database() {
  local db_source="$1"
  local keyfile_source="${2:-}"
  local target_home="$3"
  local dest_dir

  require_secret_source_exists "${db_source}" || return 1
  if [[ ! -f "${db_source}" || "${db_source}" != *.kdbx ]]; then
    log_error "KeePassXC source must be a .kdbx file: ${db_source}"
    return 1
  fi

  dest_dir="${target_home}/${KEEPASSXC_DEST_DIR}"
  install -d -m 0700 -o "${TARGET_USER}" -g "${TARGET_USER}" "${dest_dir}" || return 1
  install -m 0600 -o "${TARGET_USER}" -g "${TARGET_USER}" "${db_source}" "${dest_dir}/${KEEPASSXC_DB_NAME}" || return 1

  if [[ -n "${keyfile_source}" ]]; then
    require_secret_source_exists "${keyfile_source}" || return 1
    if [[ ! -f "${keyfile_source}" ]]; then
      log_error "KeePassXC key file source is not a file: ${keyfile_source}"
      return 1
    fi
    install -m 0600 -o "${TARGET_USER}" -g "${TARGET_USER}" "${keyfile_source}" "${dest_dir}/${KEEPASSXC_KEYFILE_NAME}" || return 1
  fi
}
