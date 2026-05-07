#!/bin/bash
set -euo pipefail

OUTPUT_PATH=${1:-/tmp/hls/epg.xml}
CHANNEL_ID=${EPG_CHANNEL_ID:-weathervane.retro}
CHANNEL_NAME=${EPG_CHANNEL_NAME:-WeatherVane RetroCast}
CHANNEL_ICON=${EPG_CHANNEL_ICON:-https://weather.com/retro/assets/icon.png}
PROGRAM_TITLE=${EPG_PROGRAM_TITLE:-RetroCast Weather Loop}
PROGRAM_DESCRIPTION=${EPG_PROGRAM_DESCRIPTION:-Continuous Weather Channel RetroCast stream.}

xml_escape_text() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g'
}

xml_escape_attr() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

# Uses GNU date syntax; WeatherVane runs on Debian bookworm-slim.
START_TIME=$(date '+%Y%m%d%H%M%S %z')
STOP_TIME=$(date -d '+3650 days' '+%Y%m%d%H%M%S %z')
TMP_PATH="${OUTPUT_PATH}.tmp"

CHANNEL_ID_XML_ATTR=$(xml_escape_attr "$CHANNEL_ID")
CHANNEL_NAME_XML_TEXT=$(xml_escape_text "$CHANNEL_NAME")
CHANNEL_ICON_XML_ATTR=$(xml_escape_attr "$CHANNEL_ICON")
PROGRAM_TITLE_XML_TEXT=$(xml_escape_text "$PROGRAM_TITLE")
PROGRAM_DESCRIPTION_XML_TEXT=$(xml_escape_text "$PROGRAM_DESCRIPTION")

cat > "$TMP_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="WeatherVane" source-info-name="weather.com/retro">
  <channel id="${CHANNEL_ID_XML_ATTR}">
    <display-name>${CHANNEL_NAME_XML_TEXT}</display-name>
    <icon src="${CHANNEL_ICON_XML_ATTR}" />
  </channel>
  <programme start="${START_TIME}" stop="${STOP_TIME}" channel="${CHANNEL_ID_XML_ATTR}">
    <title lang="en">${PROGRAM_TITLE_XML_TEXT}</title>
    <desc lang="en">${PROGRAM_DESCRIPTION_XML_TEXT}</desc>
  </programme>
</tv>
EOF

mv "$TMP_PATH" "$OUTPUT_PATH"
