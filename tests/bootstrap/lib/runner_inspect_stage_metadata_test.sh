#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BOOTSTRAP_ROOT="${REPO_ROOT}/bootstrap"

# shellcheck source=../../../bootstrap/lib/log.sh
source "${BOOTSTRAP_ROOT}/lib/log.sh"
# shellcheck source=../../../bootstrap/lib/cli.sh
source "${BOOTSTRAP_ROOT}/lib/cli.sh"
# shellcheck source=../../../bootstrap/lib/state.sh
source "${BOOTSTRAP_ROOT}/lib/state.sh"
# shellcheck source=../../../bootstrap/lib/runner.sh
source "${BOOTSTRAP_ROOT}/lib/runner.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    printf 'FAIL: %s\nExpected: %s\nActual:   %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_contains_line() {
  local needle="$1"
  local haystack="$2"
  local message="$3"

  if ! grep -Fxq "${needle}" <<<"${haystack}"; then
    printf 'FAIL: %s\nMissing line: %s\n' "${message}" "${needle}" >&2
    exit 1
  fi
}

temp_home="$(mktemp -d)"
trap 'rm -rf "${temp_home}"' EXIT

cat >"${temp_home}/.bash_profile" <<'EOF'
echo "startup-noise-from-bash-profile"
EOF

metadata="$(
  HOME="${temp_home}" inspect_stage_metadata "${BOOTSTRAP_ROOT}/stages/20-user-migration.sh"
)"

assert_eq \
  $'user-migration\tCreate and verify the target primary user\tbase' \
  "${metadata}" \
  "inspect_stage_metadata should ignore login-shell startup output"

load_stage_registry
registry_lines="$(printf '%s\n' "${STAGE_REGISTRY_IDS[@]}")"

assert_contains_line "bootstrap-user-cleanup" "${registry_lines}" "cleanup stage should be registered"
assert_contains_line "ctf-htbtoolkit" "${registry_lines}" "ctf stage should be registered"
assert_contains_line "theme-pink-rot" "${registry_lines}" "theme stage should be registered"

cleanup_line="$(grep -n '^bootstrap-user-cleanup$' <<<"${registry_lines}" | cut -d: -f1)"
ctf_line="$(grep -n '^ctf-htbtoolkit$' <<<"${registry_lines}" | cut -d: -f1)"
theme_line="$(grep -n '^theme-pink-rot$' <<<"${registry_lines}" | cut -d: -f1)"

if (( cleanup_line >= theme_line )); then
  printf 'FAIL: load_stage_registry should preserve numeric stage ordering\ncleanup line: %s\ntheme line: %s\n' \
    "${cleanup_line}" "${theme_line}" >&2
  exit 1
fi

if (( ctf_line >= theme_line )); then
  printf 'FAIL: ctf stage should sort before theme stages\nctf line: %s\ntheme line: %s\n' \
    "${ctf_line}" "${theme_line}" >&2
  exit 1
fi

printf 'PASS\n'
