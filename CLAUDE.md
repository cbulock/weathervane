# WeatherVane - Retro Weather IPTV Stream

## What This Project Does

Captures The Weather Channel's RetroCast page (`weather.com/retro/`) in a headless browser inside Docker and streams it as an HLS IPTV stream playable in VLC, Kodi, Plex, or any M3U8-compatible player.

## Architecture

```
Xvfb (:99, 960x720) → Chromium (kiosk) → weather.com/retro/
PulseAudio (virtual sink) ← browser audio
FFmpeg (x11grab + pulse) → HLS segments (.ts) → nginx (:8080) → /hls/stream.m3u8
```

## Key Files

- `Dockerfile` - Debian bookworm-slim with Xvfb, PulseAudio, native Chromium, FFmpeg, nginx, Node.js
- `docker-compose.yml` - Compose config with env vars, shm_size, tmpfs
- `scripts/entrypoint.sh` - Orchestrates startup: Xvfb → PulseAudio → nginx → Chromium → Puppeteer → FFmpeg
- `scripts/start-ffmpeg.sh` - FFmpeg x11grab + pulse → HLS encoding pipeline
- `scripts/start-chromium.sh` - Chromium in kiosk mode with autoplay and CDP enabled
- `automation/setup-weather.js` - Puppeteer script that sets location, clicks START, unmutes audio
- `config/nginx.conf` - Serves HLS segments with correct MIME types and CORS

## About the Target Page

The weather.com/retro/ page is a Nuxt.js (Vue) app that renders a 4:3 retro weather forecast with:
- VHS-style video overlays (clouds.mp4, texture.mp4, grain.mp4)
- Smooth jazz audio via Web Audio API
- Mapbox canvas elements for radar
- A "START RETROCAST" button and "Unmute audio" button
- Location settings panel with city search autocomplete
- ~3 minute forecast cycle that loops continuously

## Development Notes

### Browser Automation Selectors
The CSS selectors in `automation/setup-weather.js` are best-effort guesses. The weather.com DOM may change. When debugging:
1. Set `ENABLE_VNC=true` and connect a VNC client to `localhost:5900`
2. Inspect the page DOM to find current selectors
3. Update the selectors in setup-weather.js

### Common Issues
- **No audio**: Check PulseAudio virtual sink exists (`pactl list sources` should show `virtual_speaker.monitor`)
- **Black screen**: Verify DISPLAY=:99 and Xvfb is running
- **High CPU**: Reduce FRAMERATE to 24, use FFMPEG_PRESET=ultrafast
- **Chromium crash**: Increase shm_size in docker-compose.yml
- **Audio/video drift**: Add `-async 1` or `-itsoffset -1.25` to FFmpeg audio input

### Testing
```bash
docker compose build
docker compose up
# Wait ~60s then:
curl http://localhost:8080/health
vlc http://localhost:8080/hls/stream.m3u8
```

### CI

GitHub Actions builds the Docker image from the repository root `Dockerfile` on every `push` and `pull_request` using `.github/workflows/docker-build.yml`.

### Environment Variables
See `.env.example` for all configurable options. Key ones:
- `LOCATION` - City name (e.g. "New York")
- `SCREEN_WIDTH`/`SCREEN_HEIGHT` - Display resolution (default 960x720)
- `VIDEO_BITRATE` - Encoding quality (default 2500k)
- `ENABLE_VNC` - Debug by viewing the browser (default false)
