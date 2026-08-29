/* Renders the app icons. Four notes in the arrow colours on the dark ground —
   unmistakably this game, and still legible at 48px. */
import { chromium } from "playwright";
import fs from "fs";

const page = (size, pad) => `<!doctype html><meta charset="utf-8">
<style>
  html, body { margin: 0; width: ${size}px; height: ${size}px; }
  body { background: #14111F; display: grid; place-items: center; }
  .notes {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: ${size * 0.055}px;
    width: ${size * (1 - pad * 2)}px;
    height: ${size * (1 - pad * 2)}px;
  }
  .note { border-radius: ${size * 0.055}px; }
  .a { background: #C24B99; } .b { background: #00FFFF; }
  .c { background: #12FA05; } .d { background: #F9393F; }
</style>
<div class="notes">
  <div class="note a"></div><div class="note b"></div>
  <div class="note c"></div><div class="note d"></div>
</div>`;

const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });

for (const [file, size, pad] of [
  ["icon-192.png", 192, 0.17],
  ["icon-512.png", 512, 0.17],
  // A maskable icon gets cropped to whatever shape the phone likes, so its art
  // has to sit well inside the edges.
  ["icon-maskable-512.png", 512, 0.28]
]) {
  const tab = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
  await tab.setContent(page(size, pad));
  await tab.screenshot({ path: file, omitBackground: false });
  await tab.close();
  console.log(`  + ${file} (${fs.statSync(file).size} bytes)`);
}

await browser.close();
