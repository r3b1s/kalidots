# Prompt configuration: always show current path and git branch.
if [[ $- == *i* ]]; then
  __kalidots_git_branch() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    git branch --show-current 2>/dev/null | awk 'NF { printf " git:%s", $0 }'
  }

  PS1='\w$(__kalidots_git_branch) > '
fi
