// Capture harness for Dungeon Karl.
// Serves the repo statically, loads the game in auto-demo mode, waits for readiness,
// then grabs timed stills during combat and (optionally) records a motion clip.
// Usage: node tools/capture.mjs --out captures/wave1/piece --shots 5 --gap 1500 --video --w 1600 --h 1000
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const FFMPEG = ['/opt/pw-browsers/ffmpeg-1011/ffmpeg-linux','ffmpeg'].find(p=>{ try{ return p==='ffmpeg'||fs.existsSync(p); }catch{ return false; } }) || 'ffmpeg';

const ROOT = path.resolve(fileURLToPath(import.meta.url), '../..');
const args = Object.fromEntries(process.argv.slice(2).reduce((a,v,i,arr)=>{
  if(v.startsWith('--')){ const k=v.slice(2); const nx=arr[i+1]; a.push([k, (!nx||nx.startsWith('--'))?true:nx]); } return a; },[]));
const OUT = path.resolve(ROOT, args.out || 'captures/latest');
const SHOTS = +(args.shots||5), GAP = +(args.gap||1500), W=+(args.w||1600), H=+(args.h||1000);
const VIDEO = !!args.video, CLIPSECS = +(args.clipsecs||6);
const STRIP = +(args.strip||0), STRIPGAP = +(args.stripgap||160);
const URLPATH = args.path || '/index.html';
fs.mkdirSync(OUT, { recursive:true });

const MIME={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.jpg':'image/jpeg','.webm':'video/webm','.svg':'image/svg+xml'};
const server = http.createServer((req,res)=>{
  let p = decodeURIComponent(req.url.split('?')[0]); if(p==='/')p='/index.html';
  const fp = path.join(ROOT, p);
  if(!fp.startsWith(ROOT) || !fs.existsSync(fp)){ res.writeHead(404); return res.end('404'); }
  res.writeHead(200,{'content-type':MIME[path.extname(fp)]||'application/octet-stream'});
  fs.createReadStream(fp).pipe(res);
});
await new Promise(r=>server.listen(0,r));
const port = server.address().port;
const url = `http://127.0.0.1:${port}${URLPATH}?auto=1`;

const browser = await chromium.launch({ args:['--use-gl=angle','--use-angle=swiftshader','--enable-webgl','--ignore-gpu-blocklist'] });
const ctx = await browser.newContext({ viewport:{width:W,height:H}, deviceScaleFactor:1,
  recordVideo: VIDEO ? { dir: OUT, size:{width:W,height:H} } : undefined });
const page = await ctx.newPage();
const errors=[];
page.on('console', m=>{ if(m.type()==='error') errors.push(m.text()); });
page.on('pageerror', e=>errors.push('PAGEERROR: '+e.message));

await page.goto(url, { waitUntil:'load', timeout:30000 });
try { await page.waitForFunction('window.__READY===true', { timeout:15000 }); }
catch { console.error('WARN: __READY never set'); }
await page.waitForTimeout(1500); // let scene settle + combat begin
if(args.key){ for(const k of String(args.key).split(',')) await page.keyboard.press(k); await page.waitForTimeout(600); }

const shots=[];
for(let i=0;i<SHOTS;i++){
  const f=path.join(OUT, `shot_${String(i).padStart(2,'0')}.png`);
  await page.screenshot({ path:f });
  shots.push(f);
  if(i<SHOTS-1) await page.waitForTimeout(GAP);
}
let state={};
try { state = await page.evaluate(()=>window.__gameState||{}); } catch {}

// Motion filmstrip: rapid frames for in-page flipbook + critic motion review.
// (The bundled Playwright ffmpeg only has the image2 muxer, so we avoid gif/mp4
// conversion entirely and capture frames straight to disk as compact JPEGs.)
const strip=[];
for(let i=0;i<STRIP;i++){
  const f=path.join(OUT, `strip_${String(i).padStart(2,'0')}.jpg`);
  await page.screenshot({ path:f, type:'jpeg', quality:60 });
  strip.push(f);
  await page.waitForTimeout(STRIPGAP);
}

if(VIDEO) await page.waitForTimeout(CLIPSECS*1000);
await ctx.close(); // finalizes any recorded webm
await browser.close();
server.close();

let clip=null;
if(VIDEO){ const webm=fs.readdirSync(OUT).find(f=>f.endsWith('.webm')); if(webm) clip={ webm:path.join(OUT,webm) }; }

const report={ url, when:new Date().toISOString(), viewport:{W,H}, shots, strip, state, errors, clip };
fs.writeFileSync(path.join(OUT,'capture.json'), JSON.stringify(report,null,2));
console.log(JSON.stringify({ ok:errors.length===0, out:OUT, shots:shots.length, strip:strip.length, state, errors:errors.slice(0,5), clip }, null, 2));
