#!/bin/bash
set -e

source /app/scripts/on-demand-common.sh

mkdir -p /tmp/hls
CURRENT_FFMPEG_PID=

cleanup_manager() {
  if [ -n "${CURRENT_FFMPEG_PID}" ] && kill -0 "${CURRENT_FFMPEG_PID}" 2>/dev/null; then
    kill "${CURRENT_FFMPEG_PID}" 2>/dev/null || true
    wait "${CURRENT_FFMPEG_PID}" 2>/dev/null || true
  fi

  clear_ffmpeg_state
  clear_hls_stream_artifacts
}

trap cleanup_manager EXIT SIGTERM SIGINT

start_ffmpeg() {
  if is_ffmpeg_running; then
    return
  fi

  clear_ffmpeg_state
  clear_hls_stream_artifacts
  echo "Recent HLS activity detected; starting FFmpeg..."
  bash /app/scripts/start-ffmpeg.sh &
  local pid=$!
  CURRENT_FFMPEG_PID=${pid}
  echo "${pid}" > /tmp/ffmpeg.pid
  record_ffmpeg_start
}

stop_ffmpeg() {
  if ! is_ffmpeg_running; then
    clear_ffmpeg_state
    clear_hls_stream_artifacts
    return
  fi

  local pid
  pid=$(ffmpeg_pid)
  echo "No recent HLS activity; stopping FFmpeg..."
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  CURRENT_FFMPEG_PID=
  clear_ffmpeg_state
  clear_hls_stream_artifacts
}

echo "Starting FFmpeg on-demand manager (idle timeout: ${FFMPEG_IDLE_TIMEOUT}s, poll interval: ${FFMPEG_MANAGER_POLL_INTERVAL}s)..."

while true; do
  if has_recent_hls_activity; then
    if ! is_ffmpeg_running; then
      start_ffmpeg
    fi
  else
    if is_ffmpeg_running; then
      stop_ffmpeg
    else
      clear_ffmpeg_state
      clear_hls_stream_artifacts
    fi
  fi

  sleep "${FFMPEG_MANAGER_POLL_INTERVAL}"
done
