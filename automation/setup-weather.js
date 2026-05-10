const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const LOCATION = process.env.LOCATION || '';
const SETUP_TIMEOUT = 60000;
const CDP_HOST = process.env.CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.CDP_PORT || '9222';
const SCREEN_WIDTH = Number.parseInt(process.env.SCREEN_WIDTH || '640', 10);
const SCREEN_HEIGHT = Number.parseInt(process.env.SCREEN_HEIGHT || '480', 10);
const FRAME_SAFE_MARGIN = Number.parseInt(process.env.FRAME_SAFE_MARGIN || '12', 10);
const WATCH_MODE = process.argv.includes('--watch');
const WATCH_INTERVAL_MS = Number.parseInt(process.env.START_BUTTON_WATCH_INTERVAL_MS || '5000', 10);
const FRAMING_DEBUG = process.env.FRAMING_DEBUG === 'true';
const FRAMING_DEBUG_DIR = process.env.FRAMING_DEBUG_DIR || '/tmp/hls/debug';

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function normalizeText(value) {
  return (value || '').replace(/\s+/g, ' ').trim();
}

async function clickHandle(page, handle) {
  await handle.evaluate(el => el.scrollIntoView({ block: 'center', inline: 'center' }));
  await sleep(250);

  try {
    await handle.click({ delay: 50 });
    return;
  } catch (error) {
    const box = await handle.boundingBox();
    if (box) {
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      return;
    }
    await handle.evaluate(el => el.click());
  }
}

async function dispatchFullClick(handle) {
  await handle.evaluate(el => {
    const centerX = Math.max(1, Math.floor(el.clientWidth / 2));
    const centerY = Math.max(1, Math.floor(el.clientHeight / 2));
    const options = {
      bubbles: true,
      cancelable: true,
      composed: true,
      clientX: centerX,
      clientY: centerY,
      button: 0,
      buttons: 1,
    };

    el.dispatchEvent(new PointerEvent('pointerdown', { ...options, pointerId: 1, pointerType: 'mouse', isPrimary: true }));
    el.dispatchEvent(new MouseEvent('mousedown', options));
    el.dispatchEvent(new PointerEvent('pointerup', { ...options, pointerId: 1, pointerType: 'mouse', isPrimary: true }));
    el.dispatchEvent(new MouseEvent('mouseup', options));
    el.dispatchEvent(new MouseEvent('click', options));
  });
}

async function isCountdownVisible(page) {
  return page.evaluate(() =>
    /retrocast now begins/i.test((document.body.innerText || '').replace(/\s+/g, ' ').trim())
  );
}

async function waitForCountdownToClear(page, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (!(await isCountdownVisible(page))) {
      return true;
    }
    await sleep(500);
  }
  return false;
}

async function findButtonByText(page, pattern) {
  const buttons = await page.$$('button');
  for (const btn of buttons) {
    const text = normalizeText(await page.evaluate(el => el.textContent, btn));
    if (pattern.test(text)) {
      return btn;
    }
  }
  return null;
}

async function isElementVisible(handle) {
  return handle.evaluate(el => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return (
      rect.width > 0 &&
      rect.height > 0 &&
      style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      style.opacity !== '0'
    );
  });
}

async function normalizeViewport(page) {
  await page.setViewport({
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
    deviceScaleFactor: 1,
  });

  const session = await page.target().createCDPSession();
  await session.send('Emulation.setDeviceMetricsOverride', {
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: SCREEN_WIDTH,
    screenHeight: SCREEN_HEIGHT,
  });

  try {
    const { windowId } = await session.send('Browser.getWindowForTarget');
    await session.send('Browser.setWindowBounds', {
      windowId,
      bounds: {
        left: 0,
        top: 0,
        width: SCREEN_WIDTH,
        height: SCREEN_HEIGHT,
      },
    });
  } catch (error) {
    console.log(`Window bounds adjustment skipped: ${error.message}`);
  }
}

async function hideCursor(page) {
  await page.addStyleTag({
    content: `
      *,
      *::before,
      *::after {
        cursor: none !important;
      }
    `,
  });
}

async function applySafeFraming(page) {
  const framing = await page.evaluate(safeMargin => {
    const root = document.querySelector('#__nuxt') || document.body.firstElementChild || document.body;
    if (!root) {
      return null;
    }

    if (!root.dataset.weathervaneOriginalStyle) {
      root.dataset.weathervaneOriginalStyle = root.getAttribute('style') || '';
    }

    root.setAttribute('style', root.dataset.weathervaneOriginalStyle);

    const rect = root.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    const availableWidth = Math.max(1, viewportWidth - safeMargin * 2);
    const availableHeight = Math.max(1, viewportHeight - safeMargin * 2);
    const scale = Math.min(availableWidth / rect.width, availableHeight / rect.height, 1);
    const offsetX = Math.max(safeMargin, (viewportWidth - rect.width * scale) / 2);
    const offsetY = Math.max(safeMargin, (viewportHeight - rect.height * scale) / 2);

    document.documentElement.style.margin = '0';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.margin = '0';
    document.body.style.overflow = 'hidden';
    document.body.style.backgroundColor = '#000';

    root.style.position = 'absolute';
    root.style.left = `${offsetX}px`;
    root.style.top = `${offsetY}px`;
    root.style.width = `${rect.width}px`;
    root.style.height = `${rect.height}px`;
    root.style.transformOrigin = 'top left';
    root.style.transform = `scale(${scale})`;

    root.dataset.weathervaneScale = scale.toFixed(6);
    root.dataset.weathervaneOffsetX = offsetX.toFixed(2);
    root.dataset.weathervaneOffsetY = offsetY.toFixed(2);
    root.dataset.weathervaneSafeMargin = String(safeMargin);

    return {
      scale,
      offsetX,
      offsetY,
      width: rect.width,
      height: rect.height,
      viewportWidth,
      viewportHeight,
      safeMargin,
    };
  }, FRAME_SAFE_MARGIN);

  if (framing) {
    console.log(
      `Applied safe framing scale=${framing.scale.toFixed(4)} offset=${framing.offsetX.toFixed(1)},${framing.offsetY.toFixed(1)} margin=${framing.safeMargin}`
    );
  }
}

async function collectFramingMetrics(page) {
  return page.evaluate(() => {
    const root = document.querySelector('#__nuxt') || document.body.firstElementChild || document.body;
    const summarize = (selector, limit = 10) =>
      Array.from(document.querySelectorAll(selector)).slice(0, limit).map(el => {
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        return {
          tag: el.tagName,
          id: el.id || '',
          className: typeof el.className === 'string' ? el.className : '',
          text: (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 120),
          rect: {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
            right: rect.right,
            bottom: rect.bottom,
          },
          position: style.position,
          display: style.display,
          overflow: style.overflow,
        };
      });

    return {
      capturedAt: new Date().toISOString(),
      window: {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        outerWidth: window.outerWidth,
        outerHeight: window.outerHeight,
        devicePixelRatio: window.devicePixelRatio,
      },
      document: {
        clientWidth: document.documentElement.clientWidth,
        clientHeight: document.documentElement.clientHeight,
        scrollWidth: document.documentElement.scrollWidth,
        scrollHeight: document.documentElement.scrollHeight,
      },
      visualViewport: window.visualViewport
        ? {
            width: window.visualViewport.width,
            height: window.visualViewport.height,
            offsetLeft: window.visualViewport.offsetLeft,
            offsetTop: window.visualViewport.offsetTop,
            scale: window.visualViewport.scale,
          }
        : null,
      framing: root
        ? {
            scale: root.dataset.weathervaneScale || null,
            offsetX: root.dataset.weathervaneOffsetX || null,
            offsetY: root.dataset.weathervaneOffsetY || null,
            safeMargin: root.dataset.weathervaneSafeMargin || null,
          }
        : null,
      elements: {
        main: summarize('main', 2),
        buttons: summarize('button', 8),
        videos: summarize('video', 8),
        canvases: summarize('canvas', 8),
      },
    };
  });
}

async function writeFramingDebugArtifacts(page, label) {
  if (!FRAMING_DEBUG) {
    return;
  }

  fs.mkdirSync(FRAMING_DEBUG_DIR, { recursive: true });

  const screenshotPath = path.join(FRAMING_DEBUG_DIR, `${label}.png`);
  const metricsPath = path.join(FRAMING_DEBUG_DIR, `${label}-metrics.json`);
  const metrics = await collectFramingMetrics(page);

  await page.screenshot({ path: screenshotPath });
  fs.writeFileSync(metricsPath, `${JSON.stringify(metrics, null, 2)}\n`, 'utf8');
  console.log(`Wrote framing debug artifacts to ${FRAMING_DEBUG_DIR}`);
}

async function dismissOverlays(page) {
  // Try to dismiss cookie consent or other overlays
  try {
    const selectors = [
      '[aria-label="Close"]',
      '[data-testid="close"]',
      'button.consent-accept',
      '#onetrust-accept-btn-handler',
      '.banner-close',
    ];
    for (const sel of selectors) {
      const el = await page.$(sel);
      if (el) {
        await el.click();
        await sleep(500);
      }
    }
  } catch (e) {
    // Overlays are optional, ignore errors
  }
}

async function setLocation(page, location) {
  console.log(`Setting location to: ${location}`);

  // Click the gear/settings button
  const settingsBtn = await page.waitForSelector(
    '[aria-label="Change Location"], [aria-label="Settings"], button[class*="settings"], button[class*="gear"]',
    { timeout: 15000 }
  );
  await settingsBtn.click();
  await sleep(1000);

  // Find and fill the search input
  const searchInput = await page.waitForSelector(
    'input[placeholder*="Search"], input[placeholder*="search"], input[type="search"]',
    { timeout: 10000 }
  );
  await searchInput.click({ clickCount: 3 }); // select all existing text
  await searchInput.type(location, { delay: 50 });
  await sleep(2000); // Wait for autocomplete API response

  // Click first autocomplete result
  const firstResult = await page.waitForSelector(
    '[class*="autocomplete"] li, [class*="suggestion"] li, [class*="dropdown"] li, [class*="search-result"], [role="option"]',
    { timeout: 10000 }
  );
  await firstResult.click();
  await sleep(1500);

  // Close settings panel
  try {
    const closeBtn = await page.waitForSelector(
      '[aria-label="Close"], [class*="close"], button[class*="back"]',
      { timeout: 5000 }
    );
    await closeBtn.click();
  } catch (e) {
    // Settings may auto-close after selection
  }
  await sleep(1000);
  console.log('Location set successfully');
}

async function startRetrocast(page) {
  console.log('Starting RetroCast...');
  await normalizeViewport(page);
  await applySafeFraming(page);

  const startBtn = await findButtonByText(page, /start\s*retrocast/i);

  if (!startBtn) {
    throw new Error('Could not find START RETROCAST button');
  }

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    await dispatchFullClick(startBtn);
    const countdownCleared = await waitForCountdownToClear(page, 8000);
    await normalizeViewport(page);
    await applySafeFraming(page);
    console.log(`Clicked Start RetroCast control on attempt ${attempt}`);

    if (countdownCleared) {
      console.log(`RetroCast left countdown state on attempt ${attempt}`);
      break;
    }
  }
  console.log('RetroCast started');
}

async function clickStartIfPresent(page) {
  const startBtn = await findButtonByText(page, /start\s*retrocast/i);
  if (!startBtn) {
    return false;
  }

  if (!(await isElementVisible(startBtn))) {
    return false;
  }

  console.log('Start RetroCast button detected; clicking it.');
  await dispatchFullClick(startBtn);
  const countdownCleared = await waitForCountdownToClear(page, 8000);
  await normalizeViewport(page);
  await applySafeFraming(page);
  await hideCursor(page);
  await writeFramingDebugArtifacts(page, 'watch-recovery');

  if (countdownCleared) {
    console.log('Start RetroCast click cleared the countdown state.');
  }

  return true;
}

async function unmuteAudio(page) {
  console.log('Attempting to unmute audio...');
  await sleep(3000); // Wait for retrocast to begin playing

  // Try clicking unmute button
  try {
    const unmuteBtn = await page.waitForSelector(
      '[aria-label*="nmute"], [aria-label*="udio"], button[class*="mute"], button[class*="audio"], button[class*="sound"]',
      { timeout: 10000 }
    );
    await unmuteBtn.click();
    console.log('Audio unmuted via button');
  } catch (e) {
    // Fallback: try to find any button with unmute/audio text
    try {
      const buttons = await page.$$('button');
      for (const btn of buttons) {
        const text = await page.evaluate(
          el => el.textContent + ' ' + (el.getAttribute('aria-label') || ''),
          btn
        );
        if (text && (text.toLowerCase().includes('unmute') || text.toLowerCase().includes('audio'))) {
          await btn.click();
          console.log('Audio unmuted via text match');
          return;
        }
      }
    } catch (e2) {
      // Ignore - autoplay policy flag should handle this
    }
    console.log('Could not find unmute button - autoplay policy should handle audio');
  }
}

async function main() {
  console.log('Connecting to Chromium...');
  const browser = await puppeteer.connect({
    browserURL: `http://${CDP_HOST}:${CDP_PORT}`,
  });

  const pages = await browser.pages();
  const page = pages[0];

  await page.waitForSelector('body', { timeout: 30000 });
  await normalizeViewport(page);
  await applySafeFraming(page);
  await hideCursor(page);
  await sleep(3000);

  if (WATCH_MODE) {
    console.log(`Watching for Start RetroCast button every ${WATCH_INTERVAL_MS}ms`);
    while (true) {
      try {
        await normalizeViewport(page);
        await applySafeFraming(page);
        await hideCursor(page);
        await dismissOverlays(page);
        const clicked = await clickStartIfPresent(page);
        if (clicked) {
          await unmuteAudio(page);
        }
      } catch (error) {
        console.error(`Watcher iteration failed: ${error.message}`);
      }

      await sleep(WATCH_INTERVAL_MS);
    }
  }

  await dismissOverlays(page);

  if (LOCATION) {
    try {
      await setLocation(page, LOCATION);
    } catch (e) {
      console.error('Failed to set location:', e.message);
      console.log('Continuing with default location...');
    }
  }

  try {
    await startRetrocast(page);
  } catch (e) {
    console.error('Failed to start retrocast:', e.message);
    throw e;
  }

  await unmuteAudio(page);
  await normalizeViewport(page);
  await applySafeFraming(page);
  await hideCursor(page);
  await writeFramingDebugArtifacts(page, 'post-setup');
  await sleep(1000);

  console.log('Setup complete. RetroCast is running.');

  // Disconnect (don't close - browser keeps running)
  browser.disconnect();
  process.exit(0);
}

main().catch(err => {
  console.error('Automation failed:', err);
  process.exit(1);
});
