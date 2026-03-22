#!/usr/bin/env bash

install_user_file() {
  local src="$1"
  local dest_rel="$2"   # relative to target user home
  local mode="${3:-644}"
  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  install -D -m "${mode}" -o "${TARGET_USER}" -g "${TARGET_USER}" "${src}" "${target_home}/${dest_rel}"
}

install_user_dir() {
  local dest_rel="$1"
  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  install -d -m 755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${target_home}/${dest_rel}"
}
