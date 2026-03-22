#!/usr/bin/env bash

STATE_FILE="${STATE_FILE:-./.bootstrap/state.json}"
STATE_SCHEMA_VERSION="1"

_state_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

state_assert_dependencies() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required for state management"
    exit 1
  fi
}

state_assert_json() {
  state_assert_dependencies
  jq -e . "${STATE_FILE}" >/dev/null
}

state_init() {
  local state_dir
  local now

  state_assert_dependencies
  state_dir="$(dirname "${STATE_FILE}")"
  mkdir -p "${state_dir}"

  if [[ -f "${STATE_FILE}" ]]; then
    state_assert_json
    return 0
  fi

  now="$(_state_now)"
  jq -n \
    --arg schema_version "${STATE_SCHEMA_VERSION}" \
    --arg now "${now}" \
    '{
      schema_version: $schema_version,
      created_at: $now,
      updated_at: $now,
      selected_profiles: [],
      selected_stages: [],
      runtime: {},
      stages: {}
    }' >"${STATE_FILE}"
}

state_write_filter() {
  local jq_filter="$1"
  shift

  local tmp_file
  local state_dir

  state_init
  state_dir="$(dirname "${STATE_FILE}")"
  tmp_file="$(mktemp "${state_dir}/state.json.tmp.XXXXXX")"

  if ! jq "$jq_filter" "$@" "${STATE_FILE}" >"${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  mv "${tmp_file}" "${STATE_FILE}"
}

state_set_value() {
  local json_path="$1"
  local json_value="$2"
  local now

  now="$(_state_now)"
  state_write_filter \
    "${json_path} = (${json_value}) | .updated_at = \$now" \
    --arg now "${now}"
}

state_get_value() {
  local json_path="$1"

  state_init
  jq -c "${json_path}" "${STATE_FILE}"
}

state_get_stage_status() {
  local stage_id="$1"

  state_init
  jq -r --arg stage_id "${stage_id}" '.stages[$stage_id].status // "pending"' "${STATE_FILE}"
}

state_set_run_selection() {
  local profiles_csv="$1"
  local stages_csv="$2"
  local now

  now="$(_state_now)"
  state_write_filter '
    .selected_profiles = (
      if $profiles_csv == "" then [] else ($profiles_csv | split(",") | map(select(length > 0))) end
    ) |
    .selected_stages = (
      if $stages_csv == "" then [] else ($stages_csv | split(",") | map(select(length > 0))) end
    ) |
    .updated_at = $now
  ' --arg profiles_csv "${profiles_csv}" --arg stages_csv "${stages_csv}" --arg now "${now}"
}

state_mark_stage() {
  local stage_id="$1"
  local status="$2"
  local profiles_csv="$3"
  local note="$4"
  local now
  local apply_at="null"
  local verify_at="null"

  now="$(_state_now)"

  case "${status}" in
    applying)
      apply_at="\"${now}\""
      ;;
    verifying|verified|verify_failed)
      verify_at="\"${now}\""
      ;;
  esac

  state_write_filter '
    .stages[$stage_id] = (
      (.stages[$stage_id] // {}) +
      {
        status: $status,
        profiles: (
          if $profiles_csv == "" then [] else ($profiles_csv | split(",") | map(select(length > 0))) end
        ),
        note: $note
      } +
      (if $apply_at == null then {} else {last_apply_at: $apply_at} end) +
      (if $verify_at == null then {} else {last_verify_at: $verify_at} end)
    ) |
    .updated_at = $now
  ' \
    --arg stage_id "${stage_id}" \
    --arg status "${status}" \
    --arg profiles_csv "${profiles_csv}" \
    --arg note "${note}" \
    --arg now "${now}" \
    --argjson apply_at "${apply_at}" \
    --argjson verify_at "${verify_at}"
}
