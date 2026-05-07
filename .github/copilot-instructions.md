# Copilot Instructions for WeatherVane

## Build, test, and lint commands

This repository is primarily validated through Docker image builds and container smoke checks. There is no dedicated lint configuration or standalone unit-test suite in the repo today.

```bash
# Build the image locally
docker compose build

# Start the stream stack
docker compose up -d

# Smoke check the published health endpoint
curl http://localhost:8080/health

# Run a single in-container health check
docker compose exec weathervane bash /app/scripts/healthcheck.sh

# Stop the stack
docker compose down
```

CI builds the repository root `Dockerfile` via `.github/workflows/docker-build.yml` on every `push` and `pull_request`, and pushes `ghcr.io/<repo>:latest` plus `ghcr.io/<repo>:sha-<commit>` on pushes to `main`.

## High-level architecture

WeatherVane is a single-container streaming pipeline, not a traditional web app with an internal API/backend/frontend split.

The container starts a virtual X display with Xvfb on `:99`, launches PulseAudio with a `virtual_speaker` null sink, opens Chromium in kiosk/app mode against `https://weather.com/retro/`, and then uses Puppeteer (`automation/setup-weather.js`) to connect over Chrome DevTools on port `9222`. The automation script normalizes the viewport, dismisses overlays, optionally sets the forecast location, clicks **START RETROCAST**, unmutes audio, and then stays alive in a watch mode that re-clicks the start button if the page falls back to a start/countdown state.

FFmpeg captures the X11 display and PulseAudio monitor source, crops the browser output using `CAPTURE_*` variables, scales it to `SCREEN_WIDTH` x `SCREEN_HEIGHT`, and writes rolling HLS segments plus `stream.m3u8` into `/tmp/hls`. nginx serves `/tmp/hls` at `/hls/`, exposes `/epg.xml` from the generated XMLTV file, and redirects `/` to `/hls/stream.m3u8`.

The startup order in `scripts/entrypoint.sh` matters: Xvfb -> PulseAudio -> EPG generation -> nginx -> Chromium -> initial browser automation -> background watcher -> FFmpeg. Cleanup also depends on pidfiles written under `/tmp`.

## Key conventions

- Environment variables are the main configuration surface. Defaults are defined in the `Dockerfile`, surfaced in `.env.example`, passed through `docker-compose.yml`, and consumed again in shell scripts and Puppeteer. When adding or renaming config, keep all of those layers in sync.
- The browser automation is intentionally selector-tolerant because `weather.com/retro/` is an external Nuxt/Vue app that can change without warning. Prefer updating the selector lists and text-matching helpers in `automation/setup-weather.js` instead of rewriting the startup flow.
- The Start RetroCast control is not handled with a plain click alone. `setup-weather.js` uses synthesized pointer and mouse events plus a persistent `--watch` mode because the page can ignore simpler clicks or return to a start state later.
- `SCREEN_WIDTH` and `SCREEN_HEIGHT` control the virtual display and final encoded output, while `CAPTURE_WIDTH`, `CAPTURE_HEIGHT`, `CAPTURE_OFFSET_X`, and `CAPTURE_OFFSET_Y` control the crop region FFmpeg grabs from the X display. If output framing is wrong, adjust both sets together.
- XMLTV channel metadata now includes a configurable `EPG_CHANNEL_ICON`, which defaults to `https://weather.com/retro/assets/icon.png`. Keep that env var aligned across `.env.example`, `docker-compose.yml`, the `Dockerfile`, and `scripts/generate-epg.sh`.
- `scripts/healthcheck.sh` is the real readiness contract: nginx must answer `/health`, `/tmp/hls/stream.m3u8` must exist and be fresh, and both FFmpeg and Chromium must still be alive.
- Runtime artifacts are disposable and live under `/tmp`: HLS output in `/tmp/hls`, Chromium profile in `/tmp/chromium-profile`, and process tracking in `/tmp/*.pid`. New runtime helpers should follow that pattern so entrypoint cleanup and container health remain coherent.

## Relevant MCP usage

If an MCP server is available for Playwright/browser inspection, use it to inspect the live `weather.com/retro/` DOM before changing `automation/setup-weather.js`. It is most useful for selector breakage around the location picker, the **START RETROCAST** control, overlays/cookie banners, and audio/unmute controls.
