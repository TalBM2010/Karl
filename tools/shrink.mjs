// Downscale/convert images to JPEG so the progress page stays phone-friendly.
// The container's bundled ffmpeg is a stripped build (image2 muxer only, no PNG decoder) and
// there's no PIL/ImageMagick — so we use the one image pipeline we do have: Chromium's canvas.
// Usage: node tools/shrink.mjs <width> <out-dir> <file...>
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const [, , widthArg, outDir, ...files] = process.argv;
const W = +(widthArg || 1000);
fs.mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage();
for (const f of files) {
  if (!fs.existsSync(f)) { console.error('missing', f); continue; }
  const b64 = fs.readFileSync(f).toString('base64');
  const ext = path.extname(f).slice(1).toLowerCase();
  const mime = ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' : 'image/png';
  const out = await page.evaluate(async ({ b64, mime, W }) => {
    const img = new Image();
    img.src = `data:${mime};base64,${b64}`;
    await img.decode();
    const scale = Math.min(1, W / img.width);
    const c = document.createElement('canvas');
    c.width = Math.round(img.width * scale);
    c.height = Math.round(img.height * scale);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    return c.toDataURL('image/jpeg', 0.72);
  }, { b64, mime, W });
  const dest = path.join(outDir, path.basename(f).replace(/\.(png|jpe?g)$/i, '.jpg'));
  fs.writeFileSync(dest, Buffer.from(out.split(',')[1], 'base64'));
  console.log(`${dest}  ${(fs.statSync(dest).size / 1024).toFixed(0)}KB`);
}
await browser.close();
