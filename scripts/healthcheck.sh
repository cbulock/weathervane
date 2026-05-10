#!/bin/bash

source /app/scripts/on-demand-common.sh

curl -sf http://localhost:8080/health > /dev/null || exit 1

PLAYLIST=/tmp/hls/stream.m3u8

if [ ! -f /tmp/chromium.pid ] || ! kill -0 "$(cat /tmp/chromium.pid)" 2>/dev/null; then
  exit 1
fi

if is_on_demand_enabled; then
  if [ ! -f /tmp/ffmpeg-manager.pid ] || ! kill -0 "$(cat /tmp/ffmpeg-manager.pid)" 2>/dev/null; then
    exit 1
  fi

  if has_recent_hls_activity && ! is_ffmpeg_running; then
    exit 1
  fi
else
  if ! is_ffmpeg_running; then
    exit 1
  fi
fi

if is_ffmpeg_running; then
  if [ ! -f "$PLAYLIST" ]; then
    if ! is_within_ffmpeg_startup_grace; then
      exit 1
    fi
  elif [ "$(find "$PLAYLIST" -mmin +0.5 2>/dev/null)" ] && ! is_within_ffmpeg_startup_grace; then
    exit 1
  fi
fi

exit 0
