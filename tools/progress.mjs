// Generates progress/index.html from progress/state.json, inlining the latest capture
// screenshots as data-URIs so the page is fully self-contained (publishable as an Artifact).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const ROOT=path.resolve(fileURLToPath(import.meta.url),'../..');
const state=JSON.parse(fs.readFileSync(path.join(ROOT,'progress/state.json'),'utf8'));
const dataURI=(p)=>{ try{ const abs=path.resolve(ROOT,p); const b=fs.readFileSync(abs); const ext=path.extname(abs).slice(1);
  return `data:image/${ext==='jpg'?'jpeg':ext};base64,${b.toString('base64')}`; }catch{ return null; } };

const pieceRow=(pc)=>{
  const bar=Math.round((pc.score||0)*10);
  const stat={winning:'#57e08a',building:'#ffcf6a',critic:'#6fd0ff',queued:'#6f8a99',blocked:'#ff6a6a'}[pc.status]||'#6f8a99';
  return `<div class="pc">
    <div class="pc-h"><span class="dot" style="background:${stat}"></span><b>${pc.name}</b><span class="sc">${(pc.score??0).toFixed(1)}/10</span></div>
    <div class="track"><i style="width:${bar}%;background:${stat}"></i></div>
    <div class="pc-s">${pc.status.toUpperCase()}${pc.note?` — ${pc.note}`:''}</div>
    ${pc.gap?`<div class="gap">▸ biggest gap: ${pc.gap}</div>`:''}
  </div>`;
};
const shot=(p,cap)=>{ const d=dataURI(p); return d?`<figure><img src="${d}"><figcaption>${cap||''}</figcaption></figure>`:''; };

const html=`<title>Dungeon Karl — Build Progress</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;font-family:'Rajdhani',system-ui,sans-serif;background:#05080c;color:#dbe7ee}
.wrap{max-width:900px;margin:0 auto;padding:16px}
h1{font-size:19px;letter-spacing:.16em;color:#39d7ff;text-align:center;text-shadow:0 0 14px rgba(57,215,255,.5);margin:6px 0 2px}
.sub{text-align:center;color:#7fa9bd;font-size:11px;letter-spacing:.14em;margin-bottom:14px}
.hero{background:#0a141c;border:1px solid rgba(57,215,255,.25);border-radius:10px;padding:12px;margin-bottom:14px}
.hero .row{display:flex;gap:14px;flex-wrap:wrap;justify-content:space-around;text-align:center}
.hero .k{font-size:26px;font-weight:700;color:#eaf7ff}
.hero .l{font-size:10px;color:#6f96a8;letter-spacing:.12em}
.card{background:#0a141c;border:1px solid rgba(57,215,255,.18);border-radius:10px;padding:14px;margin-bottom:14px}
.card h2{font-size:12px;letter-spacing:.18em;color:#79b6cc;margin:0 0 10px;text-transform:uppercase}
.pc{margin-bottom:12px}
.pc-h{display:flex;align-items:center;gap:8px;font-size:14px}
.pc-h .sc{margin-left:auto;color:#9fd4e6;font-variant-numeric:tabular-nums}
.dot{width:9px;height:9px;border-radius:50%;flex:0 0 9px;box-shadow:0 0 8px currentColor}
.track{height:6px;background:#12212b;border-radius:4px;margin:5px 0 3px;overflow:hidden}
.track i{display:block;height:100%;border-radius:4px;transition:width .6s}
.pc-s{font-size:11px;color:#8fb0be;letter-spacing:.06em}
.gap{font-size:11.5px;color:#ffb06a;margin-top:3px}
.shots{display:grid;grid-template-columns:1fr 1fr;gap:10px}
@media(max-width:560px){.shots{grid-template-columns:1fr}}
figure{margin:0}
figure img{width:100%;border-radius:8px;border:1px solid rgba(57,215,255,.2);display:block}
figcaption{font-size:10.5px;color:#7fa9bd;text-align:center;margin-top:4px;letter-spacing:.08em}
.log{font-size:12px;line-height:1.55}
.log .e{padding:5px 0;border-bottom:1px solid rgba(57,215,255,.08);display:flex;gap:8px}
.log .e time{color:#5f8698;flex:0 0 auto;font-variant-numeric:tabular-nums}
.badge{display:inline-block;padding:2px 8px;border-radius:20px;font-size:10px;letter-spacing:.1em}
.foot{text-align:center;color:#4f6b7a;font-size:10px;margin:18px 0 8px;letter-spacing:.12em}
</style>
<div class="wrap">
  <h1>DUNGEON KARL — BUILD PROGRESS</h1>
  <div class="sub">DIABLO IV BAR · GALACTIC OBSERVATION PROTOCOL · UPDATED ${state.updated}</div>

  <div class="hero"><div class="row">
    <div><div class="k">${state.wave}</div><div class="l">CURRENT WAVE</div></div>
    <div><div class="k">${state.pieces.filter(p=>p.status==='winning').length}/${state.pieces.length}</div><div class="l">PIECES WINNING</div></div>
    <div><div class="k">${state.overall.toFixed(1)}</div><div class="l">OVERALL / 10</div></div>
    <div><div class="k">${state.rounds}</div><div class="l">CRITIC ROUNDS</div></div>
  </div></div>

  ${state.latestShots?.length?`<div class="card"><h2>Latest build — captured live</h2><div class="shots">${state.latestShots.map(s=>shot(s.path,s.cap)).join('')}</div></div>`:''}

  <div class="card"><h2>Pieces (each judged independently vs the reference)</h2>${state.pieces.map(pieceRow).join('')}</div>

  <div class="card"><h2>Activity log</h2><div class="log">${state.log.map(e=>`<div class="e"><time>${e.t}</time><span><span class="badge" style="background:${e.c||'#12303f'};color:#cfe">${e.tag}</span> ${e.msg}</span></div>`).join('')}</div></div>

  <div class="foot">${state.note||''} · a fresh critic sees ours beside the reference as two unlabeled candidates and picks the better one · loop continues until ours wins</div>
</div>`;
fs.writeFileSync(path.join(ROOT,'progress/index.html'), html);
console.log('progress/index.html written ('+html.length+' bytes)');
