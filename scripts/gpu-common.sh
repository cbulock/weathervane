#!/bin/bash

GPU_ENABLED=${ENABLE_GPU:-false}
VAAPI_DEVICE=${VAAPI_DEVICE:-/dev/dri/renderD128}
LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-iHD}

export VAAPI_DEVICE

if [ -n "${LIBVA_DRIVER_NAME}" ]; then
  export LIBVA_DRIVER_NAME
fi

is_gpu_enabled() {
  [ "${GPU_ENABLED}" = "true" ]
}

find_vaapi_driver() {
  find /usr/lib -path "*/dri/${LIBVA_DRIVER_NAME}_drv_video.so" -print -quit 2>/dev/null
}

require_vaapi_runtime() {
  if ! is_gpu_enabled; then
    return
  fi

  local arch
  arch=$(dpkg --print-architecture 2>/dev/null || uname -m)

  case "${arch}" in
    amd64|i386)
      ;;
    *)
      echo "ERROR: ENABLE_GPU=true is only supported on Intel-capable x86 container builds. Current architecture: ${arch}." >&2
      exit 1
      ;;
  esac

  if [ ! -c "${VAAPI_DEVICE}" ]; then
    echo "ERROR: ENABLE_GPU=true but VAAPI device '${VAAPI_DEVICE}' is unavailable. Mount the Intel render node into the container and ensure the container has access to the host render group." >&2
    exit 1
  fi

  if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_vaapi'; then
    echo "ERROR: ENABLE_GPU=true but this FFmpeg build does not provide the h264_vaapi encoder." >&2
    exit 1
  fi

  if [ -n "${LIBVA_DRIVER_NAME}" ] && [ -z "$(find_vaapi_driver)" ]; then
    echo "ERROR: ENABLE_GPU=true but the Intel VAAPI driver '${LIBVA_DRIVER_NAME}' is not installed in this image. Use an amd64 build and override LIBVA_DRIVER_NAME=i965 for older Intel GPUs if needed." >&2
    exit 1
  fi
}
