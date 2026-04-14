#!/bin/bash
set -euo pipefail

OUTPUT_PATH=${1:-/tmp/hls/epg.xml}
CHANNEL_ID=${EPG_CHANNEL_ID:-weathervane.retro}
CHANNEL_NAME=${EPG_CHANNEL_NAME:-WeatherVane RetroCast}
PROGRAM_TITLE=${EPG_PROGRAM_TITLE:-RetroCast Weather Loop}
PROGRAM_DESCRIPTION=${EPG_PROGRAM_DESCRIPTION:-Continuous Weather Channel RetroCast stream.}

# Uses GNU date syntax; WeatherVane runs on Debian bookworm-slim.
START_TIME=$(date '+%Y%m%d%H%M%S %z')
STOP_TIME=$(date -d '+3650 days' '+%Y%m%d%H%M%S %z')
TMP_PATH="${OUTPUT_PATH}.tmp"

cat > "$TMP_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="WeatherVane" source-info-name="weather.com/retro">
  <channel id="${CHANNEL_ID}">
    <display-name>${CHANNEL_NAME}</display-name>
  </channel>
  <programme start="${START_TIME}" stop="${STOP_TIME}" channel="${CHANNEL_ID}">
    <title lang="en">${PROGRAM_TITLE}</title>
    <desc lang="en">${PROGRAM_DESCRIPTION}</desc>
  </programme>
</tv>
EOF

mv "$TMP_PATH" "$OUTPUT_PATH"
