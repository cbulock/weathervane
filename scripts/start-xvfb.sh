#!/bin/bash
set -e

WIDTH=${SCREEN_WIDTH:-960}
HEIGHT=${SCREEN_HEIGHT:-720}

rm -f /tmp/.X99-lock
rm -f /tmp/.X11-unix/X99

echo "Starting Xvfb on :99 at ${WIDTH}x${HEIGHT}x24..."
Xvfb :99 -screen 0 ${WIDTH}x${HEIGHT}x24 -ac -nolisten tcp &
XVFB_PID=$!

for i in $(seq 1 30); do
  if [ -e /tmp/.X11-unix/X99 ]; then
    echo "Xvfb is ready (PID: $XVFB_PID)"
    echo $XVFB_PID > /tmp/xvfb.pid
    exit 0
  fi
  sleep 0.5
done

echo "ERROR: Xvfb failed to start"
exit 1
