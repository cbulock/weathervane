#!/bin/bash
set -e

source /app/scripts/gpu-common.sh

WIDTH=${SCREEN_WIDTH:-640}
HEIGHT=${SCREEN_HEIGHT:-480}
CAPTURE_MODE=${CAPTURE_MODE:-full}
CAPTURE_WIDTH=${CAPTURE_WIDTH:-$WIDTH}
CAPTURE_HEIGHT=${CAPTURE_HEIGHT:-$HEIGHT}
CAPTURE_OFFSET_X=${CAPTURE_OFFSET_X:-0}
CAPTURE_OFFSET_Y=${CAPTURE_OFFSET_Y:-0}
FPS=${FRAMERATE:-15}
VBITRATE=${VIDEO_BITRATE:-1200k}
ABITRATE=${AUDIO_BITRATE:-128k}
PRESET=${FFMPEG_PRESET:-ultrafast}
VAAPI_QP=${VAAPI_QP:-23}
VAAPI_QUALITY=${VAAPI_QUALITY:-4}
HLS_TIME=${HLS_SEGMENT_DURATION:-4}
HLS_SIZE=${HLS_LIST_SIZE:-5}
FRAMING_DEBUG=${FRAMING_DEBUG:-false}
FRAMING_DEBUG_DIR=${FRAMING_DEBUG_DIR:-/tmp/hls/debug}

export DISPLAY=:99

mkdir -p /tmp/hls

for i in $(seq 1 30); do
  if pactl list short sources | grep -q '^.*virtual_speaker\.monitor'; then
    break
  fi
  sleep 1
done

if ! pactl list short sources | grep -q '^.*virtual_speaker\.monitor'; then
  echo "ERROR: PulseAudio source virtual_speaker.monitor is unavailable"
  exit 1
fi

BUFSIZE=$(echo "${VBITRATE}" | sed 's/k//' | awk '{print $1*2"k"}')
GOP=$((FPS * 2))

case "${CAPTURE_MODE}" in
  full)
    SOURCE_WIDTH=${WIDTH}
    SOURCE_HEIGHT=${HEIGHT}
    SOURCE_OFFSET_X=0
    SOURCE_OFFSET_Y=0
    ;;
  crop)
    SOURCE_WIDTH=${CAPTURE_WIDTH}
    SOURCE_HEIGHT=${CAPTURE_HEIGHT}
    SOURCE_OFFSET_X=${CAPTURE_OFFSET_X}
    SOURCE_OFFSET_Y=${CAPTURE_OFFSET_Y}
    ;;
  *)
    echo "ERROR: Unsupported CAPTURE_MODE '${CAPTURE_MODE}'. Use 'full' or 'crop'."
    exit 1
    ;;
esac

if [ "${FRAMING_DEBUG}" = "true" ]; then
  mkdir -p "${FRAMING_DEBUG_DIR}"
  if ! ffmpeg \
    -y \
    -nostdin \
    -f x11grab \
    -video_size ${WIDTH}x${HEIGHT} \
    -i :99.0+0,0 \
    -frames:v 1 \
    "${FRAMING_DEBUG_DIR}/x-display.png" >/dev/null 2>&1; then
    echo "WARNING: Failed to write X display debug frame to ${FRAMING_DEBUG_DIR}/x-display.png" >&2
  fi
fi

if is_gpu_enabled; then
  require_vaapi_runtime
  echo "Starting FFmpeg capture with Intel VAAPI (${CAPTURE_MODE}: ${SOURCE_WIDTH}x${SOURCE_HEIGHT}+${SOURCE_OFFSET_X},${SOURCE_OFFSET_Y} -> ${WIDTH}x${HEIGHT} @ ${FPS}fps)..."
  exec ffmpeg \
    -nostdin \
    -vaapi_device "${VAAPI_DEVICE}" \
    -f x11grab \
    -framerate ${FPS} \
    -video_size ${SOURCE_WIDTH}x${SOURCE_HEIGHT} \
    -i :99.0+${SOURCE_OFFSET_X},${SOURCE_OFFSET_Y} \
    -f pulse \
    -ac 2 \
    -i virtual_speaker.monitor \
    -vf scale=${WIDTH}:${HEIGHT},format=nv12,hwupload \
    -c:v h264_vaapi \
    -rc_mode CQP \
    -qp ${VAAPI_QP} \
    -quality ${VAAPI_QUALITY} \
    -g ${GOP} \
    -keyint_min ${GOP} \
    -c:a aac \
    -b:a ${ABITRATE} \
    -ar 44100 \
    -ac 2 \
    -f hls \
    -hls_time ${HLS_TIME} \
    -hls_list_size ${HLS_SIZE} \
    -hls_flags delete_segments+append_list \
    -hls_segment_filename '/tmp/hls/segment_%03d.ts' \
    -hls_allow_cache 0 \
    /tmp/hls/stream.m3u8
fi

echo "Starting FFmpeg capture (${CAPTURE_MODE}: ${SOURCE_WIDTH}x${SOURCE_HEIGHT}+${SOURCE_OFFSET_X},${SOURCE_OFFSET_Y} -> ${WIDTH}x${HEIGHT} @ ${FPS}fps)..."
exec ffmpeg \
  -nostdin \
  -f x11grab \
  -framerate ${FPS} \
  -video_size ${SOURCE_WIDTH}x${SOURCE_HEIGHT} \
  -i :99.0+${SOURCE_OFFSET_X},${SOURCE_OFFSET_Y} \
  -f pulse \
  -ac 2 \
  -i virtual_speaker.monitor \
  -vf scale=${WIDTH}:${HEIGHT} \
  -c:v libx264 \
  -preset ${PRESET} \
  -tune animation \
  -profile:v main \
  -level 4.0 \
  -pix_fmt yuv420p \
  -b:v ${VBITRATE} \
  -maxrate ${VBITRATE} \
  -bufsize ${BUFSIZE} \
  -g ${GOP} \
  -keyint_min ${GOP} \
  -sc_threshold 0 \
  -c:a aac \
  -b:a ${ABITRATE} \
  -ar 44100 \
  -ac 2 \
  -f hls \
  -hls_time ${HLS_TIME} \
  -hls_list_size ${HLS_SIZE} \
  -hls_flags delete_segments+append_list \
  -hls_segment_filename '/tmp/hls/segment_%03d.ts' \
  -hls_allow_cache 0 \
  /tmp/hls/stream.m3u8
