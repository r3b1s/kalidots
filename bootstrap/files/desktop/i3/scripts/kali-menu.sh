#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="${HOME}/.config/i3/scripts"
readonly MODE="${1:-main}"
readonly -a MAIN_MENU_LABELS=(
  "Tools"
  "Paths (Term)"
  "Paths (File Explorer)"
  "Update"
  "Screenshot"
)
readonly -a MAIN_MENU_ICONS=(
  "applications-security"
  "utilities-terminal"
  "system-file-manager"
  "system-software-update"
  "applets-screenshooter"
)

desktop_entry_value() {
  local file="$1"
  local key="$2"

  awk -F= -v key="${key}" '
    BEGIN { in_entry = 0 }
    /^\[Desktop Entry\]$/ { in_entry = 1; next }
    /^\[/ && $0 != "[Desktop Entry]" { in_entry = 0 }
    in_entry && $1 == key {
      sub(/^[^=]*=/, "", $0)
      print
      exit
    }
  ' "${file}"
}

desktop_entry_hidden() {
  local file="$1"
  local hidden
  local nodisplay

  hidden="$(desktop_entry_value "${file}" "Hidden")"
  nodisplay="$(desktop_entry_value "${file}" "NoDisplay")"
  [[ "${hidden}" == "true" || "${nodisplay}" == "true" ]]
}

launch_desktop_entry() {
  local desktop_file="$1"
  setsid -f gio launch "${desktop_file}" >/dev/null 2>&1 || true
}

rofi_pick_index() {
  local prompt="$1"
  local labels_ref="$2"
  local icons_ref="$3"
  local -n labels="${labels_ref}"
  local -n icons="${icons_ref}"
  local i
  local choice

  [[ ${#labels[@]} -gt 0 ]] || return 1

  choice="$(
    for i in "${!labels[@]}"; do
      printf '%s' "${labels[i]}"
      if [[ -n "${icons[i]:-}" ]]; then
        printf '\0icon\x1f%s' "${icons[i]}"
      fi
      printf '\n'
    done | rofi -dmenu -i -show-icons -format i -p "${prompt}" -no-custom
  )" || return 1

  [[ -n "${choice}" ]] || return 1
  printf '%s\n' "${choice}"
}

icon_or_default() {
  local icon="${1:-}"
  local fallback="$2"

  if [[ -n "${icon}" ]]; then
    printf '%s\n' "${icon}"
  else
    printf '%s\n' "${fallback}"
  fi
}

find_kali_menu_file() {
  local candidate
  local -a candidates=(
    "/etc/xdg/menus/applications-merged/kali-applications.menu"
    "/etc/xdg/menus/kali-applications.menu"
    "/usr/share/applications/kali-applications.menu"
  )

  for candidate in "${candidates[@]}"; do
    [[ -f "${candidate}" ]] && printf '%s\n' "${candidate}" && return 0
  done

  return 1
}

find_directory_file() {
  local filename="$1"
  local candidate
  local -a bases=(
    "/usr/share/desktop-directories"
    "/usr/local/share/desktop-directories"
  )

  for candidate in "${bases[@]}"; do
    if [[ -f "${candidate}/${filename}" ]]; then
      printf '%s\n' "${candidate}/${filename}"
      return 0
    fi
  done

  return 1
}

directory_name_for_file() {
  local file="$1"
  local name

  name="$(desktop_entry_value "${file}" "Name")"
  printf '%s\n' "${name#• }"
}

directory_icon_for_file() {
  local file="$1"

  desktop_entry_value "${file}" "Icon"
}

parse_top_categories() {
  local menu_file="$1"

  awk '
    /<Menu>/ { depth++; next }
    /<\/Menu>/ {
      if (depth == 2 && name[depth] != "Usual Applications") {
        cats = categories[depth]
        sub(/,+$/, "", cats)
        if (cats == "") cats = "_none_"
        print name[depth] "\t" directory[depth] "\t" cats
      }
      delete name[depth]
      delete directory[depth]
      delete categories[depth]
      depth--
      next
    }
    /<Name>/ {
      line = $0
      sub(/^.*<Name>/, "", line)
      sub(/<\/Name>.*$/, "", line)
      gsub(/&amp;/, "\\&", line)
      name[depth] = line
    }
    /<Directory>/ {
      line = $0
      sub(/^.*<Directory>/, "", line)
      sub(/<\/Directory>.*$/, "", line)
      directory[depth] = line
    }
    /<Category>/ {
      line = $0
      sub(/^.*<Category>/, "", line)
      sub(/<\/Category>.*$/, "", line)
      if (categories[depth] != "") categories[depth] = categories[depth] ","
      categories[depth] = categories[depth] line
    }
  ' "${menu_file}"
}

parse_subcategories() {
  local menu_file="$1"
  local parent_name="$2"

  awk -v parent="${parent_name}" '
    /<Menu>/ { depth++; next }
    /<\/Menu>/ {
      if (depth == 3 && name[2] == parent && name[depth] != "") {
        cats = categories[depth]
        sub(/,+$/, "", cats)
        if (cats == "") cats = "_none_"
        print name[depth] "\t" directory[depth] "\t" cats
      }
      delete name[depth]
      delete directory[depth]
      delete categories[depth]
      depth--
      next
    }
    /<Name>/ {
      line = $0
      sub(/^.*<Name>/, "", line)
      sub(/<\/Name>.*$/, "", line)
      gsub(/&amp;/, "\\&", line)
      name[depth] = line
    }
    /<Directory>/ {
      line = $0
      sub(/^.*<Directory>/, "", line)
      sub(/<\/Directory>.*$/, "", line)
      directory[depth] = line
    }
    /<Category>/ {
      line = $0
      sub(/^.*<Category>/, "", line)
      sub(/<\/Category>.*$/, "", line)
      if (categories[depth] != "") categories[depth] = categories[depth] ","
      categories[depth] = categories[depth] line
    }
  ' "${menu_file}"
}

find_desktop_entries_by_categories() {
  local -a cats=("$@")
  local cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}/kalidots"
  local cache_file="${cache_root}/desktop-entry-cache.tsv"
  local -a desktop_files=()
  local cat_regex

  mkdir -p "${cache_root}"
  mapfile -t desktop_files < <(find /usr/share/applications /usr/local/share/applications -maxdepth 1 -type f -name '*.desktop' 2>/dev/null | sort)
  [[ ${#desktop_files[@]} -gt 0 ]] || return 0

  if [[ ! -f "${cache_file}" ]] || find /usr/share/applications /usr/local/share/applications -maxdepth 1 -type f -name '*.desktop' -newer "${cache_file}" 2>/dev/null | grep -q .; then
    awk -F= '
      function flush_entry() {
        if (file != "" && in_entry == 1 && name != "" && hidden != "true" && nodisplay != "true") {
          printf "%s\t%s\t%s\t%s\n", name, icon, file, categories
        }
      }
      FNR == 1 {
        flush_entry()
        file = FILENAME
        in_entry = 0
        name = ""
        icon = ""
        categories = ""
        hidden = "false"
        nodisplay = "false"
      }
      /^\[Desktop Entry\]$/ { in_entry = 1; next }
      /^\[/ && $0 != "[Desktop Entry]" { in_entry = 0 }
      in_entry && $1 == "Name" { sub(/^[^=]*=/, "", $0); name = $0; next }
      in_entry && $1 == "Icon" { sub(/^[^=]*=/, "", $0); icon = $0; next }
      in_entry && $1 == "Categories" { sub(/^[^=]*=/, "", $0); categories = $0; next }
      in_entry && $1 == "Hidden" { sub(/^[^=]*=/, "", $0); hidden = $0; next }
      in_entry && $1 == "NoDisplay" { sub(/^[^=]*=/, "", $0); nodisplay = $0; next }
      END { flush_entry() }
    ' "${desktop_files[@]}" 2>/dev/null | sort -t $'\t' -k1,1f > "${cache_file}"
  fi

  cat_regex="$(printf '%s\n' "${cats[@]}" | paste -sd'|' -)"
  awk -F'\t' -v regex="(^|;)(${cat_regex})(;|$)" '$4 ~ regex { print $1 "\t" $2 "\t" $3 }' "${cache_file}"
}

show_app_list() {
  local prompt="$1"
  shift
  local -a cats=("$@")
  local -a app_rows=()
  local -a labels=()
  local -a icons=()
  local -a desktop_files=()
  local row
  local idx
  local label
  local icon
  local desktop_file

  mapfile -t app_rows < <(find_desktop_entries_by_categories "${cats[@]}" | sort -t $'\t' -k1,1f)
  [[ ${#app_rows[@]} -gt 0 ]] || {
    notify-send -t 5000 "Kali Tools" "No launchers found for ${prompt}"
    return 0
  }

  for row in "${app_rows[@]}"; do
    IFS=$'\t' read -r label icon desktop_file <<<"${row}"
    labels+=("${label}")
    icons+=("$(icon_or_default "${icon}" "application-x-executable")")
    desktop_files+=("${desktop_file}")
  done

  idx="$(rofi_pick_index "${prompt}" labels icons)" || return 0
  launch_desktop_entry "${desktop_files[idx]}"
}

show_category_tools() {
  local menu_file="$1"
  local category_name="$2"
  local category_directory="$3"
  local category_categories="$4"
  local category_icon
  local category_directory_file
  local -a sub_rows=()
  local -a labels=()
  local -a icons=()
  local -a sub_categories=()
  local row
  local idx
  local sub_name
  local sub_directory
  local sub_cats
  local sub_directory_file
  local sub_icon

  category_directory_file="$(find_directory_file "${category_directory}")" || {
    notify-send -t 5000 "Kali Tools" "Missing directory metadata for ${category_name}"
    return 0
  }
  category_icon="$(directory_icon_for_file "${category_directory_file}")"

  mapfile -t sub_rows < <(parse_subcategories "${menu_file}" "${category_name}")
  if [[ ${#sub_rows[@]} -eq 0 ]]; then
    IFS=',' read -r -a _cats <<<"${category_categories}"
    show_app_list "${category_name}" "${_cats[@]}"
    return 0
  fi

  labels=("All Tools")
  icons=("${category_icon}")
  sub_categories=("${category_categories}")

  for row in "${sub_rows[@]}"; do
    IFS=$'\t' read -r sub_name sub_directory sub_cats <<<"${row}"
    sub_directory_file="$(find_directory_file "${sub_directory}")" || continue
    sub_icon="$(directory_icon_for_file "${sub_directory_file}")"
    labels+=("${sub_name}")
    icons+=("$(icon_or_default "${sub_icon}" "applications-other")")
    sub_categories+=("${sub_cats}")
  done

  idx="$(rofi_pick_index "${category_name}" labels icons)" || return 0
  if [[ "${idx}" == "0" ]]; then
    local -a all_cats=()
    local entry
    for entry in "${sub_categories[@]}"; do
      IFS=',' read -r -a _split <<<"${entry}"
      all_cats+=("${_split[@]}")
    done
    show_app_list "${category_name}" "${all_cats[@]}"
    return 0
  fi

  IFS=',' read -r -a _cats <<<"${sub_categories[idx]}"
  show_app_list "${labels[idx]}" "${_cats[@]}"
}

show_tools_menu() {
  local menu_file
  local -a top_rows=()
  local -a labels=()
  local -a icons=()
  local -a directories=()
  local -a xml_names=()
  local -a xml_categories=()
  local row
  local idx
  local name
  local directory
  local cats
  local directory_file

  menu_file="$(find_kali_menu_file)" || {
    notify-send -t 5000 "Kali Tools" "Could not find kali-applications.menu"
    return 0
  }

  mapfile -t top_rows < <(parse_top_categories "${menu_file}")
  [[ ${#top_rows[@]} -gt 0 ]] || {
    notify-send -t 5000 "Kali Tools" "No Kali categories found"
    return 0
  }

  for row in "${top_rows[@]}"; do
    IFS=$'\t' read -r name directory cats <<<"${row}"
    directory_file="$(find_directory_file "${directory}")" || continue
    labels+=("$(directory_name_for_file "${directory_file}")")
    icons+=("$(icon_or_default "$(directory_icon_for_file "${directory_file}")" "applications-other")")
    directories+=("${directory}")
    xml_names+=("${name}")
    xml_categories+=("${cats}")
  done

  idx="$(rofi_pick_index "Tools" labels icons)" || return 0
  show_category_tools "${menu_file}" "${xml_names[idx]}" "${directories[idx]}" "${xml_categories[idx]}"
}

open_path_target() {
  local mode="$1"
  local path="$2"

  case "${mode}" in
    terminal) setsid -f alacritty --working-directory "${path}" >/dev/null 2>&1 || true ;;
    file-manager) setsid -f thunar "${path}" >/dev/null 2>&1 || true ;;
  esac
}

flat_path_entries() {
  printf '%s\t%s\t%s\n' \
    "/tmp" "folder-temp" "/tmp" \
    "/var/www/html" "folder-remote" "/var/www/html" \
    "/opt" "folder" "/opt" \
    "/usr/share/wordlists" "folder-download" "/usr/share/wordlists" \
    "/usr/share/seclists" "folder-download" "/usr/share/seclists" \
    "/usr/share/nmap" "folder" "/usr/share/nmap" \
    "/usr/share/metasploit-framework" "folder" "/usr/share/metasploit-framework" \
    "/usr/share/exploitdb" "folder" "/usr/share/exploitdb" \
    "/usr/share/webshells" "folder" "/usr/share/webshells"
}

show_flat_paths() {
  local mode="$1"
  local -a path_rows=()
  local -a labels=()
  local -a icons=()
  local -a values=()
  local row label icon path idx

  mapfile -t path_rows < <(flat_path_entries)
  for row in "${path_rows[@]}"; do
    IFS=$'\t' read -r label icon path <<<"${row}"
    labels+=("${label}")
    icons+=("${icon}")
    values+=("${path}")
  done

  idx="$(rofi_pick_index "Paths" labels icons)" || return 0
  open_path_target "${mode}" "${values[idx]}"
}

show_screenshot_menu() {
  local -a labels=(
    "Fullscreen"
    "Screenshot Selection"
    "Screenshot Selection To Clipboard"
  )
  local -a icons=(
    "applets-screenshooter"
    "selection-rectangular"
    "edit-copy"
  )
  local idx

  idx="$(rofi_pick_index "Screenshot" labels icons)" || return 0

  case "${labels[idx]}" in
    "Fullscreen") setsid -f "${SCRIPT_DIR}/screenshot-menu.sh" fullscreen >/dev/null 2>&1 || true ;;
    "Screenshot Selection") setsid -f "${SCRIPT_DIR}/screenshot-menu.sh" selection >/dev/null 2>&1 || true ;;
    "Screenshot Selection To Clipboard") setsid -f "${SCRIPT_DIR}/screenshot-menu.sh" clipboard >/dev/null 2>&1 || true ;;
  esac
}

show_main_menu() {
  local idx

  idx="$(rofi_pick_index "Kali" MAIN_MENU_LABELS MAIN_MENU_ICONS)" || return 0

  case "${MAIN_MENU_LABELS[idx]}" in
    "Tools") show_tools_menu ;;
    "Paths (Term)") show_flat_paths "terminal" ;;
    "Paths (File Explorer)") show_flat_paths "file-manager" ;;
    "Update") setsid -f alacritty -e "${SCRIPT_DIR}/update-manager.sh" >/dev/null 2>&1 || true ;;
    "Screenshot") show_screenshot_menu ;;
  esac
}

rofi_script_header() {
  local prompt="$1"
  local data="${2:-}"

  printf '\0prompt\x1f%s\n' "${prompt}"
  printf '\0no-custom\x1ftrue\n'
  [[ -n "${data}" ]] && printf '\0data\x1f%s\n' "${data}"
}

rofi_script_row() {
  local label="$1"
  local icon="${2:-}"
  local info="${3:-}"

  printf '%s' "${label}"
  [[ -n "${icon}" ]] && printf '\0icon\x1f%s' "${icon}"
  [[ -n "${info}" ]] && printf '\x1finfo\x1f%s' "${info}"
  printf '\n'
}

render_main_menu_script() {
  local i

  rofi_script_header "Kali" "main"
  for i in "${!MAIN_MENU_LABELS[@]}"; do
    rofi_script_row "${MAIN_MENU_LABELS[i]}" "${MAIN_MENU_ICONS[i]}" "main|${MAIN_MENU_LABELS[i]}"
  done
}

render_flat_paths_menu_script() {
  local mode="$1"
  local -a path_rows=()
  local row label icon path

  rofi_script_header "Paths" "flat-paths|${mode}"
  rofi_script_row "Back" "go-previous" "back|main"

  mapfile -t path_rows < <(flat_path_entries)
  for row in "${path_rows[@]}"; do
    IFS=$'\t' read -r label icon path <<<"${row}"
    rofi_script_row "${label}" "${icon}" "path-open|${mode}|${path}"
  done
}

render_screenshot_menu_script() {
  rofi_script_header "Screenshot" "screenshot"
  rofi_script_row "Back" "go-previous" "back|main"
  rofi_script_row "Fullscreen" "applets-screenshooter" "screenshot|fullscreen"
  rofi_script_row "Screenshot Selection" "selection-rectangular" "screenshot|selection"
  rofi_script_row "Screenshot Selection To Clipboard" "edit-copy" "screenshot|clipboard"
}

render_tools_menu_script() {
  local menu_file
  local -a top_rows=()
  local row
  local name
  local directory
  local cats
  local directory_file

  menu_file="$(find_kali_menu_file)" || exit 0
  rofi_script_header "Tools" "tools-top"
  rofi_script_row "Back" "go-previous" "back|main"

  mapfile -t top_rows < <(parse_top_categories "${menu_file}")
  for row in "${top_rows[@]}"; do
    IFS=$'\t' read -r name directory cats <<<"${row}"
    directory_file="$(find_directory_file "${directory}")" || continue
    rofi_script_row \
      "$(directory_name_for_file "${directory_file}")" \
      "$(icon_or_default "$(directory_icon_for_file "${directory_file}")" "applications-other")" \
      "tools-category|${name}|${directory}|${cats}"
  done
}

render_tools_category_menu_script() {
  local category_name="$1"
  local category_directory="$2"
  local category_categories="$3"
  local menu_file
  local category_directory_file
  local category_icon
  local category_display_name
  local -a sub_rows=()
  local -a all_cats_parts=()
  local row
  local sub_name
  local sub_directory
  local sub_cats
  local sub_directory_file
  local sub_icon
  local all_cats_csv

  menu_file="$(find_kali_menu_file)" || exit 0
  category_directory_file="$(find_directory_file "${category_directory}")" || exit 0
  category_icon="$(directory_icon_for_file "${category_directory_file}")"
  category_display_name="$(directory_name_for_file "${category_directory_file}")"

  mapfile -t sub_rows < <(parse_subcategories "${menu_file}" "${category_name}")
  if [[ ${#sub_rows[@]} -eq 0 ]]; then
    render_tools_app_menu_script "${category_display_name}" "${category_categories}"
    return 0
  fi

  all_cats_parts=("${category_categories}")
  for row in "${sub_rows[@]}"; do
    IFS=$'\t' read -r sub_name sub_directory sub_cats <<<"${row}"
    all_cats_parts+=("${sub_cats}")
  done
  all_cats_csv="$(IFS=,; printf '%s' "${all_cats_parts[*]}")"

  rofi_script_header "${category_display_name}" "tools-category|${category_name}|${category_directory}|${category_categories}"
  rofi_script_row "Back" "go-previous" "back|tools-top"
  rofi_script_row "All Tools" "${category_icon}" "tools-apps|${category_display_name}|${all_cats_csv}"

  for row in "${sub_rows[@]}"; do
    IFS=$'\t' read -r sub_name sub_directory sub_cats <<<"${row}"
    sub_directory_file="$(find_directory_file "${sub_directory}")" || continue
    sub_icon="$(icon_or_default "$(directory_icon_for_file "${sub_directory_file}")" "applications-other")"
    rofi_script_row \
      "${sub_name}" \
      "${sub_icon}" \
      "tools-apps|${sub_name}|${sub_cats}"
  done
}

render_tools_app_menu_script() {
  local prompt="$1"
  local cats_csv="$2"
  local -a cats=()
  local -a app_rows=()
  local row
  local label
  local icon
  local desktop_file

  IFS=',' read -r -a cats <<<"${cats_csv}"
  rofi_script_header "${prompt}" "tools-apps|${prompt}|${cats_csv}"
  rofi_script_row "Back" "go-previous" "back|tools-top"

  mapfile -t app_rows < <(find_desktop_entries_by_categories "${cats[@]}" | sort -t $'\t' -k1,1f)
  for row in "${app_rows[@]}"; do
    IFS=$'\t' read -r label icon desktop_file <<<"${row}"
    rofi_script_row "${label}" "$(icon_or_default "${icon}" "application-x-executable")" "launch-desktop|${desktop_file}"
  done
}

handle_rofi_script_selection() {
  local info="${ROFI_INFO:-}"
  local selection="${1:-}"
  local action
  local arg1
  local arg2
  local arg3

  IFS='|' read -r action arg1 arg2 arg3 <<<"${info}"

  case "${action}" in
    main)
      case "${arg1}" in
        "Tools") render_tools_menu_script ;;
        "Paths (Term)") render_flat_paths_menu_script "terminal" ;;
        "Paths (File Explorer)") render_flat_paths_menu_script "file-manager" ;;
        "Update") setsid -f alacritty -e "${SCRIPT_DIR}/update-manager.sh" >/dev/null 2>&1 || true ;;
        "Screenshot") render_screenshot_menu_script ;;
      esac
      ;;
    back)
      case "${arg1}" in
        tools-top) render_tools_menu_script ;;
        *) render_main_menu_script ;;
      esac
      ;;
    flat-paths)
      # Data stored as flat-paths|mode, selection handled via path-open info
      ;;
    path-open)
      open_path_target "${arg1}" "${arg2}"
      ;;
    screenshot)
      case "${arg1}" in
        fullscreen) setsid -f "${SCRIPT_DIR}/screenshot-menu.sh" fullscreen >/dev/null 2>&1 || true ;;
        selection) setsid -f "${SCRIPT_DIR}/screenshot-menu.sh" selection >/dev/null 2>&1 || true ;;
        clipboard) setsid -f "${SCRIPT_DIR}/screenshot-menu.sh" clipboard >/dev/null 2>&1 || true ;;
      esac
      ;;
    tools-category)
      render_tools_category_menu_script "${arg1}" "${arg2}" "${arg3}"
      ;;
    tools-apps)
      render_tools_app_menu_script "${arg1}" "${arg2}"
      ;;
    launch-desktop)
      launch_desktop_entry "${arg1}"
      ;;
    *)
      if [[ -z "${selection}" || "${ROFI_RETV:-0}" == "0" ]]; then
        render_main_menu_script
      fi
      ;;
  esac
}

launch_rofi_script_mode() {
  exec rofi -show Kali -modes "Kali:${BASH_SOURCE[0]}"
}

render_initial_menu_script() {
  case "${KALIDOTS_ROFI_INITIAL:-main}" in
    flat-paths\|terminal) render_flat_paths_menu_script "terminal" ;;
    flat-paths\|file-manager) render_flat_paths_menu_script "file-manager" ;;
    screenshot) render_screenshot_menu_script ;;
    tools-top) render_tools_menu_script ;;
    *) render_main_menu_script ;;
  esac
}

if [[ -n "${ROFI_RETV:-}" ]]; then
  if [[ "${ROFI_RETV}" == "0" ]]; then
    render_initial_menu_script
  else
    handle_rofi_script_selection "${1:-}"
  fi
  exit 0
fi

case "${MODE}" in
  main) launch_rofi_script_mode ;;
  tools) show_tools_menu ;;
  paths-term) show_flat_paths "terminal" ;;
  paths-files) show_flat_paths "file-manager" ;;
  screenshot) show_screenshot_menu ;;
  *) exit 1 ;;
esac
