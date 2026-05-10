#!/bin/bash
set -e

echo "=== WeatherVane IPTV Stream ==="
echo "Location: ${LOCATION:-auto}"
echo "Resolution: ${SCREEN_WIDTH:-640}x${SCREEN_HEIGHT:-480}"
if [ "${ENABLE_GPU:-false}" = "true" ]; then
  echo "GPU mode: Intel VAAPI (${VAAPI_DEVICE:-/dev/dri/renderD128}, driver ${LIBVA_DRIVER_NAME:-iHD})"
else
  echo "GPU mode: disabled"
fi
echo "Stream will be available at http://localhost:${HLS_PORT:-8080}/hls/stream.m3u8"
echo "EPG will be available at http://localhost:${HLS_PORT:-8080}/epg.xml"
if [ "${FFMPEG_ON_DEMAND:-false}" = "true" ]; then
  echo "FFmpeg mode: on-demand (${FFMPEG_IDLE_TIMEOUT:-60}s idle timeout)"
else
  echo "FFmpeg mode: always on"
fi
echo "==========================="

export DISPLAY=:99
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-root}
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export PULSE_SERVER=${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}

kill_pidfile() {
  local pidfile=$1
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  fi
}

cleanup() {
  echo "Shutting down..."
  kill_pidfile /tmp/ffmpeg-manager.pid
  kill_pidfile /tmp/ffmpeg.pid
  kill_pidfile /tmp/automation-watch.pid
  kill_pidfile /tmp/chromium.pid
  kill_pidfile /tmp/dbus.pid
  kill_pidfile /tmp/system-dbus.pid
  kill_pidfile /tmp/nginx.pid
  kill_pidfile /tmp/xvfb.pid
  kill_pidfile /tmp/pulseaudio.pid
  kill_pidfile /tmp/x11vnc.pid
  exit 0
}
trap cleanup EXIT SIGTERM SIGINT

# Step 1: Start Xvfb
bash /app/scripts/start-xvfb.sh
export DISPLAY=:99

# Step 2: Start session D-Bus for Chromium
bash /app/scripts/start-dbus.sh
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}
export DBUS_SYSTEM_BUS_ADDRESS=${DBUS_SYSTEM_BUS_ADDRESS:-unix:path=/run/dbus/system_bus_socket}

# Step 3: Start PulseAudio
bash /app/scripts/start-pulseaudio.sh

# Step 4: Start nginx for HLS serving
mkdir -p /tmp/hls
rm -f /tmp/hls/viewer-activity.log /tmp/ffmpeg-started-at
EPG_PATH=/tmp/hls/epg.xml
if ! bash /app/scripts/generate-epg.sh "$EPG_PATH"; then
  echo "Failed to generate EPG file at ${EPG_PATH}" >&2
  exit 1
fi
nginx -c /app/config/nginx.conf &
echo $! > /tmp/nginx.pid
echo "nginx started"

# Step 5: Start Chromium
bash /app/scripts/start-chromium.sh

# Step 6: Optional VNC for debugging
if [ "${ENABLE_VNC}" = "true" ]; then
  echo "Starting VNC server on :5900..."
  x11vnc -display :99 -forever -nopw -shared -rfbport 5900 &
  echo $! > /tmp/x11vnc.pid
fi

# Step 7: Run browser automation (set location, start retrocast, unmute)
echo "Running browser automation..."
sleep 5
cd /app/automation && node setup-weather.js
echo "Automation complete"

# Step 8: Keep watching for the Start RetroCast button in the background
echo "Starting automation watcher..."
cd /app/automation && node setup-weather.js --watch &
echo $! > /tmp/automation-watch.pid

# Step 9: Start FFmpeg capture or on-demand manager
if [ "${FFMPEG_ON_DEMAND:-false}" = "true" ]; then
  bash /app/scripts/manage-ffmpeg.sh &
  MANAGER_PID=$!
  echo $MANAGER_PID > /tmp/ffmpeg-manager.pid
else
  bash /app/scripts/start-ffmpeg.sh &
  FFMPEG_PID=$!
  echo $FFMPEG_PID > /tmp/ffmpeg.pid
fi

echo "==========================="
echo "WeatherVane is live!"
echo "Stream: http://localhost:${HLS_PORT:-8080}/hls/stream.m3u8"
echo "EPG: http://localhost:${HLS_PORT:-8080}/epg.xml"
echo "==========================="

if [ "${FFMPEG_ON_DEMAND:-false}" = "true" ]; then
  wait $MANAGER_PID
else
  wait $FFMPEG_PID
fi
