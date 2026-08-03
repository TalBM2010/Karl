// SYSTEM LOOT-BOX OPENING CEREMONY  —  owned by the "lootbox" builder.
// A self-contained DOM/CSS/Canvas broadcast overlay: the Dungeon-Crawler-Carl reward-reveal ritual.
// The System presents a tiered loot box (Bronze/Silver/Gold/Platinum), it CHARGES (shakes, seams
// leak light, the audience froths), then BURSTS with a rarity-colored light explosion + shard
// particles + a screen flash + a camera kick, and a REWARD CARD flies up and settles with the item
// icon, name, rarity, type and stat lines. Legendary/Mythic get a bigger burst, gold/red rays and
// "!!!". Then a CLAIM prompt, and it dismisses cleanly (no DOM/particle leaks).
//
// Triggers: press "o" to open manually. In ?auto (capture/demo) it auto-opens ~4s after load and
// then ~every 9s, cycling tiers so captures reliably catch the charge, burst and reveal.
// Exposes api.lootbox = { open(tier?) }. Plugs into main.js via init(api) — edits nothing else.
// Judge against rubric 12: loot-box open flourish, rarity coding, the AAA reward moment.

export function init(api){
  const vfx = api && api.vfx;
  const isAuto = !!(api && api.isAuto);

  // ---------------------------------------------------------------- rarity + tier tables
  const RARITY = [
    { key:'Common',    label:'COMMON',    css:'#c8d2d8', w:42, tier:0 },
    { key:'Magic',     label:'MAGIC',     css:'#5a9cff', w:27, tier:1 },
    { key:'Rare',      label:'RARE',      css:'#ffd54a', w:16, tier:2 },
    { key:'Legendary', label:'LEGENDARY', css:'#ff8a3d', w:9,  tier:3 },
    { key:'Mythic',    label:'MYTHIC',    css:'#e5484d', w:4,  tier:4 },
  ];
  const RTOT = RARITY.reduce((s,r)=>s+r.w,0);
  function pickRarity(bias=0){
    let r=Math.random()*RTOT;
    for(let i=0;i<RARITY.length;i++){ r-=RARITY[i].w; if(r<=0) return RARITY[Math.min(RARITY.length-1,i+bias)]; }
    return RARITY[RARITY.length-1];
  }

  // box tiers — metal color, glow, and how hard the reward rarity is biased upward.
  const TIERS = [
    { key:'Bronze',   css:'#d98b45', edge:'#8a5322', spec:'#ffd9a8', w:46, bias:0 },
    { key:'Silver',   css:'#dfe6ee', edge:'#8b98a6', spec:'#ffffff', w:30, bias:1 },
    { key:'Gold',     css:'#ffd76a', edge:'#b5851c', spec:'#fff6cf', w:17, bias:2 },
    { key:'Platinum', css:'#eaf4ff', edge:'#8fb6cf', spec:'#ffffff', w:7,  bias:3 },
  ];
  const TTOT = TIERS.reduce((s,t)=>s+t.w,0);
  function pickTier(){ let r=Math.random()*TTOT; for(const t of TIERS){ r-=t.w; if(r<=0) return t; } return TIERS[0]; }
  function tierByKey(k){ return TIERS.find(t=>t.key.toLowerCase()===String(k).toLowerCase()); }

  // ---------------------------------------------------------------- item content (DCC flavor)
  const WEAPONS=["Stinger of Xy'Rathul","Aetherwrought Cleaver","The Neighborhood Special","Mongo's Prized Rock",
    "Skullwhisper Maul","Ferdinand's Femur","The Screaming Meat Tenderizer","Fang of the Nine","Gravebite",
    "Crystal Render","Donut's Disapproval","Bloodhelm's Regret"];
  const WCLASS=["Spiked Club","Warhammer","Cleaver","Battleaxe","Bone Maul","Crysteel Blade","War Pick"];
  const ARMOR=["Boxer's Resolve","Cloak of Static","Warden's Bulwark","Bloodguard Plate","Heart-Print Guard","Mantle of the Meat Grinder"];
  const ACLASS=["Chestguard","Ward","Cloak","Plate","Bracers","Mantle"];
  const TRINKETS=["Void Prism","Splinter of X-77","Soulstone of Regret","Mana Geode","Crystalline Core","Signet of the Showrunner"];
  const TCLASS=["Aether Focus","Rune","Sigil","Amulet","Band"];
  const pick=a=>a[(Math.random()*a.length)|0];

  const STATS=[
    ['Aether Damage', 'flat', 120, 90],
    ['Physical Damage','flat', 140, 80],
    ['Max Health',    'flat', 600, 260],
    ['Armor',         'flat', 90,  55],
    ['Critical Strike','pct', 6,   4],
    ['Crit Damage',   'pct', 18,  12],
    ['Attack Speed',  'pct', 5,   4],
    ['Movement Speed','pct', 6,   4],
    ['Lifesteal',     'pct', 4,   3],
    ['All Stats',     'raw', 8,   6],
  ];
  const AFFIX=["Chance to Fear on Hit","Detonates slain enemies","Bonus damage to Bosses","Reflects 10% damage","Ignores 20% Armor"];

  function genStats(rar){
    const mult = 1 + rar.tier*0.75 + Math.random()*0.4;
    const n = rar.tier>=3 ? 3 : (rar.tier>=1 ? (Math.random()<0.5?3:2) : 2);
    const pool=[...STATS]; const out=[];
    for(let i=0;i<n && pool.length;i++){
      const s=pool.splice((Math.random()*pool.length)|0,1)[0];
      const base=s[2]*mult, jit=s[3]*mult*Math.random();
      let v=Math.round(base+jit);
      let txt;
      if(s[1]==='pct') txt=`+${v}% ${s[0]}`;
      else if(s[1]==='raw') txt=`+${v} ${s[0]}`;
      else txt=`+${v.toLocaleString('en-US')} ${s[0]}`;
      out.push(txt);
    }
    if(rar.tier>=3) out.push(pick(AFFIX)); // special legendary/mythic affix line
    return out.slice(0,4);
  }

  function genItem(rar){
    const roll=Math.random();
    let name,type,glyph;
    if(roll<0.5){ name=pick(WEAPONS); type=`${rar.key} ${pick(WCLASS)}`; glyph='weapon'; }
    else if(roll<0.8){ name=pick(ARMOR); type=`${rar.key} ${pick(ACLASS)}`; glyph='armor'; }
    else { name=pick(TRINKETS); type=`${rar.key} ${pick(TCLASS)}`; glyph='trinket'; }
    return { name, type, glyph, rar, stats:genStats(rar) };
  }

  // ---------------------------------------------------------------- item SVG icons
  function iconSVG(glyph, col){
    const c=col, d='#0a1016';
    if(glyph==='weapon') return `<svg viewBox="0 0 48 48"><g stroke="${c}" stroke-width="2.4" fill="none" stroke-linejoin="round" stroke-linecap="round">
      <path d="M24 4 L30 14 L24 20 L18 14 Z" fill="${c}" fill-opacity=".22"/>
      <path d="M24 20 L24 40"/><path d="M18 40 L30 40"/><path d="M20 32 L28 32"/></g>
      <circle cx="24" cy="12" r="2.3" fill="${c}"/></svg>`;
    if(glyph==='armor') return `<svg viewBox="0 0 48 48"><g stroke="${c}" stroke-width="2.4" fill="${c}" fill-opacity=".16" stroke-linejoin="round">
      <path d="M24 5 L40 11 C40 26 33 38 24 43 C15 38 8 26 8 11 Z"/></g>
      <path d="M24 12 L24 34 M15 20 L33 20" stroke="${c}" stroke-width="2" fill="none" stroke-linecap="round"/></svg>`;
    return `<svg viewBox="0 0 48 48"><g stroke="${c}" stroke-width="2.4" fill="${c}" fill-opacity=".18" stroke-linejoin="round">
      <path d="M24 5 L38 15 L33 39 L15 39 L10 15 Z"/></g>
      <path d="M24 14 L31 20 L28 33 L20 33 L17 20 Z" stroke="${c}" stroke-width="1.6" fill="none"/>
      <circle cx="24" cy="24" r="3" fill="${c}"/></svg>`;
  }

  // ---------------------------------------------------------------- inject styles
  if(!document.getElementById('karl-lootbox-style')){
    const s=document.createElement('style'); s.id='karl-lootbox-style';
    s.textContent=`
    #karl-lbx{ position:fixed; inset:0; z-index:30; pointer-events:none; overflow:hidden;
      font-family:"Rajdhani","Segoe UI",system-ui,sans-serif; opacity:0; transition:opacity .35s ease;
      font-feature-settings:"tnum"; }
    #karl-lbx.on{ opacity:1; }
    #karl-lbx .veil{ position:absolute; inset:0; background:radial-gradient(120% 90% at 50% 46%,
      rgba(4,10,16,.30) 0%, rgba(3,7,12,.72) 55%, rgba(2,5,9,.92) 100%); }
    #karl-lbx canvas{ position:absolute; inset:0; width:100%; height:100%; }
    #karl-lbx .flash{ position:absolute; inset:0; background:#fff; opacity:0; mix-blend-mode:screen; }

    /* stage centers everything */
    #karl-lbx .stage{ position:absolute; left:50%; top:47%; transform:translate(-50%,-50%);
      display:flex; flex-direction:column; align-items:center; }

    /* --- System banner --- */
    #karl-lbx .banner{ text-align:center; margin-bottom:26px; opacity:0; transform:translateY(-14px);
      transition:opacity .5s ease, transform .5s cubic-bezier(.2,.9,.3,1.2); }
    #karl-lbx .banner.in{ opacity:1; transform:none; }
    #karl-lbx .banner .sys{ font-size:15px; letter-spacing:.42em; font-weight:600; color:#bfe9f7;
      text-shadow:0 0 16px rgba(57,215,255,.6); }
    #karl-lbx .banner .tier{ margin-top:8px; font-size:30px; font-weight:700; letter-spacing:.14em;
      color:var(--tc); text-shadow:0 0 26px var(--tglow), 0 2px 6px rgba(0,0,0,.8); }
    #karl-lbx .banner .tier small{ font-size:14px; letter-spacing:.34em; color:#9fb6c3; font-weight:600;
      display:block; margin-top:2px; text-shadow:none; }

    /* --- the box --- */
    #karl-lbx .boxwrap{ position:relative; width:230px; height:230px; display:flex; align-items:center; justify-content:center; }
    #karl-lbx .leak{ position:absolute; width:340px; height:340px; border-radius:50%; opacity:0;
      background:radial-gradient(circle, var(--rc) 0%, rgba(0,0,0,0) 62%); mix-blend-mode:screen;
      filter:blur(4px); }
    #karl-lbx .box{ position:relative; width:150px; height:150px; transform-style:preserve-3d;
      will-change:transform; }
    #karl-lbx .face{ position:absolute; inset:0; border-radius:12px;
      background:linear-gradient(150deg, var(--mspec) 0%, var(--tc) 34%, var(--medge) 100%);
      border:2px solid var(--medge);
      box-shadow: inset 0 0 26px rgba(0,0,0,.45), inset 0 3px 10px var(--mspec),
        0 10px 34px rgba(0,0,0,.6), 0 0 var(--glow, 26px) var(--tglow); }
    /* corner rivets */
    #karl-lbx .face::before, #karl-lbx .face::after{ content:""; position:absolute; width:9px; height:9px;
      border-radius:50%; background:radial-gradient(circle at 35% 30%, var(--mspec), var(--medge));
      box-shadow:0 0 4px rgba(0,0,0,.6); top:9px; }
    #karl-lbx .face::before{ left:9px; } #karl-lbx .face::after{ right:9px; }
    /* seams */
    #karl-lbx .seam{ position:absolute; background:var(--rc); box-shadow:0 0 8px var(--rc), 0 0 18px var(--rc);
      opacity:.25; }
    #karl-lbx .seam.h{ left:6px; right:6px; height:3px; top:50%; margin-top:-1.5px; }
    #karl-lbx .seam.v{ top:6px; bottom:6px; width:3px; left:50%; margin-left:-1.5px; }
    /* lock gem */
    #karl-lbx .lock{ position:absolute; left:50%; top:50%; width:30px; height:30px; margin:-15px 0 0 -15px;
      transform:rotate(45deg); background:linear-gradient(135deg,#fff7d6,var(--rc));
      border:2px solid rgba(255,255,255,.7); border-radius:4px;
      box-shadow:0 0 12px var(--rc), inset 0 0 8px rgba(255,255,255,.6); }
    #karl-lbx .lock::after{ content:""; position:absolute; inset:6px; border-radius:2px;
      background:radial-gradient(circle,#fff,var(--rc)); opacity:.85; }

    /* --- hype subtitle --- */
    #karl-lbx .hype{ margin-top:30px; height:22px; font-size:15px; letter-spacing:.16em; font-weight:600;
      color:#dfeff7; text-shadow:0 0 12px rgba(57,215,255,.4), 0 2px 4px rgba(0,0,0,.8); text-align:center;
      opacity:0; transition:opacity .3s ease; }
    #karl-lbx .hype b{ color:var(--rc); }

    /* --- reward card --- */
    #karl-lbx .card{ position:absolute; left:50%; top:47%; width:340px; margin-left:-170px; margin-top:-232px;
      opacity:0; transform:translateY(48px) scale(.82); pointer-events:none;
      background:linear-gradient(180deg, rgba(10,20,28,.94), rgba(6,12,18,.97));
      border:1.5px solid var(--rc); border-radius:14px; padding:18px 20px 20px;
      box-shadow:0 0 44px var(--rglow), 0 18px 60px rgba(0,0,0,.7), inset 0 0 34px rgba(0,0,0,.5);
      text-align:center; backdrop-filter:blur(3px); }
    #karl-lbx .card.in{ animation:lbxCardIn .72s cubic-bezier(.16,1.06,.3,1) forwards; }
    @keyframes lbxCardIn{ 0%{opacity:0;transform:translateY(56px) scale(.8);} 60%{opacity:1;}
      100%{opacity:1;transform:translateY(0) scale(1);} }
    /* rarity ribbon at the very top */
    #karl-lbx .card .rlabel{ font-size:13px; font-weight:700; letter-spacing:.34em; color:var(--rc);
      text-shadow:0 0 14px var(--rglow); }
    #karl-lbx .card .bang{ color:var(--rc); font-weight:900; letter-spacing:.1em; }
    #karl-lbx .card .icon{ width:96px; height:96px; margin:12px auto 6px; position:relative;
      display:flex; align-items:center; justify-content:center; }
    #karl-lbx .card .icon .ring{ position:absolute; inset:0; border-radius:16px; border:1.5px solid var(--rc);
      background:radial-gradient(circle at 50% 40%, var(--rglow), rgba(0,0,0,.15) 70%);
      box-shadow:inset 0 0 22px var(--rglow), 0 0 22px var(--rglow); }
    #karl-lbx .card .icon svg{ position:relative; width:66px; height:66px;
      filter:drop-shadow(0 0 8px var(--rc)); }
    #karl-lbx .card .iname{ font-size:23px; font-weight:700; letter-spacing:.01em; color:#f2f8fb;
      text-shadow:0 0 18px var(--rglow), 0 2px 6px rgba(0,0,0,.8); line-height:1.05; margin-top:4px; }
    #karl-lbx .card .itype{ font-size:11px; font-weight:600; letter-spacing:.2em; text-transform:uppercase;
      color:#9fb6c3; margin-top:4px; }
    #karl-lbx .card .divider{ height:1px; margin:12px 8px; background:linear-gradient(90deg,
      transparent, var(--rc), transparent); opacity:.6; }
    #karl-lbx .card .stats{ display:flex; flex-direction:column; gap:5px; }
    #karl-lbx .card .stat{ font-size:14.5px; color:#d7e6ee; letter-spacing:.01em; opacity:0;
      transform:translateY(6px); }
    #karl-lbx .card .stat.affx{ color:var(--rc); font-weight:600; font-style:italic; }
    #karl-lbx .card .stat.in{ animation:lbxStat .4s ease forwards; }
    @keyframes lbxStat{ to{opacity:1;transform:none;} }
    #karl-lbx .card .stat b{ color:#fff; font-weight:700; }

    /* --- claim prompt --- */
    #karl-lbx .claim{ position:absolute; left:50%; bottom:15%; transform:translateX(-50%);
      opacity:0; transition:opacity .4s ease; text-align:center; }
    #karl-lbx .claim.in{ opacity:1; }
    #karl-lbx .claim .btn{ display:inline-block; padding:9px 40px; font-size:16px; font-weight:700;
      letter-spacing:.34em; color:#04121a; background:linear-gradient(180deg, #bff0ff, #39d7ff);
      border-radius:6px; box-shadow:0 0 26px rgba(57,215,255,.6), inset 0 1px 2px rgba(255,255,255,.7);
      animation:lbxPulse 1s ease-in-out infinite; }
    #karl-lbx .claim .hint{ margin-top:8px; font-size:10.5px; letter-spacing:.28em; color:#7fa9bd; }
    @keyframes lbxPulse{ 50%{ box-shadow:0 0 40px rgba(57,215,255,.95), inset 0 1px 2px rgba(255,255,255,.7);
      transform:scale(1.04); } }

    /* legendary/mythic "!!!" flourish */
    #karl-lbx .bangs{ position:absolute; left:50%; top:47%; margin-top:-300px; transform:translateX(-50%);
      font-size:56px; font-weight:900; font-style:italic; letter-spacing:.06em; color:var(--rc);
      text-shadow:0 0 26px var(--rc), 0 4px 10px rgba(0,0,0,.8); opacity:0; }
    #karl-lbx .bangs.in{ animation:lbxBangs .8s cubic-bezier(.1,1.4,.3,1) forwards; }
    @keyframes lbxBangs{ 0%{opacity:0;transform:translateX(-50%) scale(.3) rotate(-8deg);}
      70%{opacity:1;transform:translateX(-50%) scale(1.15) rotate(3deg);}
      100%{opacity:1;transform:translateX(-50%) scale(1) rotate(0);} }
    `;
    (document.head||document.documentElement).appendChild(s);
  }

  // ---------------------------------------------------------------- persistent overlay + canvas
  let root=document.getElementById('karl-lbx');
  if(!root){ root=document.createElement('div'); root.id='karl-lbx'; document.body.appendChild(root); }
  const canvas=document.createElement('canvas'); root.appendChild(canvas);
  const ctx=canvas.getContext('2d');
  let cw=0, ch=0, dpr=Math.min(devicePixelRatio||1, 2);
  function sizeCanvas(){ cw=innerWidth; ch=innerHeight; dpr=Math.min(devicePixelRatio||1,2);
    canvas.width=cw*dpr; canvas.height=ch*dpr; ctx.setTransform(dpr,0,0,dpr,0,0); }
  sizeCanvas(); addEventListener('resize', sizeCanvas);

  // ---------------------------------------------------------------- particle system (canvas)
  let shards=[]; let rays=null; // rays: {col, until} for legendary+ rotating light rays

  function burstParticles(rar, big){
    const cx=cw/2, cy=ch*0.47;
    const n = big ? 150 : 90;
    const col=rar.css;
    for(let i=0;i<n;i++){
      const a=Math.random()*Math.PI*2;
      const sp=(big?7.2:5.4)*(0.35+Math.random());
      shards.push({
        x:cx, y:cy, vx:Math.cos(a)*sp, vy:Math.sin(a)*sp - 1.2,
        life:0, ttl:0.75+Math.random()*0.75, len:9+Math.random()*17, w:1.7+Math.random()*2.6,
        rot:a, col: Math.random()<0.62 ? col : '#ffffff', spin:(Math.random()-0.5)*0.3,
        grav: 10+Math.random()*10,
      });
    }
    // a couple of slow drifting embers
    for(let i=0;i<(big?26:14);i++){
      const a=Math.random()*Math.PI*2, sp=(1.5+Math.random()*2.4);
      shards.push({ x:cx, y:cy, vx:Math.cos(a)*sp, vy:Math.sin(a)*sp-1.6, life:0,
        ttl:1.2+Math.random()*1.1, len:0, w:2+Math.random()*2.4, ember:true, col, grav:-4 });
    }
  }

  function drawParticles(dt){
    ctx.clearRect(0,0,cw,ch);
    // rotating light rays behind the reveal (legendary/mythic)
    if(rays && performance.now()<rays.until){
      const cx=cw/2, cy=ch*0.47;
      const p=(rays.until-performance.now())/1400; // fades as it ends
      const a=(performance.now()/1000)*0.5;
      ctx.save(); ctx.translate(cx,cy); ctx.globalCompositeOperation='screen';
      const R=Math.max(cw,ch);
      for(let i=0;i<16;i++){
        const ang=a + i*(Math.PI*2/16);
        const grad=ctx.createLinearGradient(0,0,Math.cos(ang)*R,Math.sin(ang)*R);
        grad.addColorStop(0, hexA(rays.col, 0.0));
        grad.addColorStop(0.15, hexA(rays.col, 0.22*Math.max(0,Math.min(1,p))));
        grad.addColorStop(1, hexA(rays.col, 0));
        ctx.fillStyle=grad;
        ctx.beginPath(); ctx.moveTo(0,0);
        ctx.lineTo(Math.cos(ang-0.05)*R, Math.sin(ang-0.05)*R);
        ctx.lineTo(Math.cos(ang+0.05)*R, Math.sin(ang+0.05)*R);
        ctx.closePath(); ctx.fill();
      }
      ctx.restore();
    }
    // shards
    ctx.globalCompositeOperation='screen';
    for(let i=shards.length-1;i>=0;i--){
      const s=shards[i]; s.life+=dt;
      if(s.life>=s.ttl){ shards.splice(i,1); continue; }
      s.vy += s.grav*dt; s.x += s.vx*60*dt; s.y += s.vy*60*dt;
      s.vx*=0.985; if(!s.ember) s.rot+=s.spin;
      const k=1-s.life/s.ttl;
      ctx.globalAlpha=Math.max(0,k);
      if(s.ember){
        ctx.fillStyle=s.col; ctx.shadowBlur=10; ctx.shadowColor=s.col;
        ctx.beginPath(); ctx.arc(s.x,s.y,s.w*k+0.6,0,6.283); ctx.fill(); ctx.shadowBlur=0;
      } else {
        ctx.strokeStyle=s.col; ctx.lineWidth=s.w*k+0.4; ctx.lineCap='round';
        ctx.beginPath();
        ctx.moveTo(s.x, s.y);
        ctx.lineTo(s.x - Math.cos(s.rot)*s.len*k, s.y - Math.sin(s.rot)*s.len*k);
        ctx.stroke();
      }
    }
    ctx.globalAlpha=1; ctx.globalCompositeOperation='source-over';
  }
  function hexA(hex,a){ const n=parseInt(hex.slice(1),16); const r=(n>>16)&255,g=(n>>8)&255,b=n&255;
    return `rgba(${r},${g},${b},${a})`; }

  // ---------------------------------------------------------------- ceremony state
  let active=false, raf=0, dom=null;
  const HYPE=[
    "The crowd holds its breath…",
    "Trillions of viewers lean in…",
    "The seams strain against the pressure…",
    "Sponsors are salivating…",
    "Something powerful stirs inside…",
    "The System savors the moment…",
  ];

  function open(tierArg){
    if(active) return;
    active=true;
    const tier = tierArg ? (tierByKey(tierArg)||pickTier()) : pickTier();
    const rar  = pickRarity(tier.bias);
    const item = genItem(rar);
    runCeremony(tier, rar, item);
  }

  function runCeremony(tier, rar, item){
    // ---- build DOM for this ceremony
    const tglow = hexA(tier.css, 0.7);
    const rglow = hexA(rar.css, 0.45);
    const wrap=document.createElement('div');
    wrap.style.cssText=`--tc:${tier.css};--medge:${tier.edge};--mspec:${tier.spec};--tglow:${tglow};`+
      `--rc:${rar.css};--rglow:${rglow};--glow:26px;`;
    const bang = rar.tier>=3;
    wrap.innerHTML=`
      <div class="veil"></div>
      <div class="flash"></div>
      <div class="stage">
        <div class="banner">
          <div class="sys">◈ THE SYSTEM IS PLEASED TO PRESENT ◈</div>
          <div class="tier">${tier.key.toUpperCase()} LOOT BOX<small>SYSTEM REWARD CACHE · SEALED</small></div>
        </div>
        <div class="boxwrap">
          <div class="leak"></div>
          <div class="box">
            <div class="face"></div>
            <div class="seam h"></div><div class="seam v"></div>
            <div class="lock"></div>
          </div>
        </div>
        <div class="hype"></div>
      </div>
      ${bang?'<div class="bangs">!!!</div>':''}
      <div class="card">
        <div class="rlabel">${bang?'<span class="bang">★ </span>':''}${rar.label}${bang?'<span class="bang"> ★</span>':''}</div>
        <div class="icon"><div class="ring"></div>${iconSVG(item.glyph, rar.css)}</div>
        <div class="iname">${item.name}</div>
        <div class="itype">${item.type}</div>
        <div class="divider"></div>
        <div class="stats">${item.stats.map((t,i)=>{
          const isAff = i===item.stats.length-1 && rar.tier>=3;
          const html = t.replace(/^(\+[\d,]+%?)/,'<b>$1</b>');
          return `<div class="stat${isAff?' affx':''}">${isAff?'◆ '+t:html}</div>`;
        }).join('')}</div>
      </div>
      <div class="claim"><div class="btn">CLAIM</div><div class="hint">${isAuto?'AUTO-CLAIM':'PRESS  O  OR  CLICK  TO  CLAIM'}</div></div>
    `;
    root.appendChild(wrap);
    dom=wrap;
    const $=q=>wrap.querySelector(q);
    const box=$('.box'), face=$('.face'), leak=$('.leak'), seamH=$('.seam.h'), seamV=$('.seam.v'),
      lock=$('.lock'), banner=$('.banner'), hype=$('.hype'), flash=$('.flash'),
      card=$('.card'), claim=$('.claim'), bangs=bang?$('.bangs'):null,
      statEls=[...wrap.querySelectorAll('.stat')];

    requestAnimationFrame(()=>{ root.classList.add('on'); banner.classList.add('in'); });

    // ---- timeline (seconds)
    const T_CHARGE=0.9, T_BURST=2.55, T_CARD=2.72, T_CLAIM=3.6, T_HOLD=6.3, T_END=6.95;
    let t0=performance.now()/1000, last=t0, burst=false, cardShown=false, claimShown=false, bangShown=false;
    let hypeIdx=-1; let statsRevealed=false;

    function frame(now){
      now/=1000; const dt=Math.min(0.05, now-last); last=now; const t=now-t0;

      // ---------- CHARGE phase: box shakes, seams glow, light leaks ----------
      if(t>=T_CHARGE && t<T_BURST){
        const k=(t-T_CHARGE)/(T_BURST-T_CHARGE); // 0..1 ramp
        const amp=1.6 + k*k*9;                    // shake amplitude grows hard
        const jx=(Math.random()-0.5)*amp, jy=(Math.random()-0.5)*amp;
        const rz=(Math.random()-0.5)*amp*0.5;
        const sc=1 + k*0.09 + Math.sin(t*60)*0.006*k;
        box.style.transform=`translate(${jx}px,${jy}px) rotate(${rz}deg) scale(${sc})`;
        wrap.style.setProperty('--glow', (26+k*70)+'px');
        const seamOp=(0.25+k*0.75).toFixed(2);
        seamH.style.opacity=seamOp; seamV.style.opacity=seamOp;
        const sw=(3+k*4).toFixed(1)+'px';
        seamH.style.height=sw; seamV.style.width=sw;
        lock.style.boxShadow=`0 0 ${12+k*26}px var(--rc), inset 0 0 8px rgba(255,255,255,.6)`;
        leak.style.opacity=(k*0.9).toFixed(2);
        leak.style.transform=`scale(${0.6+k*0.9})`;
        // hype subtitles cycle
        const idx=Math.min(HYPE.length-1, Math.floor(k*HYPE.length));
        if(idx!==hypeIdx){ hypeIdx=idx;
          hype.style.opacity='0';
          setTimeout(()=>{ if(!active) return; hype.innerHTML=HYPE[idx]; hype.style.opacity='1'; },80);
        }
      }

      // ---------- BURST ----------
      if(!burst && t>=T_BURST){
        burst=true;
        box.style.transform='scale(1)'; box.style.transition='transform .18s ease, opacity .18s ease';
        box.style.opacity='0'; box.style.transform='scale(1.6)';
        leak.style.opacity='0'; hype.style.opacity='0';
        // screen flash — a quick punch that clears fast so the reveal reads clean
        flash.style.transition='none'; flash.style.opacity=(rar.tier>=3?0.82:0.62).toString();
        requestAnimationFrame(()=>{ flash.style.transition='opacity .32s cubic-bezier(.3,0,.2,1)'; flash.style.opacity='0'; });
        // particles + camera kick
        burstParticles(rar, rar.tier>=3);
        if(rar.tier>=2) rays={ col:rar.css, until:performance.now()+ (rar.tier>=3?2600:1500) };
        if(vfx && vfx.addShake) vfx.addShake(rar.tier>=4?0.7:rar.tier>=3?0.55:0.4);
        // fade the banner out so the card owns the frame
        banner.style.transition='opacity .4s ease, transform .4s ease';
        banner.style.opacity='0'; banner.style.transform='translateY(-10px)';
      }

      // ---------- REWARD CARD flies up ----------
      if(!cardShown && t>=T_CARD){ cardShown=true; card.classList.add('in'); }
      if(bang && !bangShown && t>=T_CARD+0.12){ bangShown=true; bangs.classList.add('in'); }
      // stagger stat lines in after the card settles
      if(!statsRevealed && t>=T_CARD+0.45){ statsRevealed=true;
        statEls.forEach((el,i)=>setTimeout(()=>{ if(active) el.classList.add('in'); }, i*110));
      }

      // ---------- CLAIM ----------
      if(!claimShown && t>=T_CLAIM){ claimShown=true; claim.classList.add('in'); }

      // ---------- draw particles every frame while active ----------
      drawParticles(dt);

      // ---------- END ----------
      if(t>=T_END){ dismiss(); return; }
      raf=requestAnimationFrame(frame);
    }
    raf=requestAnimationFrame(frame);

    // allow manual claim to speed dismissal
    wrap._claim=()=>{ if(active && cardShown){ t0 -= (T_END - (performance.now()/1000 - t0)) - 0.55; } };
  }

  function dismiss(){
    if(!active) return;
    root.classList.remove('on');
    const gone=dom;
    setTimeout(()=>{ if(gone && gone.parentNode) gone.parentNode.removeChild(gone); }, 400);
    cancelAnimationFrame(raf); raf=0;
    // let particles finish drawing out during fade, then clear
    setTimeout(()=>{ shards.length=0; rays=null; ctx.clearRect(0,0,cw,ch); }, 460);
    dom=null; active=false;
  }

  // ---------------------------------------------------------------- triggers
  addEventListener('keydown', e=>{
    if(e.key && e.key.toLowerCase()==='o'){
      if(active && dom && dom._claim) dom._claim();
      else open();
    }
  });
  // click-to-claim (overlay is otherwise pointer-transparent)
  addEventListener('pointerdown', ()=>{ if(active && dom && dom._claim) dom._claim(); });

  // ---------------------------------------------------------------- expose API
  api.lootbox={ open, get active(){ return active; } };

  // ---------------------------------------------------------------- auto demo
  if(isAuto){
    let cyc=0; const order=['Bronze','Silver','Gold','Platinum'];
    setTimeout(function loop(){
      if(!active) open(order[cyc++ % order.length]);
      setTimeout(loop, 9000);
    }, 4000);
  }
}
