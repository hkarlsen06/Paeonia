#!/usr/bin/env node
// Render App Store screenshots with 3D iPhone 17 Pro Max and iPad Pro 13-inch models around
// unmodified simulator captures. Every panel of a device is cut from one wide canvas. Each device is
// centred in the space between its caption and the bottom of the panel. The render fails when a
// device crosses a panel edge or does not fit under its caption, or a headline does not take exactly
// two lines. The models are in lib/device3d.mjs.
//
// Usage: node scripts/render-3d-screenshots.mjs [config.json] [captures-dir] [output-dir] [devices]
// Defaults render every device in the config, Paeonia from ios/ASConnectScreenshots/trial-1/raw into
// ios/ASConnectScreenshots/trial-1/3d. devices is a comma-separated list such as iPad.
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { launch, MODELS, openPage, renderDevices, threeImports } from './lib/device3d.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const configPath = path.resolve(process.argv[2] ?? path.join(root, 'scripts/assets/app-store/paeonia-3d.json'));
const captures = path.resolve(process.argv[3] ?? path.join(root, 'ios/ASConnectScreenshots/trial-1/raw'));
const output = path.resolve(process.argv[4] ?? path.join(root, 'ios/ASConnectScreenshots/trial-1/3d'));
const config = JSON.parse(await readFile(configPath, 'utf8'));
const devices = process.argv[5]?.split(',') ?? Object.keys(config.devices);
for (const name of devices) {
  if (!config.devices[name] || !MODELS[name]) throw new Error(`No device ${name} in the config and lib/device3d.mjs`);
}

// A soft light behind every device, at the centre renderDevices placed it.
const glows = (layout, H, centres) => layout.map((p, i) => `radial-gradient(${p.height * H * 0.55}px ${p.height * H * 0.45}px `
  + `at ${centres[i].x}px ${centres[i].y}px, ${config.glow}, transparent)`);

// caption scales the iPhone caption's size, width and margin, so a headline wraps the same way.
const page = (locale, W, H, caption) => {
  const count = config.panels[locale].length;
  return `<!doctype html><html lang="${locale}"><meta charset="utf-8">${threeImports}
    <style>
      * { box-sizing: border-box; margin: 0; }
      @font-face { font-family: Display; font-weight: 600; src: url(/font${path.extname(config.font)}); }
      html, body { width: ${W * count}px; height: ${H}px; overflow: hidden; }
      body { position: relative; background: ${config.background}; color: ${config.text}; }
      section { position: absolute; top: ${H * 0.052}px; width: ${1100 * caption}px; font: 600 ${104 * caption}px Display, serif; }
      h1 { font-size: 1em; line-height: 1.08; letter-spacing: -0.015em; text-wrap: balance; }
      h1 em { font-style: normal; color: ${config.accent}; }
      p { margin-top: 0.38em; font-size: 0.48em; line-height: 1.32; opacity: 0.72; text-wrap: balance; }
      img { position: absolute; filter: drop-shadow(0 60px 80px ${config.shadow}); }
    </style>
    ${config.panels[locale].map(([headline, body], i) =>
      `<section data-slot="${i}" style="left: ${i * W + 110 * caption}px"><h1>${headline}</h1><p>${body}</p></section>`)
      .join('')}`;
};

for (const name of devices) {
  const model = MODELS[name], { caption, layout } = config.devices[name];
  const [W, H] = model.capture;
  for (const locale of Object.keys(config.panels)) {
    // A fresh browser per strip: SwiftShader runs out of memory on the second wide strip otherwise.
    const browser = await launch(chromium);
    try {
      const count = config.panels[locale].length;
      const files = {}, spotlights = {};
      for (const { screen, spotlight } of layout) {
        files[screen] = config.capture.replaceAll('{locale}', locale).replaceAll('{device}', name)
          .replaceAll('{screen}', screen);
        const bytes = await readFile(path.join(captures, files[screen]));
        if (bytes.readUInt32BE(16) !== W || bytes.readUInt32BE(20) !== H) throw new Error(`Wrong capture size: ${files[screen]}`);
        // The capture script saves the spotlit element's frame next to the capture.
        if (spotlight) {
          const frame = path.join(captures, files[screen].replace(/\.png$/, '.spotlight.json'));
          spotlights[screen] = JSON.parse(await readFile(frame, 'utf8'));
        }
      }
      const tab = await openPage(browser, {
        width: W * count, height: H, html: page(locale, W, H, caption), captures,
        font: path.resolve(path.dirname(configPath), config.font),
      });
      const centres = await tab.evaluate(renderDevices, { model, layout, finish: config.finish, captures: files, spotlights });
      await tab.evaluate(background => { document.body.style.background = background; },
        [...glows(layout, H, centres), config.background].join(', '));

      const folder = path.join(output, locale);
      await mkdir(folder, { recursive: true });
      const shots = [];
      for (let i = 0; i < count; i++) {
        const file = `${name}-${String(i + 1).padStart(2, '0')}.png`;
        shots.push(await tab.screenshot({ path: path.join(folder, file), clip: { x: i * W, y: 0, width: W, height: H } }));
      }
      await tab.close();

      const preview = await browser.newPage({ viewport: { width: 24 + count * 344, height: 48 + Math.ceil(320 * H / W) } });
      await preview.setContent(`<style>body{margin:0;padding:24px;display:flex;gap:24px;background:white}
        img{width:320px;border-radius:30px}</style>`
        + shots.map(png => `<img src="data:image/png;base64,${png.toString('base64')}">`).join(''));
      await preview.evaluate(() => Promise.all([...document.images].map(image => image.decode())));
      await preview.screenshot({ path: path.join(output, `${locale}-${name}-preview.png`) });
      await preview.close();
      console.log(`Rendered ${count} ${locale} ${name} 3D screenshots into ${folder}`);
    } finally {
      await browser.close();
    }
  }
}
