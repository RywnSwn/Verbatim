// Makes Support/AppIcon.icns from Support/AppIcon.svg (the Ribbon icon Ryan
// picked, 2026-11-20). Runs without a Mac: Playwright's Chromium draws the SVG
// at every size, then this writes the .icns file by hand (it is a simple
// format: a header, then one PNG per size).
// Usage: node scripts/make-icon.js
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const root = path.join(__dirname, "..");
const svg = fs.readFileSync(path.join(root, "Support/AppIcon.svg"), "utf8");

// icns type code -> pixel size. The @2x codes (ic10 to ic14) are for Retina.
const entries = [
  ["icp4", 16], ["ic11", 32],
  ["icp5", 32], ["ic12", 64],
  ["ic07", 128], ["ic13", 256],
  ["ic08", 256], ["ic14", 512],
  ["ic09", 512], ["ic10", 1024],
];

(async () => {
  const browser = await chromium.launch();
  const pngs = {};
  for (const size of [...new Set(entries.map(e => e[1]))]) {
    const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
    await page.setContent(
      `<html><body style="margin:0;background:transparent">` +
      svg.replace(/width="1024" height="1024"/, `width="${size}" height="${size}"`) +
      `</body></html>`
    );
    pngs[size] = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
    await page.close();
  }
  await browser.close();

  const parts = entries.map(([type, size]) => {
    const head = Buffer.alloc(8);
    head.write(type, 0, "ascii");
    head.writeUInt32BE(8 + pngs[size].length, 4);
    return Buffer.concat([head, pngs[size]]);
  });
  const body = Buffer.concat(parts);
  const head = Buffer.alloc(8);
  head.write("icns", 0, "ascii");
  head.writeUInt32BE(8 + body.length, 4);
  fs.writeFileSync(path.join(root, "Support/AppIcon.icns"), Buffer.concat([head, body]));
  console.log("Wrote Support/AppIcon.icns");
})();
