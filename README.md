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
| `ENABLE_GPU` | `false` | Opt in to Intel VAAPI acceleration on Linux Docker hosts with `/dev/dri` passthrough |
| `VAAPI_DEVICE` | `/dev/dri/renderD128` | Intel render node passed into the container when `ENABLE_GPU=true` |
| `LIBVA_DRIVER_NAME` | `iHD` | Intel VAAPI driver to load; set `i965` for older Intel GPUs if needed |
| `VAAPI_QP` | `23` | Constant-quality QP used by the VAAPI encoder on drivers that only support CQP |
| `VAAPI_QUALITY` | `4` | VAAPI encode speed/quality tradeoff; higher is faster |
| `HLS_SEGMENT_DURATION` | `4` | Segment duration in seconds |
| `HLS_LIST_SIZE` | `5` | Number of playlist entries kept live |
| `HLS_PORT` | `8080` | Host port for nginx/HLS |
| `HLS_ROOT` | `/dev/shm/hls` | Preferred in-memory backing directory for HLS artifacts when `/tmp/hls` is not already mounted as tmpfs |
| `FFMPEG_ON_DEMAND` | `true` | Start FFmpeg only after recent HLS requests instead of running continuously |
| `FFMPEG_IDLE_TIMEOUT` | `60` | Seconds of no HLS activity before FFmpeg stops in on-demand mode |
| `FFMPEG_MANAGER_POLL_INTERVAL` | `2` | Seconds between on-demand manager checks for recent HLS activity |
| `FFMPEG_STARTUP_GRACE` | `20` | Health-check grace window after FFmpeg starts in on-demand mode |
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
- `scripts/gpu-common.sh` - shared Intel VAAPI runtime checks for Chromium and FFmpeg
- `scripts/on-demand-common.sh` - shared helpers for HLS activity tracking and FFmpeg on-demand state
- `scripts/manage-ffmpeg.sh` - on-demand FFmpeg supervisor for recent HLS traffic
- `scripts/start-ffmpeg.sh` - capture and HLS generation
- `scripts/start-chromium.sh` - browser startup flags
- `automation/setup-weather.js` - location/start/audio automation, including the Start RetroCast watcher
- `config/nginx.conf` - HLS serving config

## Optional Intel iGPU mode

WeatherVane now has an **opt-in** Intel VAAPI mode. The default path is still software rendering and software encoding.

To enable Intel iGPU acceleration on a Linux Docker host:

1. Set `ENABLE_GPU=true` in `.env`.
2. Pass the Intel render node into the container by uncommenting the `devices` and `group_add` hints in `docker-compose.yml` or by providing equivalent Docker runtime flags.
3. Leave `VAAPI_DEVICE=/dev/dri/renderD128` unless your Intel GPU uses a different render node.
4. If VAAPI initialization fails on older Intel hardware, try `LIBVA_DRIVER_NAME=i965`.

This first pass keeps the current Xvfb display path. That means:

- **FFmpeg** can use Intel VAAPI for H.264 encoding.
- **Chromium** can enable Intel VAAPI media acceleration as a best-effort path.
- **Chromium compositing stays software-based** under Xvfb, so this is not full GPU rendering for the browser UI.
- Some Intel VAAPI drivers only support **CQP** rate control for H.264. WeatherVane therefore uses `VAAPI_QP` and `VAAPI_QUALITY` for the hardware encode path instead of forcing bitrate-based RC modes.

## Optional on-demand FFmpeg mode

WeatherVane can also run FFmpeg **only while the HLS stream has recent viewer traffic**.

When `FFMPEG_ON_DEMAND=true`:

1. nginx records `/hls/` requests into a local activity log.
2. A small manager loop starts FFmpeg when recent HLS requests appear.
3. FFmpeg stops after `FFMPEG_IDLE_TIMEOUT` seconds with no recent HLS activity.

This reduces idle CPU usage, but it changes behavior:

- The first viewer after an idle period may see a short cold-start delay while FFmpeg creates a fresh playlist and segments.
- `/health` stays green while the container is intentionally idle, as long as Chromium and the FFmpeg manager are healthy.
- “Active connection” means **recent HLS requests**, not a single long-lived client socket.
- The manager keys off real timestamped request entries, not just the existence of the activity log file.

## In-memory HLS storage

WeatherVane now prefers to keep live HLS artifacts in memory instead of on disk:

- In plain `docker run` setups, startup points `/tmp/hls` at `HLS_ROOT`, which defaults to `/dev/shm/hls`.
- In Compose, the existing tmpfs mount on `/tmp/hls` is already memory-backed, so startup keeps using that RAM-backed path.
- Startup logs now print the resolved HLS backing path so it is easier to confirm whether `/tmp/hls` is landing on tmpfs or `/dev/shm`.

This keeps the nginx and script paths stable while moving the playlist and transport stream segments onto memory-backed storage by default.

## Troubleshooting

- **No audio**: verify `virtual_speaker.monitor` exists in PulseAudio.
- **Black screen**: check that Xvfb is running on `:99`.
- **Edges still look clipped with full capture**: increase `FRAME_SAFE_MARGIN` a bit so the rendered page sits farther away from the stream edges, then use `FRAMING_DEBUG=true` to compare the browser frame and X display artifacts.
- **Top/right edges are cropped**: leave `CAPTURE_MODE=full` for the default full-display capture. If you need manual framing, switch to `CAPTURE_MODE=crop`, enable `FRAMING_DEBUG=true`, and inspect `/tmp/hls/debug` before changing `CAPTURE_*`.
- **High CPU**: the defaults now favor lighter CPU usage (`640x480`, `15fps`, `1200k`, `ultrafast`). If the host is still busy, lower `FRAMERATE` further or reduce the resolution again.
- **GPU mode fails immediately**: confirm you are using an x86 Linux build, `ENABLE_GPU=true`, and `/dev/dri/renderD128` is mounted into the container with access to the host `render` group.
- **FFmpeg VAAPI fails on older Intel graphics**: try `LIBVA_DRIVER_NAME=i965` instead of `iHD`.
- **FFmpeg VAAPI rejects bitrate/rate-control settings**: the current hardware path uses CQP by default. Tune `VAAPI_QP` and `VAAPI_QUALITY` rather than expecting `VIDEO_BITRATE` to control the Intel VAAPI encoder on every driver.
- **Browser GPU mode does not reduce all Chromium CPU usage**: expected. With Xvfb, Chromium can use VAAPI/media acceleration but not full GPU compositing.
- **On-demand mode does not start instantly**: expected. The first HLS request only signals activity; FFmpeg still needs a moment to start and create a fresh playlist.
- **On-demand mode never starts FFmpeg**: confirm the client is requesting `/hls/stream.m3u8` or segment files through nginx and that `/tmp/hls/viewer-activity.log` is being updated.
- **Logs still mention `/tmp/hls`**: the public in-container path stays `/tmp/hls`, but startup logs and FFmpeg output now show the resolved backing path (for example `/dev/shm/hls`) when memory-backed storage is active.
- **Need the in-memory files somewhere else**: override `HLS_ROOT` and restart the container. WeatherVane still serves the stream from `/hls/...`; `HLS_ROOT` only changes the backing path inside the container.
- **Chromium instability**: increase `shm_size` in `docker-compose.yml`.
- **Recurring D-Bus connection errors in logs**: the container now starts private session and system D-Bus instances during startup. If you still see repeated `system_bus_socket` connection failures, you are likely running an older image/container.
- **Single Chromium `UPower` D-Bus warning**: a one-off `org.freedesktop.UPower` lookup failure can still appear in minimal containers because no power-management service is installed. It is usually harmless if Chromium reaches ready state and `/health` stays green.
- **Need to inspect the browser**: set `ENABLE_VNC=true` and expose port `5900`.

## CI

GitHub Actions builds the Docker image on every push and pull request using `.github/workflows/docker-build.yml`.

Pushes to `main` also publish the container image to GitHub Container Registry as:

```text
ghcr.io/cbulock/weathervane:latest
ghcr.io/cbulock/weathervane:sha-<commit>
```
