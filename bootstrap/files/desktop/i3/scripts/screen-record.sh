#!/usr/bin/env bash
set -euo pipefail

PIDFILE="/tmp/i3-screenrecord.pid"
INDICATOR="/tmp/i3-recording-active"
STATEFILE="/tmp/i3-screenrecord.state"
MODE="${1:---fullscreen}"

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    notify-send "Recording Error" "Missing dependency: ${cmd}"
    exit 1
  }
}

recording_is_active() {
  [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null
}

write_state() {
  local mode="$1"
  local output="$2"
  local temp_output="$3"

  cat > "${STATEFILE}" <<EOF
MODE=${mode}
OUTPUT=${output}
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

stop_recording() {
  if recording_is_active; then
    local pid
    pid="$(cat "${PIDFILE}")"

    kill -INT "${pid}" 2>/dev/null || true
    while kill -0 "${pid}" 2>/dev/null; do
      sleep 0.2
    done

    if load_state && [[ "${MODE:-}" == "gif" && -n "${TEMP_OUTPUT:-}" && -f "${TEMP_OUTPUT}" ]]; then
      require_command ffmpeg
      ffmpeg -y -i "${TEMP_OUTPUT}" -vf "fps=15,scale=640:-1:flags=lanczos" "${OUTPUT}"
      rm -f "${TEMP_OUTPUT}"
      notify-send "GIF Saved" "${OUTPUT}"
    elif load_state && [[ -n "${OUTPUT:-}" ]]; then
      notify-send "Recording Saved" "${OUTPUT}"
    else
      notify-send "Recording Stopped" "Saved to /tmp/"
    fi

    cleanup_state
  else
    cleanup_state
  fi
}

require_command ffmpeg

# If already recording, stop (toggle behavior)
if recording_is_active; then
  stop_recording
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="/tmp/recording-${TIMESTAMP}.mp4"

case "${MODE}" in
  --fullscreen)
    require_command xdpyinfo
    RESOLUTION="$(xdpyinfo | awk '/dimensions:/ {print $2}')"
    write_state "video" "${OUTPUT}" ""
    ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size "${RESOLUTION}" \
      -i "${DISPLAY}+0,0" -preset ultrafast -pix_fmt yuv420p "${OUTPUT}" \
      >/tmp/i3-screenrecord.log 2>&1 &
    ;;
  --area)
    require_command slop
    GEOMETRY="$(slop -f '%wx%h+%x,%y')"
    [[ -n "${GEOMETRY}" ]] || exit 0
    SIZE="${GEOMETRY%%+*}"
    OFFSET="${GEOMETRY#*+}"
    write_state "video" "${OUTPUT}" ""
    ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size "${SIZE}" \
      -i "${DISPLAY}+${OFFSET}" -preset ultrafast -pix_fmt yuv420p "${OUTPUT}" \
      >/tmp/i3-screenrecord.log 2>&1 &
    ;;
  --gif)
    require_command slop
    OUTPUT="/tmp/recording-${TIMESTAMP}.gif"
    GEOMETRY="$(slop -f '%wx%h+%x,%y')"
    [[ -n "${GEOMETRY}" ]] || exit 0
    SIZE="${GEOMETRY%%+*}"
    OFFSET="${GEOMETRY#*+}"
    MP4="/tmp/recording-${TIMESTAMP}-tmp.mp4"
    write_state "gif" "${OUTPUT}" "${MP4}"
    ffmpeg -y -loglevel error -f x11grab -framerate 20 -video_size "${SIZE}" \
      -i "${DISPLAY}+${OFFSET}" -preset ultrafast -pix_fmt yuv420p "${MP4}" \
      >/tmp/i3-screenrecord.log 2>&1 &
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
notify-send "Recording Started" "Press binding again to stop"
