#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="desktop-neovim"
stage_description="Install Neovim with LazyVim starter and non-themed baseline configuration"
stage_profiles=("desktop")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

LAZYVIM_STARTER_URL="https://github.com/LazyVim/starter.git"

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  local nvim_dir="${target_home}/.config/nvim"

  # Clone LazyVim starter (skip if nvim config already exists)
  if [[ ! -d "${nvim_dir}" ]]; then
    log_info "Cloning LazyVim starter config"
    git clone --depth 1 "${LAZYVIM_STARTER_URL}" "${nvim_dir}"
    rm -rf "${nvim_dir}/.git"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${nvim_dir}"
  fi

  local pixel_spec="${nvim_dir}/lua/plugins/pixel.lua"
  local kalidots_theme="${nvim_dir}/lua/plugins/kalidots-theme.lua"
  local kalidots_colorscheme="${nvim_dir}/colors/kalidots.lua"

  if [[ -f "${pixel_spec}" ]]; then
    rm -f "${pixel_spec}"
  fi

  if [[ -f "${kalidots_theme}" ]]; then
    rm -f "${kalidots_theme}"
  fi

  if [[ -f "${kalidots_colorscheme}" ]]; then
    rm -f "${kalidots_colorscheme}"
  fi
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  command -v nvim >/dev/null 2>&1 || { log_error "neovim not found in PATH"; return 1; }
  [[ -f "${target_home}/.config/nvim/init.lua" ]] || { log_error "LazyVim starter not deployed"; return 1; }
  [[ ! -f "${target_home}/.config/nvim/lua/plugins/pixel.lua" ]] || { log_error "stale pixel.nvim plugin spec still present"; return 1; }
  [[ ! -f "${target_home}/.config/nvim/lua/plugins/kalidots-theme.lua" ]] || { log_error "theme-specific kalidots override should not be present in desktop profile"; return 1; }
  [[ ! -f "${target_home}/.config/nvim/colors/kalidots.lua" ]] || { log_error "theme-specific kalidots colorscheme should not be present in desktop profile"; return 1; }
}
