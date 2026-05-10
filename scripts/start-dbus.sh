#!/bin/bash
set -e

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-root}
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

DBUS_BUS_PATH=${DBUS_BUS_PATH:-$XDG_RUNTIME_DIR/bus}
SYSTEM_DBUS_DIR=${SYSTEM_DBUS_DIR:-/run/dbus}
SYSTEM_DBUS_PIDFILE=${SYSTEM_DBUS_PIDFILE:-/tmp/system-dbus.pid}
SYSTEM_DBUS_RUNTIME_PIDFILE=${SYSTEM_DBUS_RUNTIME_PIDFILE:-${SYSTEM_DBUS_DIR}/pid}

rm -f "$DBUS_BUS_PATH" /tmp/dbus.pid "$SYSTEM_DBUS_PIDFILE" "$SYSTEM_DBUS_RUNTIME_PIDFILE" "${SYSTEM_DBUS_DIR}/system_bus_socket"
mkdir -p "$SYSTEM_DBUS_DIR"

dbus-uuidgen --ensure=/etc/machine-id >/dev/null 2>&1 || true

echo "Starting session D-Bus..."
dbus-daemon \
  --session \
  --address="unix:path=$DBUS_BUS_PATH" \
  --fork \
  --print-pid > /tmp/dbus.pid

export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_BUS_PATH"
echo "D-Bus session bus is ready"

echo "Starting system D-Bus..."
dbus-daemon \
  --system \
  --fork \
  --print-pid > "$SYSTEM_DBUS_PIDFILE"

export DBUS_SYSTEM_BUS_ADDRESS=${DBUS_SYSTEM_BUS_ADDRESS:-unix:path=${SYSTEM_DBUS_DIR}/system_bus_socket}
echo "D-Bus system bus is ready"
