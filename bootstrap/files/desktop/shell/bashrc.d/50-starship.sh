# Prompt configuration: always show current path and git branch.
if [[ $- == *i* ]]; then
  if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
  else
    __kalidots_git_branch() {
      git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
      git branch --show-current 2>/dev/null | awk 'NF { printf " git:%s", $0 }'
    }

    PS1='\W$(__kalidots_git_branch) > '
  fi
fi
