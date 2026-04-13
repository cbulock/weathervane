#!/bin/bash

curl -sf http://localhost:8080/health > /dev/null || exit 1

PLAYLIST=/tmp/hls/stream.m3u8
[ -f "$PLAYLIST" ] || exit 1
if [ "$(find "$PLAYLIST" -mmin +0.5 2>/dev/null)" ]; then
  exit 1
fi

if [ ! -f /tmp/ffmpeg.pid ] || ! kill -0 "$(cat /tmp/ffmpeg.pid)" 2>/dev/null; then
  exit 1
fi

if [ ! -f /tmp/chromium.pid ] || ! kill -0 "$(cat /tmp/chromium.pid)" 2>/dev/null; then
  exit 1
fi

exit 0
