#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BOOTSTRAP_ROOT="${ROOT_DIR}/bootstrap"

# shellcheck disable=SC1091
source "${ROOT_DIR}/bootstrap/lib/log.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/bootstrap/lib/state.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/bootstrap/lib/users.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    fail "${message}: expected [${expected}] got [${actual}]"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${message}: missing [${needle}]"
  fi
}

test_prompt_target_username_uses_gum_when_available() {
  local calls_file=""
  local username=""

  calls_file="$(mktemp)"
  gum() {
    printf '%s' "$*" >"${calls_file}"
    printf 'alice\n'
  }

  username="$(prompt_target_username)"

  assert_eq "alice" "${username}" "username prompt should return gum value"
  assert_eq "input --placeholder primary username" "$(cat "${calls_file}")" "username prompt should call gum input with placeholder"
  rm -f "${calls_file}"
}

test_prompt_target_username_falls_back_to_read_and_validates() {
  local output=""
  local stderr=""
  local values_file=""

  BOOTSTRAP_USER="bootstrap"
  stderr="$(mktemp)"
  values_file="$(mktemp)"
  printf '\nbootstrap\n  alice  \n' >"${values_file}"

  prompt_with_fallback() {
    local next_value=""
    next_value="$(head -n 1 "${values_file}")"
    tail -n +2 "${values_file}" >"${values_file}.next"
    mv "${values_file}.next" "${values_file}"
    printf '%s\n' "${next_value}"
  }

  output="$(prompt_target_username 2>"${stderr}")"

  assert_eq "alice" "${output}" "username fallback should trim and accept final value"
  assert_contains "$(cat "${stderr}")" "Primary username cannot be blank." "username fallback should reject blank values"
  assert_contains "$(cat "${stderr}")" "Primary username must differ from bootstrap user bootstrap." "username fallback should reject bootstrap user"
  rm -f "${stderr}"
  rm -f "${values_file}"
  unset -f prompt_with_fallback
}

test_prompt_target_password_falls_back_to_read_secret() {
  local output=""
  local stderr=""
  local values_file=""

  stderr="$(mktemp)"
  values_file="$(mktemp)"
  printf '\nsecret-pass\n' >"${values_file}"

  prompt_with_fallback() {
    local next_value=""
    next_value="$(head -n 1 "${values_file}")"
    tail -n +2 "${values_file}" >"${values_file}.next"
    mv "${values_file}.next" "${values_file}"
    printf '%s\n' "${next_value}"
  }

  output="$(prompt_target_password 2>"${stderr}")"

  assert_eq "secret-pass" "${output}" "password fallback should return accepted password"
  assert_contains "$(cat "${stderr}")" "Primary password cannot be blank." "password fallback should reject blank values"
  rm -f "${stderr}"
  rm -f "${values_file}"
  unset -f prompt_with_fallback
}

test_load_or_prompt_target_user_prefers_state_and_supports_fallback_prompt() {
  local output=""
  local state_write_file=""

  state_write_file="$(mktemp)"

  state_get_value() {
    printf 'null\n'
  }

  json_string() {
    printf '"%s"' "$1"
  }

  state_set_value() {
    printf '%s=%s' "$1" "$2" >"${state_write_file}"
  }

  BOOTSTRAP_USER="bootstrap"
  unset TARGET_USER
  prompt_target_username() {
    printf 'alice\n'
  }

  output="$(load_or_prompt_target_user)"

  assert_eq "alice" "${output}" "load_or_prompt_target_user should prompt successfully without gum"
  assert_eq ".runtime.target_user=\"alice\"" "$(cat "${state_write_file}")" "load_or_prompt_target_user should persist selected target user"

  state_get_value() {
    printf '"stored-user"\n'
  }

  output="$(load_or_prompt_target_user)"
  assert_eq "stored-user" "${output}" "load_or_prompt_target_user should prefer stored state"
  rm -f "${state_write_file}"
  unset -f prompt_target_username
}

main() {
  declare -F prompt_with_fallback >/dev/null || fail "prompt_with_fallback function is missing"
  test_prompt_target_username_uses_gum_when_available
  unset -f gum || true
  test_prompt_target_username_falls_back_to_read_and_validates
  test_prompt_target_password_falls_back_to_read_secret
  test_load_or_prompt_target_user_prefers_state_and_supports_fallback_prompt
  printf 'PASS\n'
}

main "$@"
