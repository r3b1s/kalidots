#!/usr/bin/env bash

STAGE_REGISTRY_IDS=()
declare -A STAGE_FILE_BY_ID=()
declare -A STAGE_DESCRIPTION_BY_ID=()
declare -A STAGE_PROFILES_BY_ID=()

reset_stage_contract() {
  unset stage_id || true
  unset stage_description || true
  unset stage_profiles || true
  unset -f stage_apply || true
  unset -f stage_verify || true
}

discover_stage_files() {
  local stage_dir="${BOOTSTRAP_ROOT}/stages"
  local -a stage_files=()

  if [[ ! -d "${stage_dir}" ]]; then
    printf '%s\n' ""
    return 0
  fi

  shopt -s nullglob
  # Discover candidate stage files from bootstrap/stages/*.sh.
  stage_files=("${stage_dir}"/*.sh)
  shopt -u nullglob

  printf '%s\n' "${stage_files[@]}"
}

inspect_stage_metadata() {
  local stage_file="$1"
  local metadata_output

  metadata_output="$(
    BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT}" bash --noprofile --norc -c '
      set -euo pipefail
      stage_id=""
      stage_description=""
      stage_profiles=()
      source "$1"
      printf "%s\t%s\t%s\n" \
        "$stage_id" \
        "$stage_description" \
        "$(IFS=,; printf "%s" "${stage_profiles[*]}")"
    ' bash "${stage_file}"
  )"

  printf '%s\n' "${metadata_output}"
}

register_stage_file() {
  local stage_file="$1"
  local metadata
  local stage_id_local
  local stage_description_local
  local stage_profiles_csv

  metadata="$(inspect_stage_metadata "${stage_file}")"
  IFS=$'\t' read -r stage_id_local stage_description_local stage_profiles_csv <<<"${metadata}"

  if [[ -z "${stage_id_local}" ]]; then
    log_error "Stage file ${stage_file} did not declare stage_id"
    exit 1
  fi

  STAGE_REGISTRY_IDS+=("${stage_id_local}")
  STAGE_FILE_BY_ID["${stage_id_local}"]="${stage_file}"
  STAGE_DESCRIPTION_BY_ID["${stage_id_local}"]="${stage_description_local}"
  STAGE_PROFILES_BY_ID["${stage_id_local}"]="${stage_profiles_csv}"
}

load_stage_registry() {
  local -a stage_files=()
  local stage_file

  STAGE_REGISTRY_IDS=()

  while IFS= read -r stage_file; do
    [[ -n "${stage_file}" ]] || continue
    stage_files+=("${stage_file}")
  done < <(discover_stage_files | sort -V)

  if [[ "${#stage_files[@]}" -eq 0 ]]; then
    return 1
  fi

  for stage_file in "${stage_files[@]}"; do
    register_stage_file "${stage_file}"
  done
}

stage_matches_selected_profiles() {
  local stage_id_local="$1"
  local profile
  local selected_profile
  local profiles_csv="${STAGE_PROFILES_BY_ID[${stage_id_local}]}"
  local -a stage_profiles_local=()

  [[ -n "${profiles_csv}" ]] || return 1
  IFS=',' read -r -a stage_profiles_local <<<"${profiles_csv}"

  for selected_profile in "${SELECTED_PROFILES[@]}"; do
    for profile in "${stage_profiles_local[@]}"; do
      if [[ "${profile}" == "${selected_profile}" ]]; then
        return 0
      fi
    done
  done

  return 1
}

filter_stages_for_profiles() {
  local stage_id_local
  local explicit_stage_id
  local -A explicit_ids=()
  local -a selected_stage_ids=()

  if [[ "${#SELECTED_STAGE_IDS[@]}" -gt 0 ]]; then
    # explicit stage IDs override profile matching even if a stage has no profiles
    for explicit_stage_id in "${SELECTED_STAGE_IDS[@]}"; do
      explicit_ids["${explicit_stage_id}"]=1
    done

    for stage_id_local in "${STAGE_REGISTRY_IDS[@]}"; do
      if [[ -n "${explicit_ids[${stage_id_local}]+x}" ]]; then
        selected_stage_ids+=("${stage_id_local}")
      fi
    done

    for explicit_stage_id in "${SELECTED_STAGE_IDS[@]}"; do
      if [[ -z "${STAGE_FILE_BY_ID[${explicit_stage_id}]+x}" ]]; then
        log_error "Unknown stage ID requested with --stage ID: ${explicit_stage_id}"
        exit 1
      fi
    done

    printf '%s\n' "${selected_stage_ids[@]}"
    return 0
  fi

  for stage_id_local in "${STAGE_REGISTRY_IDS[@]}"; do
    if stage_matches_selected_profiles "${stage_id_local}"; then
      selected_stage_ids+=("${stage_id_local}")
    fi
  done

  printf '%s\n' "${selected_stage_ids[@]}"
}

load_stage_for_execution() {
  local stage_id_local="$1"
  local stage_file="${STAGE_FILE_BY_ID[${stage_id_local}]}"

  reset_stage_contract
  # shellcheck disable=SC1090
  source "${stage_file}"
}

mark_stage_verified() {
  local stage_id_local="$1"
  local profiles_csv="$2"
  state_mark_stage "${stage_id_local}" "verified" "${profiles_csv}" "Stage verification passed"
}

run_selected_stages() {
  local -a selected_stage_ids=()
  local stage_id_local
  local current_status
  local profiles_csv

  if ! load_stage_registry; then
    log_info "No stage files found under bootstrap/stages/*.sh; exiting successfully."
    return 0
  fi

  while IFS= read -r stage_id_local; do
    [[ -n "${stage_id_local}" ]] || continue
    selected_stage_ids+=("${stage_id_local}")
  done < <(filter_stages_for_profiles)

  if [[ "${#selected_stage_ids[@]}" -eq 0 ]]; then
    log_info "No stages selected after profile filtering; exiting successfully."
    return 0
  fi

  state_init
  state_set_run_selection \
    "$(join_by_comma "${SELECTED_PROFILES[@]}")" \
    "$(join_by_comma "${selected_stage_ids[@]}")"

  for stage_id_local in "${selected_stage_ids[@]}"; do
    load_stage_for_execution "${stage_id_local}"
    profiles_csv="$(IFS=,; printf '%s' "${stage_profiles[*]-}")"
    current_status="$(state_get_stage_status "${stage_id_local}")"

    if [[ "${current_status}" == "verified" ]]; then
      log_info "Skipping ${stage_id_local}; already verified."
      continue
    fi

    if [[ "${current_status}" == "verifying" || "${current_status}" == "verify_failed" ]]; then
      log_info "Re-checking ${stage_id_local} before mutating again."
      if stage_verify; then
        mark_stage_verified "${stage_id_local}" "${profiles_csv}"
        continue
      fi

      state_mark_stage "${stage_id_local}" "verify_failed" "${profiles_csv}" \
        "Verification failed before rerun; attempting apply again"
    fi

    state_mark_stage "${stage_id_local}" "applying" "${profiles_csv}" "Applying stage changes"
    stage_apply

    state_mark_stage "${stage_id_local}" "verifying" "${profiles_csv}" "Running stage verification"
    if ! stage_verify; then
      state_mark_stage "${stage_id_local}" "verify_failed" "${profiles_csv}" \
        "Stage verification failed after apply"
      log_error "Stage verification failed for ${stage_id_local}"
      return 1
    fi

    mark_stage_verified "${stage_id_local}" "${profiles_csv}"
  done
}
