#!/bin/bash
set -e

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-root}
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

DBUS_BUS_PATH=${DBUS_BUS_PATH:-$XDG_RUNTIME_DIR/bus}

rm -f "$DBUS_BUS_PATH" /tmp/dbus.pid

echo "Starting session D-Bus..."
dbus-daemon \
  --session \
  --address="unix:path=$DBUS_BUS_PATH" \
  --fork \
  --print-pid > /tmp/dbus.pid

export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_BUS_PATH"
echo "D-Bus session bus is ready"
