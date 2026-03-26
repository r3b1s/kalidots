#!/usr/bin/env bash
set -euo pipefail

PIDFILE="/tmp/i3-screenrecord.pid"
INDICATOR="/tmp/i3-recording-active"
STATEFILE="/tmp/i3-screenrecord.state"
LOGFILE="/tmp/i3-screenrecord.log"
MODE="${1:---fullscreen}"
OUTPUT_DIR="${HOME}/recordings"

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    notify-send -t 5000 "Recording Error" "Missing dependency: ${cmd}"
    exit 1
  }
}

recording_is_active() {
  [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null
}

write_state() {
  local mode="$1"
  local final_output="$2"
  local temp_output="$3"

  cat > "${STATEFILE}" <<EOF
MODE=${mode}
FINAL_OUTPUT=${final_output}
TEMP_OUTPUT=${temp_output}
EOF
}

load_state() {
  [[ -f "${STATEFILE}" ]] || return 1
  # shellcheck disable=SC1090
  source "${STATEFILE}"
}

cleanup_state() {
  rm -f "${PIDFILE}" "${INDICATOR}" "${STATEFILE}"
}

wait_for_pid_exit() {
  local pid="$1"
  local remaining=100

  while kill -0 "${pid}" 2>/dev/null && (( remaining > 0 )); do
    sleep 0.1
    ((remaining -= 1))
  done
}

finalize_video() {
  local temp_output="$1"
  local final_output="$2"

  ffmpeg -y -loglevel error -i "${temp_output}" -c copy "${final_output}" >>"${LOGFILE}" 2>&1
}

finalize_gif() {
  local temp_output="$1"
  local final_output="$2"

  ffmpeg -y -loglevel error -i "${temp_output}" \
    -vf "fps=15,scale=640:-1:flags=lanczos" \
    "${final_output}" >>"${LOGFILE}" 2>&1
}

stop_recording() {
  local pid=""
  local temp_output=""
  local final_output=""
  local mode=""

  if load_state; then
    temp_output="${TEMP_OUTPUT:-}"
    final_output="${FINAL_OUTPUT:-}"
    mode="${MODE:-}"
  fi

  if recording_is_active; then
    pid="$(cat "${PIDFILE}")"

    kill -INT "${pid}" 2>/dev/null || true
    wait_for_pid_exit "${pid}"
  fi

  if [[ -n "${temp_output}" && -s "${temp_output}" && -n "${final_output}" ]]; then
    require_command ffmpeg
    case "${mode}" in
      gif) finalize_gif "${temp_output}" "${final_output}" ;;
      video) finalize_video "${temp_output}" "${final_output}" ;;
    esac
    rm -f "${temp_output}"
    notify-send -t 5000 "Recording Stopped" "Saved to ${final_output}"
  elif [[ -n "${final_output}" ]]; then
    notify-send -t 5000 "Recording Error" "Capture failed. See ${LOGFILE}"
  else
    notify-send -t 5000 "Recording Stopped" "No active recording"
  fi

  cleanup_state
}

require_command ffmpeg
mkdir -p "${OUTPUT_DIR}"

# If already recording, stop (toggle behavior)
if recording_is_active; then
  stop_recording
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FINAL_OUTPUT="${OUTPUT_DIR}/recording-${TIMESTAMP}.mp4"
TEMP_OUTPUT="${OUTPUT_DIR}/.recording-${TIMESTAMP}.mkv"

case "${MODE}" in
  --fullscreen)
    require_command xdpyinfo
    RESOLUTION="$(xdpyinfo | awk '/dimensions:/ {print $2}')"
    write_state "video" "${FINAL_OUTPUT}" "${TEMP_OUTPUT}"
    ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size "${RESOLUTION}" \
      -i "${DISPLAY}+0,0" -c:v libx264 -preset ultrafast -pix_fmt yuv420p "${TEMP_OUTPUT}" \
      >>"${LOGFILE}" 2>&1 &
    ;;
  --area)
    require_command slop
    GEOMETRY="$(slop -f '%wx%h+%x,%y')"
    [[ -n "${GEOMETRY}" ]] || exit 0
    SIZE="${GEOMETRY%%+*}"
    OFFSET="${GEOMETRY#*+}"
    write_state "video" "${FINAL_OUTPUT}" "${TEMP_OUTPUT}"
    ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size "${SIZE}" \
      -i "${DISPLAY}+${OFFSET}" -c:v libx264 -preset ultrafast -pix_fmt yuv420p "${TEMP_OUTPUT}" \
      >>"${LOGFILE}" 2>&1 &
    ;;
  --gif)
    require_command slop
    FINAL_OUTPUT="${OUTPUT_DIR}/recording-${TIMESTAMP}.gif"
    GEOMETRY="$(slop -f '%wx%h+%x,%y')"
    [[ -n "${GEOMETRY}" ]] || exit 0
    SIZE="${GEOMETRY%%+*}"
    OFFSET="${GEOMETRY#*+}"
    TEMP_OUTPUT="${OUTPUT_DIR}/.recording-${TIMESTAMP}-gif.mkv"
    write_state "gif" "${FINAL_OUTPUT}" "${TEMP_OUTPUT}"
    ffmpeg -y -loglevel error -f x11grab -framerate 20 -video_size "${SIZE}" \
      -i "${DISPLAY}+${OFFSET}" -c:v libx264 -preset ultrafast -pix_fmt yuv420p "${TEMP_OUTPUT}" \
      >>"${LOGFILE}" 2>&1 &
    ;;
  --stop)
    stop_recording
    exit 0
    ;;
  *)
    echo "Usage: $0 {--fullscreen|--area|--gif|--stop}" >&2
    exit 1
    ;;
esac

echo $! > "${PIDFILE}"
touch "${INDICATOR}"
