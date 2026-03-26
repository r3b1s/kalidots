#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="ctf-placeholder"
stage_description="Reserved placeholder stage for future CTF tooling"
stage_profiles=("ctf")

stage_apply() {
  log_info "CTF profile placeholder stage: no changes applied"
}

stage_verify() {
  return 0
}
