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

reload_users_lib() {
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/bootstrap/lib/users.sh"
}

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

test_choose_available_target_uid_uses_preferred_when_free() {
  local chosen_uid=""

  uid_is_available() {
    [[ "$1" == "12345" ]]
  }

  chosen_uid="$(choose_available_target_uid "12345")"
  assert_eq "12345" "${chosen_uid}" "should reuse preferred UID when it is free"

  unset -f uid_is_available
  reload_users_lib
}

test_choose_available_target_uid_retries_until_random_uid_is_free() {
  local chosen_uid=""
  local calls_file=""

  calls_file="$(mktemp)"
  printf '0\n' >"${calls_file}"

  uid_is_available() {
    [[ "$1" == "22222" ]]
  }

  random_target_uid() {
    local random_calls=0
    random_calls="$(cat "${calls_file}")"
    random_calls=$((random_calls + 1))
    printf '%s\n' "${random_calls}" >"${calls_file}"
    case "${random_calls}" in
      1) printf '11111\n' ;;
      2) printf '22222\n' ;;
      *) printf '33333\n' ;;
    esac
  }

  chosen_uid="$(choose_available_target_uid "10001" 2>/dev/null)"

  assert_eq "22222" "${chosen_uid}" "should skip colliding UIDs and return the first available random UID"

  unset -f uid_is_available
  unset -f random_target_uid
  rm -f "${calls_file}"
  reload_users_lib
}

test_random_target_uid_stays_in_expected_range() {
  local uid=""
  local iteration=0

  while (( iteration < 200 )); do
    uid="$(random_target_uid)"
    if (( uid < 10001 || uid >= 64000 )); then
      fail "random_target_uid returned out-of-range value ${uid}"
    fi
    iteration=$((iteration + 1))
  done
}

main() {
  test_choose_available_target_uid_uses_preferred_when_free
  test_choose_available_target_uid_retries_until_random_uid_is_free
  test_random_target_uid_stays_in_expected_range
  printf 'PASS\n'
}

main "$@"
