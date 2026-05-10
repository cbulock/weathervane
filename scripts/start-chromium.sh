#!/bin/bash
set -e

source /app/scripts/gpu-common.sh

WIDTH=${SCREEN_WIDTH:-640}
HEIGHT=${SCREEN_HEIGHT:-480}

export DISPLAY=:99

CHROME_BIN=${CHROME_BIN:-/usr/bin/chromium}

if [ ! -x "$CHROME_BIN" ]; then
  echo "ERROR: Chrome binary not found at $CHROME_BIN"
  exit 1
fi

CHROME_FLAGS=(
  --no-sandbox
  --disable-dev-shm-usage
  --no-first-run
  --disable-sync
  --disable-translate
  --disable-extensions
  --disable-background-networking
  --disable-default-apps
  --disable-infobars
  --disable-background-timer-throttling
  --disable-backgrounding-occluded-windows
  --disable-renderer-backgrounding
  --disable-features=UseDBus,UseSkiaRenderer
  --autoplay-policy=no-user-gesture-required
  --disable-features=TranslateUI
  --window-size=${WIDTH},${HEIGHT}
  --window-position=0,0
  --force-device-scale-factor=1
  --high-dpi-support=1
  --kiosk
  --remote-debugging-port=9222
  --user-data-dir=/tmp/chromium-profile
  --disable-session-crashed-bubble
  --disable-component-update
  --disable-breakpad
  --disable-dev-tools
  --no-zygote
  --js-flags=--max-old-space-size=512
)

if is_gpu_enabled; then
  require_vaapi_runtime
  echo "Starting Chromium with Intel VAAPI enabled via ${VAAPI_DEVICE} (driver ${LIBVA_DRIVER_NAME})..."
  CHROME_FLAGS+=(
    --use-gl=swiftshader
    --ignore-gpu-blocklist
    --enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks
  )
else
  echo "Starting Chromium..."
  CHROME_FLAGS+=(
    --disable-gpu
    --disable-software-rasterizer
    --use-gl=swiftshader
  )
fi

"$CHROME_BIN" "${CHROME_FLAGS[@]}" --app="https://weather.com/retro/" &

CHROME_PID=$!
echo $CHROME_PID > /tmp/chromium.pid

for i in $(seq 1 60); do
  if curl -sf http://localhost:9222/json/version > /dev/null 2>&1; then
    echo "Chromium is ready (PID: $CHROME_PID)"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Chromium failed to start"
exit 1
