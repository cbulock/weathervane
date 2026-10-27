const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');

const image = process.env.WEATHERVANE_TEST_IMAGE || 'weathervane-weathervane:latest';
const name = `weathervane-on-demand-test-${process.pid}`;

function docker(...args) {
  return execFileSync('docker', args, { encoding: 'utf8', timeout: 30000 }).trim();
}

function inContainer(command) {
  return docker('exec', name, 'sh', '-lc', command);
}

function styleCount() {
  const script = 'const p = require("puppeteer-core"); p.connect({browserURL:"http://127.0.0.1:9222"}).then(async b => { const page = (await b.pages())[0]; console.log(await page.evaluate(() => document.querySelectorAll("style").length)); b.disconnect(); });';
  return Number(docker('exec', '-w', '/app/automation', name, 'node', '-e', script));
}

async function waitFor(check, timeoutMs, description) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      if (check()) return;
    } catch (_) {
      // Startup and teardown briefly make exec unavailable.
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  assert.fail(`Timed out waiting for ${description}`);
}

test('on-demand mode leaves Chromium idle, starts a stream, and stops it after inactivity', { timeout: 180000 }, async () => {
  try {
    docker('run', '-d', '--rm', '--name', name, '--shm-size', '2g',
      '--tmpfs', '/tmp/hls:size=100m', '-e', 'FFMPEG_ON_DEMAND=true',
      '-e', 'FFMPEG_IDLE_TIMEOUT=15', '-e', 'FFMPEG_MANAGER_POLL_INTERVAL=1', image);

    await waitFor(() => inContainer('curl -fsS http://localhost:8080/health >/dev/null 2>&1 && test -f /tmp/ffmpeg-manager.pid') === '', 30000, 'nginx and manager');
    assert.equal(inContainer('test ! -f /tmp/chromium.pid && test ! -f /tmp/ffmpeg.pid && echo idle'), 'idle');

    inContainer('curl -s -o /dev/null http://localhost:8080/hls/stream.m3u8');
    await waitFor(() => inContainer('test -f /tmp/browser-started-at && echo starting') === 'starting', 10000, 'browser startup');
    assert.equal(inContainer('bash /app/scripts/healthcheck.sh && echo healthy'), 'healthy');

    await waitFor(() => {
      inContainer('curl -s -o /dev/null http://localhost:8080/hls/stream.m3u8');
      return inContainer('test -s /tmp/hls/stream.m3u8 && test -f /tmp/chromium.pid && test -f /tmp/ffmpeg.pid && echo live') === 'live';
    }, 100000, 'live HLS stream');

    const stylesBefore = styleCount();
    await new Promise(resolve => setTimeout(resolve, 12000));
    assert.equal(styleCount(), stylesBefore, 'the watcher should not inject styles while the page is stable');

    await waitFor(() => inContainer('test ! -f /tmp/chromium.pid && test ! -f /tmp/ffmpeg.pid && ! pgrep -x chromium && ! pgrep -x ffmpeg && echo idle') === 'idle', 40000, 'idle shutdown');
    assert.equal(inContainer('curl -fsS http://localhost:8080/health'), 'OK');

    await waitFor(() => {
      inContainer('curl -s -o /dev/null http://localhost:8080/hls/stream.m3u8');
      return inContainer('test -s /tmp/hls/stream.m3u8 && test -f /tmp/chromium.pid && test -f /tmp/ffmpeg.pid && echo live') === 'live';
    }, 100000, 'stream after a second viewer arrives');
  } finally {
    try { docker('rm', '-f', name); } catch (_) { /* Already stopped. */ }
  }
});

test('always-on mode starts Chromium and FFmpeg without a viewer', { timeout: 90000 }, async () => {
  const alwaysName = `${name}-always`;
  try {
    docker('run', '-d', '--rm', '--name', alwaysName, '--shm-size', '2g',
      '--tmpfs', '/tmp/hls:size=100m', '-e', 'FFMPEG_ON_DEMAND=false', image);
    await waitFor(() => docker('exec', alwaysName, 'sh', '-lc',
      'test -f /tmp/chromium.pid && test -f /tmp/ffmpeg.pid && echo live') === 'live',
    70000, 'always-on capture');
  } finally {
    try { docker('rm', '-f', alwaysName); } catch (_) { /* Already stopped. */ }
  }
});
