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
  stop_browser
}

trap 'exit 0' SIGTERM SIGINT
trap cleanup_manager EXIT

stop_browser() {
  if [ -f /tmp/automation-watch.pid ]; then
    kill "$(cat /tmp/automation-watch.pid)" 2>/dev/null || true
    wait "$(cat /tmp/automation-watch.pid)" 2>/dev/null || true
    rm -f /tmp/automation-watch.pid
  fi

  if is_chromium_running; then
    local pid
    pid=$(cat /tmp/chromium.pid)
    echo "Stopping idle Chromium..."
    kill "${pid}" 2>/dev/null || true
    for _ in $(seq 1 10); do
      if ! kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "${pid}" 2>/dev/null; then
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  fi

  rm -f /tmp/chromium.pid "${BROWSER_START_TS_FILE}"
}

start_browser() {
  if is_chromium_running; then
    return
  fi

  stop_browser
  date +%s > "${BROWSER_START_TS_FILE}"
  echo "Recent HLS activity detected; starting Chromium..."
  bash /app/scripts/start-chromium.sh
  sleep 5
  (cd /app/automation && node setup-weather.js)
  (cd /app/automation && node setup-weather.js --watch) &
  echo $! > /tmp/automation-watch.pid
  rm -f "${BROWSER_START_TS_FILE}"
}

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

echo "Starting stream on-demand manager (idle timeout: ${FFMPEG_IDLE_TIMEOUT}s, poll interval: ${FFMPEG_MANAGER_POLL_INTERVAL}s)..."

while true; do
  if has_recent_hls_activity; then
    if ! is_chromium_running; then
      stop_ffmpeg
      start_browser
    fi
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
    stop_browser
  fi

  sleep "${FFMPEG_MANAGER_POLL_INTERVAL}"
done
