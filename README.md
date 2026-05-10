# WeatherVane

WeatherVane turns The Weather Channel's RetroCast experience into an HLS stream you can play in VLC, Kodi, Plex, or any M3U8-compatible client.

## How it works

Inside Docker, the stack:

```text
Xvfb (:99, 640x480) -> Chromium -> weather.com/retro/
PulseAudio virtual sink <- browser audio
FFmpeg (x11grab + pulse) -> HLS segments -> nginx (:8080)
```

The resulting stream is served at:

```text
http://localhost:8080/hls/stream.m3u8
```

EPG data is served at:

```text
http://localhost:8080/epg.xml
```

## Quick start

1. Copy `.env.example` to `.env` if you want to override defaults.
2. Build and start the container:

```bash
docker compose build
docker compose up -d
```

3. Wait about a minute for the browser, automation, and HLS pipeline to settle.
4. Open the stream in a player:

```bash
vlc http://localhost:8080/hls/stream.m3u8
```

5. Check service health if needed:

```bash
curl http://localhost:8080/health
```

## Configuration

Key environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOCATION` | empty | Forecast location to set in RetroCast |
| `SCREEN_WIDTH` | `640` | X display width |
| `SCREEN_HEIGHT` | `480` | X display height |
| `FRAME_SAFE_MARGIN` | `12` | Shrinks and insets the page slightly so edge content survives minor capture/player clipping |
| `CAPTURE_MODE` | `full` | Capture the full X display, or set `crop` to use `CAPTURE_*` overrides |
| `FRAMERATE` | `15` | Capture frame rate |
| `CAPTURE_WIDTH` | `640` | Cropped capture width when `CAPTURE_MODE=crop` |
| `CAPTURE_HEIGHT` | `480` | Cropped capture height when `CAPTURE_MODE=crop` |
| `CAPTURE_OFFSET_X` | `0` | Horizontal crop offset when `CAPTURE_MODE=crop` |
| `CAPTURE_OFFSET_Y` | `0` | Vertical crop offset when `CAPTURE_MODE=crop` |
| `VIDEO_BITRATE` | `1200k` | HLS video bitrate |
| `AUDIO_BITRATE` | `128k` | HLS audio bitrate |
| `FFMPEG_PRESET` | `ultrafast` | FFmpeg x264 preset |
| `HLS_SEGMENT_DURATION` | `4` | Segment duration in seconds |
| `HLS_LIST_SIZE` | `5` | Number of playlist entries kept live |
| `HLS_PORT` | `8080` | Host port for nginx/HLS |
| `FRAMING_DEBUG` | `false` | Write X11 and Puppeteer framing artifacts for calibration |
| `FRAMING_DEBUG_DIR` | `/tmp/hls/debug` | Directory for framing screenshots and metrics |
| `EPG_CHANNEL_ID` | `weathervane.retro` | XMLTV channel id used in `/epg.xml` |
| `EPG_CHANNEL_NAME` | `WeatherVane RetroCast` | XMLTV channel display name |
| `EPG_CHANNEL_ICON` | `https://weather.com/retro/assets/icon.png` | XMLTV channel icon URL used in `/epg.xml` |
| `EPG_PROGRAM_TITLE` | `RetroCast Weather Loop` | XMLTV programme title |
| `EPG_PROGRAM_DESCRIPTION` | `Continuous Weather Channel RetroCast stream.` | XMLTV programme description |
| `ENABLE_VNC` | `false` | Expose VNC for visual debugging |

## Important files

- `Dockerfile` - container image definition
- `docker-compose.yml` - runtime wiring and defaults
- `scripts/entrypoint.sh` - orchestrates Xvfb, PulseAudio, Chromium, automation, nginx, and FFmpeg
- `scripts/start-ffmpeg.sh` - capture and HLS generation
- `scripts/start-chromium.sh` - browser startup flags
- `automation/setup-weather.js` - location/start/audio automation, including the Start RetroCast watcher
- `config/nginx.conf` - HLS serving config

## Troubleshooting

- **No audio**: verify `virtual_speaker.monitor` exists in PulseAudio.
- **Black screen**: check that Xvfb is running on `:99`.
- **Edges still look clipped with full capture**: increase `FRAME_SAFE_MARGIN` a bit so the rendered page sits farther away from the stream edges, then use `FRAMING_DEBUG=true` to compare the browser frame and X display artifacts.
- **Top/right edges are cropped**: leave `CAPTURE_MODE=full` for the default full-display capture. If you need manual framing, switch to `CAPTURE_MODE=crop`, enable `FRAMING_DEBUG=true`, and inspect `/tmp/hls/debug` before changing `CAPTURE_*`.
- **High CPU**: the defaults now favor lighter CPU usage (`640x480`, `15fps`, `1200k`, `ultrafast`). If the host is still busy, lower `FRAMERATE` further or reduce the resolution again.
- **Chromium instability**: increase `shm_size` in `docker-compose.yml`.
- **Recurring Chromium D-Bus errors in logs**: the container now starts a private session bus for Chromium, but a few browser warnings from missing desktop services can still appear and are usually harmless if `/health` stays green and the HLS playlist keeps advancing.
- **Need to inspect the browser**: set `ENABLE_VNC=true` and expose port `5900`.

## CI

GitHub Actions builds the Docker image on every push and pull request using `.github/workflows/docker-build.yml`.

Pushes to `main` also publish the container image to GitHub Container Registry as:

```text
ghcr.io/cbulock/weathervane:latest
ghcr.io/cbulock/weathervane:sha-<commit>
```
