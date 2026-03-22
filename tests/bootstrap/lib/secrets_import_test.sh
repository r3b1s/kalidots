#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BOOTSTRAP_ROOT="${REPO_ROOT}/bootstrap"

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/secrets.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    printf 'assertion failed: %s\nexpected: %s\nactual: %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_nonzero() {
  local message="$1"
  shift

  if "$@"; then
    printf 'assertion failed: %s\n' "${message}" >&2
    exit 1
  fi
}

assert_file_mode() {
  local expected="$1"
  local path="$2"
  local message="$3"
  local actual

  actual="$(stat -c %a "${path}")"
  assert_eq "${expected}" "${actual}" "${message}"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

touch "${tmpdir}/vault.kdbx"
mkdir -p "${tmpdir}/ssh-dir"
printf 'not a valid ssh key\n' >"${tmpdir}/invalid_id_ed25519"

assert_eq "keepassxc-db" "$(detect_secret_handler "${tmpdir}/vault.kdbx")" "detects keepassxc-db handler"
assert_eq "ssh-dir" "$(detect_secret_handler "${tmpdir}/ssh-dir")" "detects ssh-dir handler"
assert_nonzero "rejects invalid ssh private key material" validate_ssh_private_key_file "${tmpdir}/invalid_id_ed25519"

TARGET_USER="$(id -un)"
mkdir -p "${tmpdir}/source" "${tmpdir}/target-home"
ssh-keygen -q -t ed25519 -N '' -f "${tmpdir}/source/id_valid" >/dev/null
printf 'not a valid ssh key\n' >"${tmpdir}/source/id_invalid"

assert_nonzero "import_ssh_directory fails when any private key is invalid" import_ssh_directory "${tmpdir}/source" "${tmpdir}/target-home"
if [[ -e "${tmpdir}/target-home/.ssh/id_invalid" ]]; then
  printf 'assertion failed: invalid key should not be copied to %s\n' "${tmpdir}/target-home/.ssh/id_invalid" >&2
  exit 1
fi

rm -rf "${tmpdir}/target-home/.ssh"
rm -f "${tmpdir}/source/id_invalid"
import_ssh_directory "${tmpdir}/source" "${tmpdir}/target-home"

chmod 0644 "${tmpdir}/target-home/.ssh/id_valid"
chmod 0755 "${tmpdir}/target-home/.ssh"
normalize_ssh_permissions "${tmpdir}/target-home/.ssh"
assert_file_mode "700" "${tmpdir}/target-home/.ssh" "normalizes ssh directory mode"
assert_file_mode "600" "${tmpdir}/target-home/.ssh/id_valid" "normalizes private key mode"
assert_file_mode "644" "${tmpdir}/target-home/.ssh/id_valid.pub" "normalizes public key mode"

real_chmod_path="$(command -v chmod)"
chmod() {
  if [[ "$#" -ge 2 && "$2" == "${tmpdir}/target-home/.ssh/id_valid" ]]; then
    return 1
  fi
  command "${real_chmod_path}" "$@"
}

assert_nonzero "normalize_ssh_permissions fails when chmod fails" normalize_ssh_permissions "${tmpdir}/target-home/.ssh"
unset -f chmod

normalize_ssh_permissions "${tmpdir}/target-home/.ssh"
assert_file_mode "700" "${tmpdir}/target-home/.ssh" "rerun restores ssh directory mode after failure"
assert_file_mode "600" "${tmpdir}/target-home/.ssh/id_valid" "rerun restores private key mode after failure"
assert_file_mode "644" "${tmpdir}/target-home/.ssh/id_valid.pub" "rerun restores public key mode after failure"

printf 'secrets import helpers ok\n'
