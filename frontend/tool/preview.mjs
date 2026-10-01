// CI-only visual smoke check for the compiled Web client.
import { chromium } from '/tmp/jol-ui-check/node_modules/playwright/index.mjs';
import { mkdir } from 'node:fs/promises';
await mkdir('frontend/build/screenshots', { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
const failures = [];
page.on('pageerror', error => failures.push(error.message));
await page.goto('http://localhost:3000');
await page.waitForTimeout(6000);
await page.screenshot({ path: 'frontend/build/screenshots/login-desktop.png' });
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(1000);
await page.screenshot({ path: 'frontend/build/screenshots/login-phone.png' });
await browser.close();
if (failures.length) throw new Error(failures.join('\n'));
