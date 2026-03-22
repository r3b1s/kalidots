#!/usr/bin/env bash
set -euo pipefail

PIDFILE="/tmp/i3-screenrecord.pid"
INDICATOR="/tmp/i3-recording-active"
MODE="${1:---fullscreen}"

stop_recording() {
  if [[ -f "${PIDFILE}" ]]; then
    local pid
    pid="$(cat "${PIDFILE}")"
    if kill -0 "${pid}" 2>/dev/null; then
      kill -INT "${pid}"
      wait "${pid}" 2>/dev/null || true
    fi
    rm -f "${PIDFILE}" "${INDICATOR}"
    notify-send "Recording Stopped" "Saved to /tmp/"
  fi
}

# If already recording, stop (toggle behavior)
if [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
  stop_recording
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="/tmp/recording-${TIMESTAMP}.mp4"

case "${MODE}" in
  --fullscreen)
    RESOLUTION="$(xdpyinfo | awk '/dimensions:/ {print $2}')"
    ffmpeg -f x11grab -video_size "${RESOLUTION}" -i "${DISPLAY}" \
      -preset ultrafast -pix_fmt yuv420p "${OUTPUT}" &
    ;;
  --area)
    GEOMETRY="$(slop -f '%wx%h+%x,%y')"
    SIZE="$(echo "${GEOMETRY}" | cut -d+ -f1)"
    OFFSET="$(echo "${GEOMETRY}" | cut -d+ -f2)"
    ffmpeg -f x11grab -video_size "${SIZE}" -i "${DISPLAY}+${OFFSET}" \
      -preset ultrafast -pix_fmt yuv420p "${OUTPUT}" &
    ;;
  --gif)
    OUTPUT="/tmp/recording-${TIMESTAMP}.gif"
    GEOMETRY="$(slop -f '%wx%h+%x,%y')"
    SIZE="$(echo "${GEOMETRY}" | cut -d+ -f1)"
    OFFSET="$(echo "${GEOMETRY}" | cut -d+ -f2)"
    MP4="/tmp/recording-${TIMESTAMP}-tmp.mp4"
    ffmpeg -f x11grab -video_size "${SIZE}" -i "${DISPLAY}+${OFFSET}" \
      -preset ultrafast -pix_fmt yuv420p "${MP4}" &
    echo $! > "${PIDFILE}"
    touch "${INDICATOR}"
    notify-send "GIF Recording Started" "Press binding again to stop"
    # GIF conversion happens on stop — override stop function
    wait $!
    ffmpeg -i "${MP4}" -vf "fps=15,scale=640:-1:flags=lanczos" "${OUTPUT}"
    rm -f "${MP4}" "${PIDFILE}" "${INDICATOR}"
    notify-send "GIF Saved" "${OUTPUT}"
    exit 0
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
