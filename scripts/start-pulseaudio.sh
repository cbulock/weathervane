#!/bin/bash
set -e

echo "Starting PulseAudio..."

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-root}
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

rm -rf /tmp/pulse-* "$XDG_RUNTIME_DIR/pulse"

pulseaudio \
  --daemonize=no \
  --exit-idle-time=-1 \
  --disallow-exit \
  --log-target=stderr \
  --log-level=warning &
PA_PID=$!

for i in $(seq 1 20); do
  if pactl info > /dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! pactl info > /dev/null 2>&1; then
  echo "ERROR: PulseAudio did not become ready"
  exit 1
fi

pactl load-module module-null-sink sink_name=virtual_speaker sink_properties=device.description="Virtual_Speaker"
pactl set-default-sink virtual_speaker

for i in $(seq 1 20); do
  if pactl list short sources | grep -q '^.*virtual_speaker\.monitor'; then
    break
  fi
  sleep 0.5
done

if ! pactl list short sources | grep -q '^.*virtual_speaker\.monitor'; then
  echo "ERROR: PulseAudio monitor source was not created"
  exit 1
fi

echo "PulseAudio is ready (PID: $PA_PID)"
echo $PA_PID > /tmp/pulseaudio.pid
