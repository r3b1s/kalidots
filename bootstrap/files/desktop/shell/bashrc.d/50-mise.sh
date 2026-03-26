# mise - polyglot runtime manager
# Disable anonymous telemetry (download stats to mise-versions.jdx.dev)
export MISE_USE_VERSIONS_HOST=0

# Ensure mise shims are in PATH for non-interactive and scripted use
if [[ -d "${HOME}/.local/share/mise/shims" ]]; then
  export PATH="${HOME}/.local/share/mise/shims:${PATH}"
fi

# Full activation for interactive shells (hooks, auto-switching)
if [[ $- == *i* ]] && command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi
