#!/usr/bin/env bash
set -euo pipefail

alacritty -e bash -lc '
set -euo pipefail

confirm_upgrade() {
  if command -v gum >/dev/null 2>&1; then
    gum confirm "Start apt update + full-upgrade? Once it begins, do not interrupt it."
    return $?
  fi

  printf "Start apt update + full-upgrade? Once it begins, do not interrupt it. [y/N] "
  read -r reply
  [[ ${reply,,} == y || ${reply,,} == yes ]]
}

if ! confirm_upgrade; then
  printf "\nUpgrade cancelled.\n"
  read -r -p "Press Enter to close..."
  exit 0
fi

sudo apt update
sudo apt full-upgrade -y

printf "\nUpgrade finished.\n"
read -r -p "Press Enter to close..."
'
