# WeatherVane

WeatherVane turns The Weather Channel's RetroCast experience into an HLS stream you can play in VLC, Kodi, Plex, or any M3U8-compatible client.

## How it works

Inside Docker, the stack:

```text
Xvfb (:99, 960x720) -> Chromium -> weather.com/retro/
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
| `SCREEN_WIDTH` | `960` | X display width |
| `SCREEN_HEIGHT` | `720` | X display height |
| `FRAMERATE` | `30` | Capture frame rate |
| `CAPTURE_WIDTH` | `930` | Width of the captured content window |
| `CAPTURE_HEIGHT` | `600` | Height of the captured content window |
| `CAPTURE_OFFSET_X` | `15` | Horizontal capture offset |
| `CAPTURE_OFFSET_Y` | `0` | Vertical capture offset |
| `VIDEO_BITRATE` | `2500k` | HLS video bitrate |
| `AUDIO_BITRATE` | `128k` | HLS audio bitrate |
| `FFMPEG_PRESET` | `veryfast` | FFmpeg x264 preset |
| `HLS_SEGMENT_DURATION` | `4` | Segment duration in seconds |
| `HLS_LIST_SIZE` | `5` | Number of playlist entries kept live |
| `HLS_PORT` | `8080` | Host port for nginx/HLS |
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
- **High CPU**: lower `FRAMERATE` or use `FFMPEG_PRESET=ultrafast`.
- **Chromium instability**: increase `shm_size` in `docker-compose.yml`.
- **Need to inspect the browser**: set `ENABLE_VNC=true` and expose port `5900`.

## CI

GitHub Actions builds the Docker image on every push and pull request using `.github/workflows/docker-build.yml`.

Pushes to `main` also publish the container image to GitHub Container Registry as:

```text
ghcr.io/cbulock/weathervane:latest
ghcr.io/cbulock/weathervane:sha-<commit>
```
