#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="${HOME}/.config/i3/scripts"
readonly MODE="${1:-main}"
readonly -a MAIN_MENU_LABELS=(
  "Tools"
  "Paths"
  "Update"
  "Screen Recording"
  "Screenshot"
)
readonly -a MAIN_MENU_ICONS=(
  "applications-security"
  "folder"
  "system-software-update"
  "camera-video"
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
        print name[depth] "\t" directory[depth]
      }
      delete name[depth]
      delete directory[depth]
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
  ' "${menu_file}"
}

parse_subcategories() {
  local menu_file="$1"
  local parent_name="$2"

  awk -v parent="${parent_name}" '
    /<Menu>/ { depth++; next }
    /<\/Menu>/ {
      if (depth == 3 && name[2] == parent && name[depth] != "") {
        print name[depth] "\t" directory[depth]
      }
      delete name[depth]
      delete directory[depth]
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
  ' "${menu_file}"
}

slug_from_directory_file() {
  local directory_file="$1"
  printf '%s\n' "$(basename "${directory_file}" .directory)"
}

find_desktop_entries_by_slugs() {
  local -a slugs=("$@")
  local -A seen=()
  local desktop_file
  local categories
  local name
  local icon
  local slug

  while IFS= read -r desktop_file; do
    desktop_entry_hidden "${desktop_file}" && continue
    categories="$(desktop_entry_value "${desktop_file}" "Categories")"
    [[ -n "${categories}" ]] || continue

    for slug in "${slugs[@]}"; do
      if [[ ";${categories};" == *";${slug};"* ]]; then
        [[ -n "${seen[${desktop_file}]+x}" ]] && continue 2
        name="$(desktop_entry_value "${desktop_file}" "Name")"
        icon="$(desktop_entry_value "${desktop_file}" "Icon")"
        [[ -n "${name}" ]] || continue 2
        printf '%s\t%s\t%s\n' "${name}" "${icon}" "${desktop_file}"
        seen["${desktop_file}"]=1
        continue 2
      fi
    done
  done < <(find /usr/share/applications /usr/local/share/applications -maxdepth 1 -type f -name '*.desktop' 2>/dev/null | sort)
}

show_app_list_for_slugs() {
  local prompt="$1"
  shift
  local -a slugs=("$@")
  local -a app_rows=()
  local -a labels=()
  local -a icons=()
  local -a desktop_files=()
  local row
  local idx
  local label
  local icon
  local desktop_file

  mapfile -t app_rows < <(find_desktop_entries_by_slugs "${slugs[@]}" | sort -t $'\t' -k1,1f)
  [[ ${#app_rows[@]} -gt 0 ]] || {
    notify-send "Kali Tools" "No launchers found for ${prompt}"
    return 0
  }

  for row in "${app_rows[@]}"; do
    IFS=$'\t' read -r label icon desktop_file <<<"${row}"
    labels+=("${label}")
    icons+=("${icon}")
    desktop_files+=("${desktop_file}")
  done

  idx="$(rofi_pick_index "${prompt}" labels icons)" || return 0
  launch_desktop_entry "${desktop_files[idx]}"
}

show_category_tools() {
  local menu_file="$1"
  local category_name="$2"
  local category_directory="$3"
  local category_slug
  local category_icon
  local category_directory_file
  local -a sub_rows=()
  local -a labels=()
  local -a icons=()
  local -a sub_slugs=()
  local row
  local idx
  local sub_name
  local sub_directory
  local sub_directory_file
  local sub_icon

  category_directory_file="$(find_directory_file "${category_directory}")" || {
    notify-send "Kali Tools" "Missing directory metadata for ${category_name}"
    return 0
  }
  category_slug="$(slug_from_directory_file "${category_directory_file}")"
  category_icon="$(directory_icon_for_file "${category_directory_file}")"

  mapfile -t sub_rows < <(parse_subcategories "${menu_file}" "${category_name}")
  if [[ ${#sub_rows[@]} -eq 0 ]]; then
    show_app_list_for_slugs "${category_name}" "${category_slug}"
    return 0
  fi

  labels=("All Tools")
  icons=("${category_icon}")
  sub_slugs=("${category_slug}")

  for row in "${sub_rows[@]}"; do
    IFS=$'\t' read -r sub_name sub_directory <<<"${row}"
    sub_directory_file="$(find_directory_file "${sub_directory}")" || continue
    sub_icon="$(directory_icon_for_file "${sub_directory_file}")"
    labels+=("${sub_name}")
    icons+=("${sub_icon}")
    sub_slugs+=("$(slug_from_directory_file "${sub_directory_file}")")
  done

  idx="$(rofi_pick_index "${category_name}" labels icons)" || return 0
  if [[ "${idx}" == "0" ]]; then
    show_app_list_for_slugs "${category_name}" "${sub_slugs[@]}"
    return 0
  fi

  show_app_list_for_slugs "${labels[idx]}" "${sub_slugs[idx]}"
}

show_tools_menu() {
  local menu_file
  local -a top_rows=()
  local -a labels=()
  local -a icons=()
  local -a directories=()
  local row
  local idx
  local name
  local directory
  local directory_file

  menu_file="$(find_kali_menu_file)" || {
    notify-send "Kali Tools" "Could not find kali-applications.menu"
    return 0
  }

  mapfile -t top_rows < <(parse_top_categories "${menu_file}")
  [[ ${#top_rows[@]} -gt 0 ]] || {
    notify-send "Kali Tools" "No Kali categories found"
    return 0
  }

  for row in "${top_rows[@]}"; do
    IFS=$'\t' read -r name directory <<<"${row}"
    directory_file="$(find_directory_file "${directory}")" || continue
    labels+=("$(directory_name_for_file "${directory_file}")")
    icons+=("$(directory_icon_for_file "${directory_file}")")
    directories+=("${directory}")
  done

  idx="$(rofi_pick_index "Tools" labels icons)" || return 0
  show_category_tools "${menu_file}" "${labels[idx]}" "${directories[idx]}"
}

open_path_target() {
  local mode="$1"
  local path="$2"

  case "${mode}" in
    terminal) setsid -f alacritty --working-directory "${path}" >/dev/null 2>&1 || true ;;
    file-manager) setsid -f thunar "${path}" >/dev/null 2>&1 || true ;;
  esac
}

path_section_entries() {
  local section="$1"

  case "${section}" in
    Core)
      printf '%s\t%s\t%s\n' \
        "downloads" "folder-download" "${HOME}/downloads" \
        "notes" "folder-documents" "${HOME}/notes" \
        "engagements" "folder" "${HOME}/engagements"
      ;;
    Loot)
      printf '%s\t%s\t%s\n' \
        "loot" "folder-saved-search" "${HOME}/loot" \
        "screenshots" "folder-pictures" "${HOME}/screenshots" \
        "recordings" "folder-videos" "${HOME}/recordings" \
        "reports" "folder-documents" "${HOME}/reports"
      ;;
    Infra)
      printf '%s\t%s\t%s\n' \
        "payloads" "folder-templates" "${HOME}/payloads" \
        "staging (/tmp)" "folder-temp" "/tmp" \
        "web root" "folder-remote" "/var/www/html" \
        "tooling (/opt)" "folder" "/opt" \
        "wordlists" "folder-download" "/usr/share/wordlists" \
        "SecLists" "folder-download" "/usr/share/seclists" \
        "nmap data" "folder" "/usr/share/nmap" \
        "Metasploit" "folder" "/usr/share/metasploit-framework"
      ;;
  esac
}

show_path_section_menu() {
  local mode="$1"
  local -a labels=()
  local -a icons=(
    "folder"
    "folder-saved-search"
    "applications-system"
  )
  local -a sections=(
    "Core"
    "Loot"
    "Infra"
  )
  local -a path_rows=()
  local -a path_labels=()
  local -a path_icons=()
  local -a path_values=()
  local section_idx
  local row
  local label
  local icon
  local path
  local path_idx

  labels=("${sections[@]}")
  section_idx="$(rofi_pick_index "Paths" labels icons)" || return 0

  mapfile -t path_rows < <(path_section_entries "${sections[section_idx]}")
  for row in "${path_rows[@]}"; do
    IFS=$'\t' read -r label icon path <<<"${row}"
    path_labels+=("${label}")
    path_icons+=("${icon}")
    path_values+=("${path}")
  done

  path_idx="$(rofi_pick_index "${sections[section_idx]}" path_labels path_icons)" || return 0
  open_path_target "${mode}" "${path_values[path_idx]}"
}

show_paths_menu() {
  local -a labels=(
    "Open in Terminal"
    "Open in File Explorer"
  )
  local -a icons=(
    "utilities-terminal"
    "system-file-manager"
  )
  local idx

  idx="$(rofi_pick_index "Paths" labels icons)" || return 0

  case "${labels[idx]}" in
    "Open in Terminal") show_path_section_menu "terminal" ;;
    "Open in File Explorer") show_path_section_menu "file-manager" ;;
  esac
}

show_screen_recording_menu() {
  local -a labels=(
    "Record Full Screen"
    "Record Selection"
    "Record Selection To GIF"
  )
  local -a icons=(
    "video-display"
    "video-x-generic"
    "image-gif"
  )
  local idx

  idx="$(rofi_pick_index "Recording" labels icons)" || return 0

  case "${labels[idx]}" in
    "Record Full Screen") setsid -f "${SCRIPT_DIR}/screen-record.sh" --fullscreen >/dev/null 2>&1 || true ;;
    "Record Selection") setsid -f "${SCRIPT_DIR}/screen-record.sh" --area >/dev/null 2>&1 || true ;;
    "Record Selection To GIF") setsid -f "${SCRIPT_DIR}/screen-record.sh" --gif >/dev/null 2>&1 || true ;;
  esac
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
    "Paths") show_paths_menu ;;
    "Update") setsid -f "${SCRIPT_DIR}/system-update.sh" >/dev/null 2>&1 || true ;;
    "Screen Recording") show_screen_recording_menu ;;
    "Screenshot") show_screenshot_menu ;;
  esac
}

case "${MODE}" in
  main) show_main_menu ;;
  tools) show_tools_menu ;;
  paths) show_paths_menu ;;
  recording) show_screen_recording_menu ;;
  screenshot) show_screenshot_menu ;;
  *) exit 1 ;;
esac
