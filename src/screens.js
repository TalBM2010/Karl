// screens — INVENTORY + CHARACTER SHEET overlays for Dungeon Karl.
// Plug-in module, auto-loaded by main.js via init(api). Owns ONLY this file.
// Builds DOM overlays + injects a <style>. Toggled by keyboard: c / i / Escape.
// Reuses the broadcast HUD's :root custom props (--cyan,--gold,--panel,--panel-line,
// --phys,--aether,--crit) so it reads as a Diablo-IV panel wearing the GOP skin.

export function init(api){
  api = api || window.__KARL || {};

  // ---------------------------------------------------------------- styles
  const css = `
  #ks-root{position:fixed;inset:0;z-index:60;display:none;font-family:var(--font);
    color:#cfe3ee;font-feature-settings:"tnum";-webkit-font-smoothing:antialiased}
  #ks-root.open{display:block}
  #ks-back{position:absolute;inset:0;background:rgba(2,7,12,.62);backdrop-filter:blur(5px);
    animation:ks-fade .18s ease both}
  @keyframes ks-fade{from{opacity:0}to{opacity:1}}
  @keyframes ks-pop{from{opacity:0;transform:translate(-50%,-50%) scale(.985)}to{opacity:1;transform:translate(-50%,-50%) scale(1)}}
  .ks-panel{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);
    width:min(1500px,95vw);height:min(940px,94vh);display:none;flex-direction:column;
    background:linear-gradient(160deg,rgba(9,19,28,.94),rgba(5,11,17,.96));
    border:1px solid var(--panel-line);border-radius:12px;padding:22px 26px 20px;
    box-shadow:0 0 0 1px rgba(0,0,0,.6),0 30px 90px rgba(0,0,0,.7),
      inset 0 0 90px rgba(57,215,255,.045),inset 0 1px 0 rgba(120,220,255,.10);
    animation:ks-pop .2s cubic-bezier(.2,.7,.3,1) both}
  .ks-panel.show{display:flex}
  /* corner bevels */
  .ks-panel::before,.ks-panel::after{content:"";position:absolute;width:26px;height:26px;
    border-color:var(--cyan);opacity:.55;pointer-events:none}
  .ks-panel::before{left:9px;top:9px;border-left:2px solid;border-top:2px solid;border-top-left-radius:8px}
  .ks-panel::after{right:9px;bottom:9px;border-right:2px solid;border-bottom:2px solid;border-bottom-right-radius:8px}

  .ks-close{position:absolute;top:12px;right:14px;width:34px;height:34px;border-radius:8px;
    border:1px solid var(--panel-line);background:rgba(8,18,26,.8);color:#a9d6e6;
    font-size:19px;line-height:1;cursor:pointer;display:flex;align-items:center;justify-content:center;
    transition:.15s;z-index:5}
  .ks-close:hover{color:#fff;border-color:var(--cyan);box-shadow:0 0 14px rgba(57,215,255,.4);background:rgba(20,40,52,.9)}

  .ks-eyebrow{font-size:10px;letter-spacing:.42em;color:#5f93a8;text-transform:uppercase}
  .ks-lab{font-size:9.5px;letter-spacing:.2em;color:#7bb0c6;text-transform:uppercase;font-weight:600}
  .ks-hdrline{height:1px;background:linear-gradient(90deg,transparent,var(--panel-line),transparent);margin:8px 0}

  /* section card */
  .ks-card{background:linear-gradient(180deg,rgba(10,22,31,.72),rgba(6,13,19,.72));
    border:1px solid var(--panel-line);border-radius:9px;padding:12px 14px;
    box-shadow:inset 0 0 40px rgba(57,215,255,.035),inset 0 1px 0 rgba(120,220,255,.06)}
  .ks-card-t{display:flex;align-items:center;gap:8px;margin-bottom:9px}
  .ks-card-t .tt{font-size:10.5px;letter-spacing:.26em;font-weight:700;text-transform:uppercase}
  .ks-card-t .rule{flex:1;height:1px;background:linear-gradient(90deg,var(--panel-line),transparent)}

  .ks-stat{display:flex;align-items:baseline;justify-content:space-between;gap:10px;
    padding:5px 2px;border-bottom:1px solid rgba(57,215,255,.07)}
  .ks-stat:last-child{border-bottom:0}
  .ks-stat .n{font-size:11px;letter-spacing:.05em;color:#9fbccb;text-transform:uppercase}
  .ks-stat .v{font-size:13px;font-weight:700;color:#eaf6fd;font-variant-numeric:tabular-nums;
    text-shadow:0 0 10px rgba(57,215,255,.18)}
  .ks-stat .v.hl{color:var(--cyan)}
  .ks-stat .v.gold{color:var(--gold)}

  /* rarity palette */
  .rar-common{--rc:#9aa6ad}.rar-magic{--rc:#4aa0ff}.rar-rare{--rc:#ffcf6a}
  .rar-legendary{--rc:#ff8a3c}.rar-mythic{--rc:#ff4b4b}

  /* ---------- CHARACTER SHEET ---------- */
  #ks-char .ch-top{display:flex;align-items:flex-start;gap:20px}
  #ks-char .ch-name{font-size:40px;font-weight:800;letter-spacing:.14em;line-height:1;
    color:#f3efe4;text-shadow:0 0 26px rgba(255,207,106,.28),0 2px 6px #000}
  #ks-char .ch-sub{font-size:12px;letter-spacing:.34em;color:var(--gold);margin-top:8px;font-weight:600}
  #ks-char .ch-paragon{font-size:11px;letter-spacing:.28em;color:var(--cyan);margin-top:4px;font-weight:600}
  .ch-xpwrap{flex:1;max-width:560px;margin-top:6px}
  .ch-xprow{display:flex;justify-content:space-between;font-size:10px;letter-spacing:.16em;color:#7ba7bb;margin-bottom:5px}
  .ch-xprow b{color:#dbeaf2;font-weight:700}
  .ch-xpbar{height:12px;border-radius:6px;background:#0a1a23;border:1px solid rgba(57,215,255,.22);
    overflow:hidden;position:relative;box-shadow:inset 0 2px 6px rgba(0,0,0,.6)}
  .ch-xpbar>i{display:block;height:100%;width:81.1%;border-radius:6px;position:relative;
    background:linear-gradient(90deg,#2f7fb0,var(--cyan));box-shadow:0 0 14px rgba(57,215,255,.6)}
  .ch-xpbar>i::after{content:"";position:absolute;inset:0;
    background:linear-gradient(90deg,transparent,rgba(255,255,255,.35),transparent);
    background-size:200% 100%;animation:ks-shine 2.6s linear infinite}
  @keyframes ks-shine{from{background-position:120% 0}to{background-position:-120% 0}}

  .ch-core{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:14px 0 4px}
  .ch-attr{text-align:center;padding:11px 6px 10px;border-radius:8px;position:relative;
    background:linear-gradient(180deg,rgba(12,26,36,.85),rgba(6,14,20,.85));
    border:1px solid var(--panel-line);box-shadow:inset 0 0 26px rgba(57,215,255,.05)}
  .ch-attr .a-v{font-size:26px;font-weight:800;color:#eaf6fd;font-variant-numeric:tabular-nums;
    text-shadow:0 0 16px rgba(57,215,255,.3)}
  .ch-attr .a-n{font-size:9.5px;letter-spacing:.24em;color:#8fb4c6;margin-top:3px;text-transform:uppercase}
  .ch-attr .a-bar{height:3px;border-radius:2px;margin-top:8px;background:#0b1922;overflow:hidden}
  .ch-attr .a-bar>i{display:block;height:100%;background:linear-gradient(90deg,var(--cyan-dim),var(--cyan))}

  .ch-main{flex:1;display:grid;grid-template-columns:1fr 1.05fr 1fr;gap:16px;min-height:0;margin-top:12px}
  .ch-col{display:flex;flex-direction:column;gap:12px;min-height:0}
  .ch-col .ks-card{flex:1;overflow:auto}
  .ch-center{display:flex;flex-direction:column;gap:12px;min-height:0}

  .ch-pedestal{flex:1;border-radius:10px;position:relative;overflow:hidden;min-height:240px;
    border:1px solid var(--panel-line);
    background:radial-gradient(120% 90% at 50% 8%,rgba(57,215,255,.14),transparent 55%),
      radial-gradient(80% 60% at 50% 100%,rgba(57,215,255,.16),transparent 60%),
      linear-gradient(180deg,#081521,#04090e)}
  .ch-pedestal svg{position:absolute;inset:0;width:100%;height:100%}
  .ch-pedestal .glow{position:absolute;left:50%;bottom:8%;width:60%;height:26%;transform:translateX(-50%);
    background:radial-gradient(ellipse at center,rgba(57,215,255,.5),transparent 70%);filter:blur(6px)}
  .ch-pedestal .cls{position:absolute;left:0;right:0;bottom:10px;text-align:center;
    font-size:10px;letter-spacing:.34em;color:#8fc7dd;text-transform:uppercase}

  .ch-equip{display:flex;gap:8px;justify-content:space-between}
  .ch-eslot{flex:1;aspect-ratio:1;border-radius:7px;position:relative;border:1.5px solid var(--rc,#9aa6ad);
    background:linear-gradient(180deg,rgba(14,28,38,.9),rgba(6,13,19,.9));
    box-shadow:0 0 12px -3px var(--rc,#9aa6ad),inset 0 0 18px rgba(0,0,0,.5)}
  .ch-eslot .ic{position:absolute;inset:5px;border-radius:4px;display:flex;align-items:center;
    justify-content:center;font-size:17px;background:radial-gradient(circle at 40% 30%,rgba(255,255,255,.1),transparent);
    filter:drop-shadow(0 0 6px var(--rc))}
  .ch-eslot .sl{position:absolute;top:2px;left:4px;font-size:7.5px;letter-spacing:.12em;color:#87a6b5;text-transform:uppercase}

  .ch-metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
  .ch-metric{padding:10px 12px;border-radius:8px;background:linear-gradient(180deg,rgba(10,22,31,.7),rgba(6,13,19,.7));
    border:1px solid var(--panel-line)}
  .ch-metric .m-v{font-size:19px;font-weight:800;color:#eaf6fd;font-variant-numeric:tabular-nums}
  .ch-metric .m-n{font-size:9px;letter-spacing:.2em;color:#7fa8ba;margin-top:2px;text-transform:uppercase}

  /* ---------- INVENTORY ---------- */
  #ks-inv .iv-head{display:flex;align-items:flex-end;justify-content:space-between;gap:16px}
  #ks-inv .iv-title{font-size:22px;font-weight:800;letter-spacing:.2em;color:#eaf3f8}
  .iv-tabs{display:flex;gap:6px}
  .iv-tab{padding:8px 18px;border-radius:8px 8px 0 0;font-size:10.5px;letter-spacing:.22em;font-weight:700;
    text-transform:uppercase;color:#7ea6b8;cursor:pointer;border:1px solid var(--panel-line);border-bottom:0;
    background:linear-gradient(180deg,rgba(9,19,28,.6),rgba(6,13,19,.2));transition:.15s}
  .iv-tab:hover{color:#cfe9f4}
  .iv-tab.active{color:#04121a;background:linear-gradient(180deg,var(--cyan),#2f9fc9);
    box-shadow:0 0 16px rgba(57,215,255,.5)}

  .iv-body{flex:1;display:grid;grid-template-columns:120px 1fr 120px;gap:18px;min-height:0;margin-top:14px}
  .iv-side{display:flex;flex-direction:column;gap:9px}
  .iv-side .sh{font-size:9px;letter-spacing:.24em;color:#6f9bad;text-align:center;text-transform:uppercase}
  .iv-eslot{aspect-ratio:1;border-radius:8px;position:relative;border:1.5px solid var(--rc,#9aa6ad);
    background:linear-gradient(180deg,rgba(14,28,38,.9),rgba(6,13,19,.9));
    box-shadow:0 0 14px -4px var(--rc,#9aa6ad),inset 0 0 18px rgba(0,0,0,.55)}
  .iv-eslot .ic{position:absolute;inset:6px;border-radius:5px;display:flex;align-items:center;justify-content:center;
    font-size:22px;filter:drop-shadow(0 0 7px var(--rc))}
  .iv-eslot .sl{position:absolute;bottom:3px;left:0;right:0;text-align:center;font-size:7px;letter-spacing:.1em;
    color:#8aa9b8;text-transform:uppercase}

  .iv-gridwrap{display:flex;flex-direction:column;min-height:0}
  .iv-grid{flex:1;display:grid;grid-template-columns:repeat(6,1fr);grid-template-rows:repeat(4,1fr);
    gap:12px;min-height:0}
  .iv-slot{border-radius:9px;position:relative;border:1.5px solid var(--rc,#3a4a52);
    background:linear-gradient(180deg,rgba(14,28,38,.86),rgba(6,13,19,.9));
    box-shadow:0 0 16px -5px var(--rc,transparent),inset 0 0 20px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.04);
    display:flex;align-items:center;justify-content:center;overflow:hidden;transition:.12s;cursor:pointer}
  .iv-slot.empty{border-color:rgba(57,215,255,.14);box-shadow:inset 0 0 18px rgba(0,0,0,.5)}
  .iv-slot:not(.empty):hover{transform:translateY(-2px);box-shadow:0 6px 22px -4px var(--rc),inset 0 0 20px rgba(0,0,0,.4)}
  .iv-slot .ic{font-size:30px;filter:drop-shadow(0 0 9px var(--rc))}
  .iv-slot .rr{position:absolute;top:0;left:0;right:0;height:3px;background:var(--rc);opacity:.9}
  .iv-slot .pips{position:absolute;bottom:4px;left:0;right:0;display:flex;gap:2px;justify-content:center}
  .iv-slot .pips i{width:5px;height:5px;transform:rotate(45deg);background:var(--rc);
    box-shadow:0 0 5px var(--rc)}
  .iv-slot .ql{position:absolute;top:3px;right:5px;font-size:8px;font-weight:700;color:var(--rc);letter-spacing:.05em}

  .iv-cur{display:flex;gap:26px;justify-content:center;margin-top:16px;padding-top:14px;
    border-top:1px solid var(--panel-line)}
  .iv-coin{display:flex;align-items:center;gap:9px}
  .iv-coin .dot{width:20px;height:20px;border-radius:50%;box-shadow:0 0 12px currentColor}
  .iv-coin .lb{font-size:9px;letter-spacing:.2em;color:#7fa8ba;text-transform:uppercase}
  .iv-coin .vv{font-size:17px;font-weight:800;color:#eaf6fd;font-variant-numeric:tabular-nums;line-height:1}

  .ks-hint{position:absolute;bottom:12px;left:26px;font-size:9.5px;letter-spacing:.2em;color:#557485;text-transform:uppercase}
  `;
  const style=document.createElement('style'); style.textContent=css; document.head.appendChild(style);

  // ---------------------------------------------------------------- helpers
  const el=(t,c,h)=>{const e=document.createElement(t); if(c)e.className=c; if(h!=null)e.innerHTML=h; return e;};
  const RAR=['rar-common','rar-magic','rar-rare','rar-legendary','rar-mythic'];
  const RTAG=['C','M','R','L','MY'];
  const pips=(n)=>{let s=''; for(let i=0;i<n;i++) s+='<i></i>'; return s;};

  // ---------------------------------------------------------------- ROOT + backdrop
  const root=el('div'); root.id='ks-root';
  const back=el('div'); back.id='ks-back';
  back.addEventListener('pointerdown',close);
  root.appendChild(back);

  // ================================================= CHARACTER SHEET
  const char=el('div','ks-panel'); char.id='ks-char';
  char.appendChild(closeBtn());
  char.innerHTML+=`
    <div class="ks-eyebrow">Galactic Observation Protocol · Specimen Dossier</div>
    <div class="ch-top" style="margin-top:8px">
      <div>
        <div class="ch-name">CARL</div>
        <div class="ch-sub">LEVEL 78 · PRIMAL WARRIOR</div>
        <div class="ch-paragon">◆ PARAGON TIER 4</div>
      </div>
      <div class="ch-xpwrap">
        <div class="ch-xprow"><span>EXPERIENCE</span><span><b>23,314,112</b> / 28,750,000 XP</span></div>
        <div class="ch-xpbar"><i></i></div>
        <div class="ch-xprow" style="margin-top:6px;color:#5f93a8"><span>NEXT LEVEL</span><span>5,435,888 TO GO</span></div>
      </div>
    </div>
    <div class="ch-core" id="ch-core"></div>
    <div class="ch-main">
      <div class="ch-col" id="ch-off"></div>
      <div class="ch-center">
        <div class="ch-pedestal">
          ${heroSVG()}
          <div class="glow"></div>
          <div class="cls">◈ PRIMAL WARRIOR · ASCENDED ◈</div>
        </div>
        <div class="ch-equip" id="ch-equip"></div>
      </div>
      <div class="ch-col" id="ch-def-util"></div>
    </div>
    <div class="ch-metrics" id="ch-metrics" style="margin-top:12px"></div>
    <div class="ks-hint">C · CHARACTER   I · INVENTORY   ESC · CLOSE</div>`;

  // core attributes
  const core=[['STRENGTH','1,482',.86],['DEXTERITY','487',.44],['INTELLIGENCE','392',.4],
    ['WILLPOWER','612',.55],['VITALITY','1,118',.74]];
  const coreWrap=char.querySelector('#ch-core');
  core.forEach(([n,v,p])=>coreWrap.appendChild(el('div','ch-attr',
    `<div class="a-v">${v}</div><div class="a-n">${n}</div><div class="a-bar"><i style="width:${p*100}%"></i></div>`)));

  // stat columns
  const OFFENSE=[['Physical Damage','4,892'],['Aether Damage','3,112','aether'],['Critical Strike Chance','38.7%','hl'],
    ['Critical Damage','217.4%'],['Vulnerable Damage','46.2%'],['All Damage','32.6%'],
    ['Attack Speed','1.18'],['Overpower Damage','72.1%']];
  const DEFENSE=[['Max Health','16,800','gold'],['Armor','11,732'],['Damage Reduction','63.2%','hl'],
    ['Resist All','58.4%'],['Physical Resist','56.1%'],['Aether Resist','59.7%'],
    ['Dodge','12.3%'],['Barrier Gen','18.6%']];
  const UTILITY=[['Max Energy','1,600'],['Energy Regen','24.5/s'],['Cooldown Reduction','24.6%','hl'],
    ['Experience Bonus','25.0%','gold'],['Gold Find','48.7%','gold'],['Magic Find','62.3%','gold'],
    ['Movement Speed','115.0%'],['Mount Speed','120.0%']];

  char.querySelector('#ch-off').appendChild(statCard('Offense','⚔',OFFENSE,'var(--gold)'));
  const rightCol=char.querySelector('#ch-def-util');
  rightCol.appendChild(statCard('Defense','🛡',DEFENSE,'var(--cyan)'));
  rightCol.appendChild(statCard('Utility','✦',UTILITY,'#8fd0ff'));

  // equipment row (7 rarity slots)
  const eq=[['HEAD',3,'⛑'],['CHEST',4,'🛡'],['GLOVES',2,'🧤'],['WEAPON',4,'⚔'],
    ['LEGS',3,'👖'],['BOOTS',2,'🥾'],['AMULET',4,'📿']];
  const eqWrap=char.querySelector('#ch-equip');
  eq.forEach(([sl,r,ic])=>{const s=el('div','ch-eslot '+RAR[r]);
    s.innerHTML=`<div class="sl">${sl}</div><div class="ic">${ic}</div>`; eqWrap.appendChild(s);});

  // bottom metrics
  const metrics=[['124h 37m','Time Played'],['68,742','Monsters Killed'],
    ['247','Bosses Defeated'],['89 / 128','Areas Discovered']];
  const mWrap=char.querySelector('#ch-metrics');
  metrics.forEach(([v,n])=>mWrap.appendChild(el('div','ch-metric',
    `<div class="m-v">${v}</div><div class="m-n">${n}</div>`)));

  root.appendChild(char);

  // ================================================= INVENTORY
  const inv=el('div','ks-panel'); inv.id='ks-inv';
  inv.appendChild(closeBtn());
  inv.innerHTML+=`
    <div class="ks-eyebrow">Galactic Observation Protocol · Specimen Loadout</div>
    <div class="iv-head" style="margin-top:8px">
      <div class="iv-title">INVENTORY</div>
      <div class="iv-tabs" id="iv-tabs"></div>
    </div>
    <div class="ks-hdrline"></div>
    <div class="iv-body">
      <div class="iv-side" id="iv-left"></div>
      <div class="iv-gridwrap">
        <div class="iv-grid" id="iv-grid"></div>
      </div>
      <div class="iv-side" id="iv-right"></div>
    </div>
    <div class="iv-cur" id="iv-cur"></div>
    <div class="ks-hint">C · CHARACTER   I · INVENTORY   ESC · CLOSE</div>`;

  // equipment paperdoll sides
  const leftSlots=[['HEAD',3,'⛑'],['CHEST',4,'🛡'],['GLOVES',2,'🧤'],['LEGS',3,'👖'],['BOOTS',2,'🥾']];
  const rightSlots=[['WEAPON',4,'⚔'],['OFFHAND',3,'🗡'],['AMULET',4,'📿'],['RING I',2,'💍'],['RING II',3,'💍']];
  const L=inv.querySelector('#iv-left'), R=inv.querySelector('#iv-right');
  L.appendChild(el('div','sh','ARMOR')); leftSlots.forEach(s=>L.appendChild(eslot(s)));
  R.appendChild(el('div','sh','WEAPONS')); rightSlots.forEach(s=>R.appendChild(eslot(s)));

  // tabs + item sets (r=rarity idx 0-4, star=pips, ic=glyph)
  const ICON={w:['⚔','🗡','🏹','🔨','🪓','🔱'],a:['🛡','⛑','🧤','👖','🥾','🎽'],
    j:['📿','💍','🔮','💎','🧿','⭕'],c:['🧪','⚗','🍖','📜','🔥','❄']};
  const TABS=[['WEAPONS','w'],['ARMOR','a'],['JEWELRY','j'],['CONSUMABLES','c']];
  // deterministic pseudo-fill per tab (24 cells, a few empty)
  function itemsFor(key){
    const icons=ICON[key]; const out=[];
    for(let i=0;i<24;i++){
      const seed=(i*7+key.charCodeAt(0))%17;
      if(seed>13){ out.push(null); continue; }
      const r=[0,0,1,1,1,2,2,3,3,4][(i*3+seed)%10];
      const star=1+((i+seed)%5);
      out.push({r,star,ic:icons[(i+seed)%icons.length]});
    }
    return out;
  }
  const tabsWrap=inv.querySelector('#iv-tabs'), grid=inv.querySelector('#iv-grid');
  let activeTab='w';
  function renderGrid(){
    grid.innerHTML='';
    itemsFor(activeTab).forEach(it=>{
      if(!it){ grid.appendChild(el('div','iv-slot empty')); return; }
      const s=el('div','iv-slot '+RAR[it.r]);
      s.innerHTML=`<div class="rr"></div><div class="ql">${RTAG[it.r]}</div>`+
        `<div class="ic">${it.ic}</div><div class="pips">${pips(it.star)}</div>`;
      grid.appendChild(s);
    });
  }
  TABS.forEach(([label,key])=>{
    const t=el('div','iv-tab'+(key===activeTab?' active':''),label); t.dataset.k=key;
    t.addEventListener('click',()=>{activeTab=key;
      tabsWrap.querySelectorAll('.iv-tab').forEach(x=>x.classList.toggle('active',x.dataset.k===key));
      renderGrid();});
    tabsWrap.appendChild(t);
  });
  renderGrid();

  // currency row
  const cur=[['#ffcf6a','Gold','52,348,772'],['#cfe3ee','Platinum','8,722'],['#7bd6ff','Crystals','123']];
  const curWrap=inv.querySelector('#iv-cur');
  cur.forEach(([col,lb,vv])=>{const c=el('div','iv-coin');
    c.innerHTML=`<span class="dot" style="background:${col};color:${col}"></span>`+
      `<span><span class="lb">${lb}</span><br><span class="vv">${vv}</span></span>`;
    curWrap.appendChild(c);});

  root.appendChild(inv);
  document.body.appendChild(root);

  // ---------------------------------------------------------------- builders
  function closeBtn(){const b=el('button','ks-close','×'); b.setAttribute('aria-label','Close');
    b.addEventListener('click',close); return b;}
  function statCard(title,glyph,rows,accent){
    const c=el('div','ks-card');
    c.innerHTML=`<div class="ks-card-t"><span style="color:${accent}">${glyph}</span>`+
      `<span class="tt" style="color:${accent}">${title}</span><span class="rule"></span></div>`;
    rows.forEach(([n,v,cls])=>{
      const isAe = cls==='aether';
      const vc = isAe ? 'v' : ('v'+(cls?(' '+cls):''));
      const vstyle = isAe ? ' style="color:var(--aether)"' : '';
      c.appendChild(el('div','ks-stat',`<span class="n">${n}</span><span class="${vc}"${vstyle}>${v}</span>`));
    });
    return c;
  }
  function eslot([sl,r,ic]){const s=el('div','iv-eslot '+RAR[r]);
    s.innerHTML=`<div class="ic">${ic}</div><div class="sl">${sl}</div>`; return s;}
  function heroSVG(){
    return `<svg viewBox="0 0 200 260" preserveAspectRatio="xMidYMax meet">
      <defs>
        <radialGradient id="ksg" cx="50%" cy="30%" r="70%">
          <stop offset="0%" stop-color="#bfeaff" stop-opacity=".9"/>
          <stop offset="45%" stop-color="#4a8fb0" stop-opacity=".55"/>
          <stop offset="100%" stop-color="#0a1720" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="ksb" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#1a2b36"/><stop offset="100%" stop-color="#060d13"/>
        </linearGradient>
      </defs>
      <ellipse cx="100" cy="30" rx="70" ry="70" fill="url(#ksg)"/>
      <g fill="#0c1a24" stroke="#39d7ff" stroke-width="1.2" stroke-opacity=".55">
        <circle cx="100" cy="52" r="15"/>
        <path d="M78 70 q22 -10 44 0 l10 60 q-16 8 -32 8 t-32 -8 z"/>
        <path d="M78 74 l-20 34 8 8 20 -30z"/>
        <path d="M122 74 l20 34 -8 8 -20 -30z"/>
        <path d="M86 146 l-6 66 12 2 8 -60z"/>
        <path d="M114 146 l6 66 -12 2 -8 -60z"/>
        <path d="M142 40 l6 0 -3 96 -3 0z" fill="#22323c" stroke-opacity=".8"/>
        <path d="M136 132 l18 0 0 8 -18 0z" fill="#2a3a44"/>
      </g>
      <g>
        <ellipse cx="100" cy="236" rx="76" ry="16" fill="url(#ksb)" stroke="#39d7ff" stroke-opacity=".4"/>
        <ellipse cx="100" cy="228" rx="60" ry="12" fill="#0a1621" stroke="#39d7ff" stroke-opacity=".55"/>
        <ellipse cx="100" cy="224" rx="46" ry="9" fill="#0d1e2a" stroke="#5fd0f0" stroke-opacity=".7"/>
      </g>
    </svg>`;
  }

  // ---------------------------------------------------------------- open/close
  let curOpen=null; // 'char' | 'inv' | null
  function show(which){
    curOpen=which;
    char.classList.toggle('show',which==='char');
    inv.classList.toggle('show',which==='inv');
    root.classList.add('open');
    const p = which==='char'?char:inv;
    p.style.animation='none'; void p.offsetWidth; p.style.animation='';
  }
  function close(){curOpen=null; char.classList.remove('show'); inv.classList.remove('show');
    root.classList.remove('open');}
  function toggle(which){ if(curOpen===which) close(); else show(which); }

  window.addEventListener('keydown',(e)=>{
    const tag=(e.target&&e.target.tagName)||''; if(tag==='INPUT'||tag==='TEXTAREA') return;
    const k=e.key;
    if(k==='Escape'){ if(curOpen){ close(); e.preventDefault(); } return; }
    const low=k.toLowerCase();
    if(low==='c'){ toggle('char'); e.preventDefault(); }
    else if(low==='i'){ toggle('inv'); e.preventDefault(); }
  });

  // expose for the capture harness / debugging
  api.screens={open:show,close,toggle};
}
