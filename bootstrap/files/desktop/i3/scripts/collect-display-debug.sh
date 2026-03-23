#!/usr/bin/env bash
set -euo pipefail

log_file="${1:-${HOME}/display-debug-$(date -u +%Y%m%dT%H%M%SZ).log}"
event_window="${EVENT_WINDOW_SECONDS:-15}"
script_path="${HOME}/.config/i3/scripts/display-hotplug-watch.sh"
i3_config="${HOME}/.config/i3/config"
xev_log="$(mktemp)"

cleanup() {
  rm -f "${xev_log}"
}
trap cleanup EXIT

run_section() {
  local title="$1"
  shift

  {
    printf '\n===== %s =====\n' "${title}"
    printf '+'
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
    "$@"
  } >>"${log_file}" 2>&1 || true
}

append_note() {
  {
    printf '\n===== %s =====\n' "$1"
    printf '%s\n' "$2"
  } >>"${log_file}"
}

{
  printf 'display debug collected at %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'host=%s\n' "$(hostname)"
  printf 'user=%s\n' "${USER}"
  printf 'pwd=%s\n' "$(pwd)"
} >"${log_file}"

run_section "Process Checks" pgrep -af 'display-hotplug-watch|xev|xsettingsd|spice-display-init'

watcher_pids="$(pgrep -f display-hotplug-watch || true)"
if [[ -n "${watcher_pids}" ]]; then
  watcher_pid_csv="$(paste -sd, <<<"${watcher_pids}")"
  run_section "Watcher ps Output" ps -fp "${watcher_pid_csv}"
else
  append_note "Watcher ps Output" "display-hotplug-watch process not found"
fi

run_section "Script Presence" ls -l "${script_path}"
run_section "i3 Config Entry" grep -n 'display-hotplug-watch' "${i3_config}"
run_section "Session Environment" env
run_section "Display Variables" bash -lc 'printf "DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nXAUTHORITY=%s\n" "${DISPLAY:-}" "${XDG_RUNTIME_DIR:-}" "${XAUTHORITY:-}"'
run_section "Binary Checks" bash -lc 'command -v xev; command -v xrandr; command -v i3-msg; command -v loginctl'
run_section "Initial RandR State" xrandr --query
run_section "SPICE Agent Status" systemctl status spice-vdagentd --no-pager -l
run_section "QEMU Agent Status" systemctl status qemu-guest-agent --no-pager -l
run_section "Session Status" loginctl session-status

append_note \
  "Resize Instructions" \
  "The script will now capture RandR events for ${event_window} seconds. Resize the VM window once during that period."

if command -v timeout >/dev/null 2>&1; then
  timeout "${event_window}" xev -root -event randr >"${xev_log}" 2>&1 || true
else
  (
    xev -root -event randr >"${xev_log}" 2>&1 &
    xev_pid=$!
    sleep "${event_window}"
    kill "${xev_pid}" 2>/dev/null || true
    wait "${xev_pid}" 2>/dev/null || true
  )
fi

{
  printf '\n===== RandR Event Capture =====\n'
  cat "${xev_log}"
} >>"${log_file}" 2>&1

run_section "RandR State After Resize Window" xrandr --query
run_section "Manual xrandr Auto Apply" xrandr --auto
run_section "RandR State After Manual Apply" xrandr --query

append_note "Done" "Log written to ${log_file}"
printf '%s\n' "${log_file}"
