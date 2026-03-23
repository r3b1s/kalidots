#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BOOTSTRAP_ROOT="${REPO_ROOT}/bootstrap"

# shellcheck source=../../../bootstrap/lib/log.sh
source "${BOOTSTRAP_ROOT}/lib/log.sh"
# shellcheck source=../../../bootstrap/lib/cli.sh
source "${BOOTSTRAP_ROOT}/lib/cli.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    printf 'FAIL: %s\nExpected: %s\nActual:   %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

profile_is_valid "ctf" || {
  printf 'FAIL: ctf should be recognized as a valid profile\n' >&2
  exit 1
}

normalize_selected_profiles base ctf ctf theme
assert_eq "base,ctf,theme" "$(join_by_comma "${NORMALIZED_SELECTED_PROFILES[@]}")" "normalize_selected_profiles should dedupe ctf"

printf 'PASS\n'
