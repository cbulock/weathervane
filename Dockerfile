FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xvfb \
    pulseaudio \
    ffmpeg \
    nginx-light \
    chromium \
    fonts-liberation \
    fonts-noto-color-emoji \
    fonts-dejavu-core \
    dbus-x11 \
    libnss3 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libasound2-plugins \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpangocairo-1.0-0 \
    libgtk-3-0 \
    libxss1 \
    libxext6 \
    libxtst6 \
    libxi6 \
    libxfixes3 \
    libxkbcommon0 \
    libxshmfence1 \
    libglu1-mesa \
    procps \
    tini \
    x11vnc \
    nodejs \
    npm \
    libva2 \
    libva-drm2 \
    vainfo \
    && rm -rf /var/lib/apt/lists/*

RUN set -e; \
    arch="$(dpkg --print-architecture)"; \
    if [ "$arch" = "amd64" ] || [ "$arch" = "i386" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends \
        intel-media-va-driver \
        i965-va-driver; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Create app directory
RUN mkdir -p /app

# Install automation dependencies and download a real browser binary for the container.
COPY automation/package*.json /app/automation/
RUN cd /app/automation \
    && npm install --production

# Copy application files
COPY scripts/ /app/scripts/
COPY config/ /app/config/
COPY automation/setup-weather.js /app/automation/
COPY config/asound.conf /etc/asound.conf

# Normalize script line endings for Linux containers and make scripts executable.
RUN sed -i 's/\r$//' /app/scripts/*.sh \
    && chmod +x /app/scripts/*.sh

# Ensure directories exist
RUN mkdir -p /tmp/hls /tmp/chromium-profile

# Set environment defaults
ENV SCREEN_WIDTH=640 \
    SCREEN_HEIGHT=480 \
    FRAME_SAFE_MARGIN=12 \
    CAPTURE_MODE=full \
    CAPTURE_WIDTH=640 \
    CAPTURE_HEIGHT=480 \
    CAPTURE_OFFSET_X=0 \
    CAPTURE_OFFSET_Y=0 \
    FRAMERATE=15 \
    VIDEO_BITRATE=1200k \
    AUDIO_BITRATE=128k \
    FFMPEG_PRESET=ultrafast \
    ENABLE_GPU=false \
    VAAPI_DEVICE=/dev/dri/renderD128 \
    LIBVA_DRIVER_NAME=iHD \
    HLS_SEGMENT_DURATION=4 \
    HLS_LIST_SIZE=5 \
    HLS_PORT=8080 \
    FRAMING_DEBUG=false \
    FRAMING_DEBUG_DIR=/tmp/hls/debug \
    EPG_CHANNEL_ID=weathervane.retro \
    EPG_CHANNEL_NAME="WeatherVane RetroCast" \
    EPG_CHANNEL_ICON=https://weather.com/retro/assets/icon.png \
    EPG_PROGRAM_TITLE="RetroCast Weather Loop" \
    EPG_PROGRAM_DESCRIPTION="Continuous Weather Channel RetroCast stream." \
    TZ=America/New_York \
    ENABLE_VNC=false \
    DISPLAY=:99

EXPOSE 8080 5900

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD bash /app/scripts/healthcheck.sh

ENTRYPOINT ["tini", "--"]
CMD ["bash", "/app/scripts/entrypoint.sh"]
