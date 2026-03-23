#!/usr/bin/env bash
set -euo pipefail

readonly ROFI_PROMPT_MAIN="Kali"
readonly ROFI_PROMPT_TOOLS="Tools"

readonly -a TOOL_CATEGORY_MENU=(
  "01 - Reconnaissance"
  "02 - Resource Development"
  "03 - Initial Access"
  "04 - Execution"
  "05 - Persistence"
  "06 - Privilege Escalation"
  "07 - Defense Evasion"
  "08 - Credential Access"
  "09 - Discovery"
  "10 - Lateral Movement"
  "11 - Collection"
  "12 - Command and Control"
  "13 - Exfiltration"
  "14 - Impact"
  "15 - Forensics"
  "16 - Services and Other Tools"
)

rofi_pick_index() {
  local prompt="$1"
  shift
  local -a options=("$@")
  local choice

  [[ ${#options[@]} -gt 0 ]] || return 1

  choice="$(
    printf '%s\n' "${options[@]}" \
      | rofi -dmenu -i -format i -p "${prompt}" -no-custom
  )" || return 1

  [[ -n "${choice}" ]] || return 1
  printf '%s\n' "${choice}"
}

launch_desktop_entry() {
  local desktop_file="$1"
  gio launch "${desktop_file}" >/dev/null 2>&1 &
  disown || true
}

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

slug_to_label() {
  local slug="$1"

  case "${slug}" in
    kali-reconnaissance) printf 'Reconnaissance\n' ;;
    kali-host-information) printf 'Host Information\n' ;;
    kali-identity-information) printf 'Identity Information\n' ;;
    kali-network-information) printf 'Network Information\n' ;;
    kali-network-information-dns) printf 'Network Information: DNS\n' ;;
    kali-web-scanning) printf 'Web Scanning\n' ;;
    kali-vulnerability-scanning) printf 'Vulnerability Scanning\n' ;;
    kali-web-vulnerability-scanning) printf 'Web Vulnerability Scanning\n' ;;
    kali-bluetooth) printf 'Bluetooth\n' ;;
    kali-wifi) printf 'WiFi\n' ;;
    kali-radio-frequency) printf 'Radio Frequency\n' ;;
    kali-resource-development) printf 'Resource Development\n' ;;
    kali-initial-access) printf 'Initial Access\n' ;;
    kali-execution) printf 'Execution\n' ;;
    kali-persistence) printf 'Persistence\n' ;;
    kali-privilege-escalation) printf 'Privilege Escalation\n' ;;
    kali-defense-evasion) printf 'Defense Evasion\n' ;;
    kali-pass-the-hash) printf 'Pass-the-Hash\n' ;;
    kali-credential-access) printf 'Credential Access\n' ;;
    kali-os-credential-dumping) printf 'OS Credential Dumping\n' ;;
    kali-hash-identification) printf 'Hash Identification\n' ;;
    kali-password-profiling-wordlists) printf 'Password Profiling & Wordlists\n' ;;
    kali-brute-force) printf 'Brute Force\n' ;;
    kali-password-cracking) printf 'Password Cracking\n' ;;
    kali-unsecured-credentials) printf 'Unsecured Credentials\n' ;;
    kali-wifi-credential-access) printf 'WiFi Credential Access\n' ;;
    kali-keylogger) printf 'Keylogger\n' ;;
    kali-voip-credential-access) printf 'VoIP Credential Access\n' ;;
    kali-nfc) printf 'NFC\n' ;;
    kali-kerberoasting) printf 'Kerberoasting\n' ;;
    kali-discovery) printf 'Discovery\n' ;;
    kali-network-service-discovery) printf 'Network Service Discovery\n' ;;
    kali-ssl-tls) printf 'SSL / TLS\n' ;;
    kali-snmp) printf 'SNMP\n' ;;
    kali-network-sniffing) printf 'Network Sniffing\n' ;;
    kali-remote-system-discovery) printf 'Remote System Discovery\n' ;;
    kali-account-discovery) printf 'Account Discovery\n' ;;
    kali-network-share-discovery) printf 'Network Share Discovery\n' ;;
    kali-process-discovery) printf 'Process Discovery\n' ;;
    kali-system-network-configuration-discovery) printf 'System Network Configuration Discovery\n' ;;
    kali-network-security-appliances) printf 'Network Security Appliances\n' ;;
    kali-databases) printf 'Databases\n' ;;
    kali-smtp) printf 'SMTP\n' ;;
    kali-cisco-tools) printf 'Cisco Tools\n' ;;
    kali-active-directory) printf 'Active Directory\n' ;;
    kali-voip) printf 'VoIP\n' ;;
    kali-lateral-movement) printf 'Lateral Movement\n' ;;
    kali-collection) printf 'Collection\n' ;;
    kali-command-and-control) printf 'Command and Control\n' ;;
    kali-application-layer-protocol) printf 'Application Layer Protocol\n' ;;
    kali-non-application-layer-protocol) printf 'Non-Application Layer Protocol\n' ;;
    kali-protocol-tunneling) printf 'Protocol Tunneling\n' ;;
    kali-exfiltration) printf 'Exfiltration\n' ;;
    kali-impact) printf 'Impact\n' ;;
    kali-forensics) printf 'Forensics\n' ;;
    kali-digital-forensics) printf 'Digital Forensics\n' ;;
    kali-forensic-carving-tools) printf 'Forensic Carving Tools\n' ;;
    kali-forensic-imaging-tools) printf 'Forensic Imaging Tools\n' ;;
    kali-pdf-forensics-tools) printf 'PDF Forensics Tools\n' ;;
    kali-sleuth-kit-suite) printf 'Sleuth Kit Suite\n' ;;
    kali-services-and-other-tools) printf 'Services and Other Tools\n' ;;
    kali-reporting-tools) printf 'Reporting Tools\n' ;;
    kali-laboratories) printf 'Laboratories\n' ;;
    kali-system-services) printf 'System Services\n' ;;
    kali-kali-offsec-links) printf 'Kali & Offsec Links\n' ;;
    *)
      printf '%s\n' "${slug#kali-}" | sed 's/-/ /g'
      ;;
  esac
}

category_slugs_for_menu() {
  local category="$1"

  case "${category}" in
    "01 - Reconnaissance")
      printf '%s\n' \
        kali-reconnaissance \
        kali-host-information \
        kali-identity-information \
        kali-network-information \
        kali-network-information-dns \
        kali-web-scanning \
        kali-vulnerability-scanning \
        kali-web-vulnerability-scanning \
        kali-bluetooth \
        kali-wifi \
        kali-radio-frequency
      ;;
    "02 - Resource Development") printf '%s\n' kali-resource-development ;;
    "03 - Initial Access") printf '%s\n' kali-initial-access ;;
    "04 - Execution") printf '%s\n' kali-execution ;;
    "05 - Persistence") printf '%s\n' kali-persistence ;;
    "06 - Privilege Escalation") printf '%s\n' kali-privilege-escalation ;;
    "07 - Defense Evasion")
      printf '%s\n' \
        kali-defense-evasion \
        kali-pass-the-hash
      ;;
    "08 - Credential Access")
      printf '%s\n' \
        kali-credential-access \
        kali-os-credential-dumping \
        kali-hash-identification \
        kali-password-profiling-wordlists \
        kali-brute-force \
        kali-password-cracking \
        kali-unsecured-credentials \
        kali-wifi-credential-access \
        kali-keylogger \
        kali-voip-credential-access \
        kali-nfc \
        kali-kerberoasting
      ;;
    "09 - Discovery")
      printf '%s\n' \
        kali-discovery \
        kali-network-service-discovery \
        kali-ssl-tls \
        kali-snmp \
        kali-network-sniffing \
        kali-remote-system-discovery \
        kali-account-discovery \
        kali-network-share-discovery \
        kali-process-discovery \
        kali-system-network-configuration-discovery \
        kali-network-security-appliances \
        kali-databases \
        kali-smtp \
        kali-cisco-tools \
        kali-active-directory \
        kali-voip
      ;;
    "10 - Lateral Movement")
      printf '%s\n' \
        kali-lateral-movement \
        kali-pass-the-hash
      ;;
    "11 - Collection") printf '%s\n' kali-collection ;;
    "12 - Command and Control")
      printf '%s\n' \
        kali-command-and-control \
        kali-application-layer-protocol \
        kali-non-application-layer-protocol \
        kali-protocol-tunneling
      ;;
    "13 - Exfiltration") printf '%s\n' kali-exfiltration ;;
    "14 - Impact") printf '%s\n' kali-impact ;;
    "15 - Forensics")
      printf '%s\n' \
        kali-forensics \
        kali-digital-forensics \
        kali-forensic-carving-tools \
        kali-forensic-imaging-tools \
        kali-pdf-forensics-tools \
        kali-sleuth-kit-suite
      ;;
    "16 - Services and Other Tools")
      printf '%s\n' \
        kali-services-and-other-tools \
        kali-reporting-tools \
        kali-laboratories \
        kali-system-services \
        kali-kali-offsec-links
      ;;
    *)
      return 1
      ;;
  esac
}

desktop_entry_matches_category() {
  local desktop_file="$1"
  local matched_slug="$2"
  local categories

  categories="$(desktop_entry_value "${desktop_file}" "Categories")"
  [[ -n "${categories}" ]] || return 1

  [[ ";${categories};" == *";${matched_slug};"* ]]
}

find_desktop_entries_for_category() {
  local menu_category="$1"
  local -a category_slugs=()
  local -a desktop_dirs=("/usr/share/applications" "/usr/local/share/applications")
  local -a desktop_files=()
  local desktop_dir
  local desktop_file
  local display_name
  local matched_slug
  local matched_label
  local slug

  mapfile -t category_slugs < <(category_slugs_for_menu "${menu_category}")

  for desktop_dir in "${desktop_dirs[@]}"; do
    [[ -d "${desktop_dir}" ]] || continue
    while IFS= read -r desktop_file; do
      desktop_files+=("${desktop_file}")
    done < <(find "${desktop_dir}" -maxdepth 1 -type f -name '*.desktop' | sort)
  done

  for desktop_file in "${desktop_files[@]}"; do
    desktop_entry_hidden "${desktop_file}" && continue
    display_name="$(desktop_entry_value "${desktop_file}" "Name")"
    [[ -n "${display_name}" ]] || continue

    matched_slug=""
    for slug in "${category_slugs[@]}"; do
      if desktop_entry_matches_category "${desktop_file}" "${slug}"; then
        matched_slug="${slug}"
        break
      fi
    done

    [[ -n "${matched_slug}" ]] || continue

    matched_label="$(slug_to_label "${matched_slug}")"
    printf '%s\t%s\t%s\n' "${display_name}" "${matched_label}" "${desktop_file}"
  done | sort -t $'\t' -k1,1f -k2,2f
}

show_tools_menu() {
  local category_index
  local selected_category
  local -a records=()
  local -a displays=()
  local tool_index
  local selected_record
  local desktop_file

  category_index="$(rofi_pick_index "${ROFI_PROMPT_TOOLS}" "${TOOL_CATEGORY_MENU[@]}")" || return 0
  selected_category="${TOOL_CATEGORY_MENU[category_index]}"

  mapfile -t records < <(find_desktop_entries_for_category "${selected_category}")
  if [[ ${#records[@]} -eq 0 ]]; then
    notify-send "Kali Tools" "No desktop launchers found for ${selected_category}"
    return 0
  fi

  local record
  for record in "${records[@]}"; do
    IFS=$'\t' read -r display_name matched_label desktop_file <<<"${record}"
    displays+=("${display_name} [${matched_label}]")
  done

  tool_index="$(rofi_pick_index "${selected_category}" "${displays[@]}")" || return 0
  selected_record="${records[tool_index]}"
  IFS=$'\t' read -r _ _ desktop_file <<<"${selected_record}"
  launch_desktop_entry "${desktop_file}"
}

show_screen_recording_menu() {
  local -a options=(
    "Record Full Screen"
    "Record Selection"
    "Record Selection To GIF"
  )
  local choice_index

  choice_index="$(rofi_pick_index "Recording" "${options[@]}")" || return 0

  case "${options[choice_index]}" in
    "Record Full Screen") "${HOME}/.config/i3/scripts/screen-record.sh" --fullscreen ;;
    "Record Selection") "${HOME}/.config/i3/scripts/screen-record.sh" --area ;;
    "Record Selection To GIF") "${HOME}/.config/i3/scripts/screen-record.sh" --gif ;;
  esac
}

show_main_menu() {
  local -a options=(
    "Tools"
    "Update"
    "Screen Recording"
    "Screenshot"
  )
  local choice_index

  choice_index="$(rofi_pick_index "${ROFI_PROMPT_MAIN}" "${options[@]}")" || return 0

  case "${options[choice_index]}" in
    "Tools") show_tools_menu ;;
    "Update") "${HOME}/.config/i3/scripts/system-update.sh" ;;
    "Screen Recording") show_screen_recording_menu ;;
    "Screenshot") "${HOME}/.config/i3/scripts/screenshot-menu.sh" ;;
  esac
}

show_main_menu
