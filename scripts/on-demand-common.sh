#!/bin/bash

FFMPEG_ON_DEMAND=${FFMPEG_ON_DEMAND:-false}
HLS_ACTIVITY_LOG=${HLS_ACTIVITY_LOG:-/tmp/hls/viewer-activity.log}
FFMPEG_IDLE_TIMEOUT=${FFMPEG_IDLE_TIMEOUT:-60}
FFMPEG_MANAGER_POLL_INTERVAL=${FFMPEG_MANAGER_POLL_INTERVAL:-2}
FFMPEG_STARTUP_GRACE=${FFMPEG_STARTUP_GRACE:-20}
FFMPEG_START_TS_FILE=${FFMPEG_START_TS_FILE:-/tmp/ffmpeg-started-at}

is_on_demand_enabled() {
  [ "${FFMPEG_ON_DEMAND}" = "true" ]
}

ffmpeg_pid() {
  if [ -f /tmp/ffmpeg.pid ]; then
    cat /tmp/ffmpeg.pid
  fi
}

is_ffmpeg_running() {
  local pid
  pid=$(ffmpeg_pid)
  [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null
}

record_ffmpeg_start() {
  date +%s > "${FFMPEG_START_TS_FILE}"
}

clear_ffmpeg_state() {
  rm -f /tmp/ffmpeg.pid "${FFMPEG_START_TS_FILE}"
}

clear_hls_stream_artifacts() {
  find /tmp/hls -maxdepth 1 -type f \( -name 'stream.m3u8' -o -name 'stream.m3u8.tmp' -o -name 'segment_*.ts' \) -delete 2>/dev/null || true
}

has_recent_hls_activity() {
  if [ ! -f "${HLS_ACTIVITY_LOG}" ]; then
    return 1
  fi

  local now modified
  now=$(date +%s)
  modified=$(stat -c %Y "${HLS_ACTIVITY_LOG}" 2>/dev/null || echo 0)
  [ $((now - modified)) -lt "${FFMPEG_IDLE_TIMEOUT}" ]
}

is_within_ffmpeg_startup_grace() {
  if [ ! -f "${FFMPEG_START_TS_FILE}" ]; then
    return 1
  fi

  local now started
  now=$(date +%s)
  started=$(cat "${FFMPEG_START_TS_FILE}" 2>/dev/null || echo 0)
  [ $((now - started)) -lt "${FFMPEG_STARTUP_GRACE}" ]
}
