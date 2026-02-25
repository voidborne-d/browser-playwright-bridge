/**
 * Playwright script template for OpenClaw browser bridge.
 *
 * Usage:
 *   ./scripts/browser-lock.sh run scripts/my-script.js [args...]
 *
 * Shares cookies/login with OpenClaw browser via same Chrome user-data-dir.
 */

const { chromium } = require('playwright');

const CDP_PORT = process.env.CDP_PORT || '18800';

async function main() {
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const context = browser.contexts()[0];
  const page = await context.newPage();

  try {
    // ====== Your automation here ======

    await page.goto('https://example.com');
    console.log('Title:', await page.title());

    // ==================================
  } finally {
    await page.close();
  }
}

main().then(() => process.exit(0)).catch(e => {
  console.error('❌', e.message);
  process.exit(1);
});
