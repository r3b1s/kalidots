#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="desktop-neovim"
stage_description="Install Neovim with LazyVim starter and pixel.nvim colorscheme"
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

  # Deploy pixel.nvim plugin spec
  install_user_dir ".config/nvim/lua/plugins"
  local pixel_spec="${nvim_dir}/lua/plugins/pixel.lua"
  if [[ ! -f "${pixel_spec}" ]] || ! grep -q 'pixel' "${pixel_spec}" 2>/dev/null; then
    cat > "${pixel_spec}" <<'PLUGIN_SPEC'
return {
  {
    "bjarneo/pixel.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("pixel")
    end,
  },
}
PLUGIN_SPEC
    chown "${TARGET_USER}:${TARGET_USER}" "${pixel_spec}"
  fi
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  command -v nvim >/dev/null 2>&1 || { log_error "neovim not found in PATH"; return 1; }
  [[ -f "${target_home}/.config/nvim/init.lua" ]] || { log_error "LazyVim starter not deployed"; return 1; }
  [[ -f "${target_home}/.config/nvim/lua/plugins/pixel.lua" ]] || { log_error "pixel.nvim plugin spec not deployed"; return 1; }
}
