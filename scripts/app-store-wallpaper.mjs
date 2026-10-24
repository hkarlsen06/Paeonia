#!/usr/bin/env node
// Draws the dark plum image that the App Store Home Screen capture (01-widget) takes its wallpaper
// colour from, at the iPhone 17 Pro Max screen size. scripts/capture-app-store-screenshots.py says
// how to set it. The noise keeps the dark gradient from banding.
//
// Usage: node scripts/app-store-wallpaper.mjs <output.png>
import path from 'node:path';
import { chromium } from 'playwright';

const W = 1320, H = 2868;
const output = path.resolve(process.argv[2] ?? 'paeonia-wallpaper.png');
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.setContent(`<body style="margin:0"><canvas width="${W}" height="${H}"></canvas></body>`);
  await page.evaluate(([W, H]) => {
    const c = document.querySelector('canvas').getContext('2d');
    const base = c.createLinearGradient(0, 0, W * 0.3, H);
    base.addColorStop(0, '#2b0b1f');
    base.addColorStop(0.55, '#1a0612');
    base.addColorStop(1, '#10030b');
    c.fillStyle = base;
    c.fillRect(0, 0, W, H);
    for (const [x, y, r, color] of [[0.2, 0.18, 0.95, '#6a2550a0'], [0.95, 0.78, 0.8, '#7a2d5740']]) {
      const glow = c.createRadialGradient(x * W, y * H, 0, x * W, y * H, r * W);
      glow.addColorStop(0, color);
      glow.addColorStop(1, '#00000000');
      c.fillStyle = glow;
      c.fillRect(0, 0, W, H);
    }
    const image = c.getImageData(0, 0, W, H);
    let seed = 7;
    for (let i = 0; i < image.data.length; i += 4) {
      seed = (seed + 0x6d2b79f5) | 0; // mulberry32
      let t = Math.imul(seed ^ (seed >>> 15), seed | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      const n = (((t ^ (t >>> 14)) >>> 0) % 5) - 2;
      for (let k = 0; k < 3; k++) image.data[i + k] = Math.max(0, Math.min(255, image.data[i + k] + n));
    }
    c.putImageData(image, 0, 0);
  }, [W, H]);
  await page.locator('canvas').screenshot({ path: output });
  console.log(`Wrote ${output}`);
} finally {
  await browser.close();
}
