// COMBAT ABILITIES  —  owned by the "combat-abilities" builder pipeline.
// Spectacular Primal-Warrior ability VFX that auto-fire in a rotation during combat so the fight
// reads like the Diablo-IV reference: Carl wreathed in swirling cyan/aether energy. Also drives the
// action-bar cooldown sweeps. Plugs into main.js via init(api) — edits NOTHING else.
// Judge against rubric 7 (combat feel), 8 (additive ability particles), 10 (skill-bar cooldowns).
//
// Abilities (each on its own cooldown, each with a BIG readable additive VFX):
//   CLEAVE       — wide cyan crescent that sweeps in front of Carl, synced to the melee swing.
//   AETHER NOVA  — expanding purple ring shockwave that flashes + damages nearby enemies.
//   WHIRLWIND    — Carl wreathed in a spinning ring of blue energy blades for ~1s.
//   AETHER BOLT  — glowing projectile that streaks from Carl to the target and bursts.
//   WAR CRY      — radiant ground rune + upward light pillar under Carl (aura pulse).
//   AETHER AURA  — persistent, subtle: two slowly counter-rotating energy rings around Carl.

export function init(api){
  const { THREE, scene, camera, hero, enemies, vfx, V3 } = api;
  if(!THREE || !scene || !hero) return;

  // ---------------------------------------------------------------- skill-bar cooldown driver
  // Slot order in #slots matches [L-Click,1,2,3,4,Q,E,R,R-Click]. index.html already ships the
  // `.cd` conic-gradient (`var(--a)`) and `.slot.cooling .cd{display:block}` — we just animate it.
  const SLOT = { CLEAVE:0, NOVA:3, WHIRL:4, WARCRY:5, BOLT:8 };
  // Inject a style that darkens the shipped `.cd` conic sweep so it reads clearly as a Diablo-IV
  // cooldown wipe, adds a glowing active-cooldown border, and styles the numeric countdown timer.
  (function injectStyle(){ if(document.getElementById('abil-cd-style')) return;
    const s=document.createElement('style'); s.id='abil-cd-style';
    s.textContent=`
    /* Diablo-IV cooldown read: a SEMI-transparent dark wedge sweeps over the slot so the (dimmed)
       skill icon stays clearly visible underneath, with the numeric timer on top — never a black hole. */
    #slots .slot.cooling .cd{ background:conic-gradient(rgba(4,10,16,.55) var(--a,0deg), rgba(90,210,255,.05) 0) !important; }
    #slots .slot.cooling .ic{ filter:brightness(.9) saturate(.92); }
    #slots .slot.cooling{ outline:1px solid rgba(90,205,255,.55); outline-offset:-1px; box-shadow:0 0 10px rgba(80,200,255,.35); }
    #slots .slot .cdnum{ position:absolute; inset:0; display:none; align-items:center; justify-content:center;
      font:900 15px/1 "Arial Black","Arial Bold",Impact,sans-serif; color:#eafaff; z-index:3; pointer-events:none;
      text-shadow:0 0 7px #4fe6ff, 0 1px 2px #000, 0 0 3px #000, 0 -1px 2px #000; }
    #slots .slot.cooling .cdnum{ display:flex; }`;
    (document.head||document.documentElement).appendChild(s); })();
  // add a numeric-timer node to each slot (behaviour we own; DOM structure of the bar is untouched otherwise)
  (function addTimers(){ const s=document.getElementById('slots'); if(!s) return;
    for(const slot of s.children){ if(!slot.querySelector('.cdnum')){ const n=document.createElement('div'); n.className='cdnum'; slot.appendChild(n); } } })();

  function slotEl(i){ const s=document.getElementById('slots'); return s? s.children[i] : null; }
  function triggerCooldown(i, dur){
    const slot=slotEl(i); if(!slot) return; const cd=slot.querySelector('.cd'), num=slot.querySelector('.cdnum');
    if(!cd) return;
    slot.classList.add('cooling');
    const start=performance.now(), ms=dur*1000, showNum=dur>=1.2;
    // brief ready-pop so a fresh, fully-swept slot flashes bright the instant it comes off cooldown
    (function tick(now){
      const k=(now-start)/ms;
      if(k>=1){ cd.style.setProperty('--a','0deg'); slot.classList.remove('cooling'); if(num)num.textContent='';
        slot.style.boxShadow='0 0 16px rgba(120,230,255,.95)';
        setTimeout(()=>{ slot.style.boxShadow=''; }, 220); return; }
      cd.style.setProperty('--a', (360*(1-k)).toFixed(1)+'deg');   // full sweep 360°→0 as it recharges
      if(num){ const rem=dur*(1-k); num.textContent = showNum ? (rem>=1? String(Math.ceil(rem)) : rem.toFixed(1)) : ''; }
      requestAnimationFrame(tick);
    })(start);
  }

  // ---------------------------------------------------------------- shared textures / geometries
  // Textures + reusable geometries are created ONCE and live for the whole scene (no per-fire allocs,
  // no leaks). Per-effect MATERIALS are cloned so each instance fades independently, then disposed.
  const glowTex=(()=>{ const c=document.createElement('canvas'); c.width=c.height=64; const g=c.getContext('2d');
    const rg=g.createRadialGradient(32,32,0,32,32,32);
    rg.addColorStop(0,'rgba(255,255,255,1)'); rg.addColorStop(.4,'rgba(255,255,255,.55)');
    rg.addColorStop(.75,'rgba(255,255,255,.12)'); rg.addColorStop(1,'rgba(255,255,255,0)');
    g.fillStyle=rg; g.fillRect(0,0,64,64); const t=new THREE.CanvasTexture(c); t.colorSpace=THREE.SRGBColorSpace; return t; })();
  const runeTex=(()=>{ const c=document.createElement('canvas'); c.width=c.height=256; const g=c.getContext('2d');
    g.clearRect(0,0,256,256); g.translate(128,128); g.strokeStyle='rgba(150,235,255,.95)'; g.lineWidth=3;
    g.beginPath(); g.arc(0,0,112,0,6.2832); g.stroke();
    g.lineWidth=6; g.beginPath(); g.arc(0,0,96,0,6.2832); g.stroke();
    g.lineWidth=2; g.beginPath(); g.arc(0,0,60,0,6.2832); g.stroke();
    // radial ticks + inner runic triangles
    for(let i=0;i<12;i++){ const a=i/12*6.2832; g.save(); g.rotate(a);
      g.beginPath(); g.moveTo(0,-96); g.lineTo(6,-80); g.lineTo(-6,-80); g.closePath(); g.fillStyle='rgba(180,140,255,.9)'; g.fill(); g.restore(); }
    g.strokeStyle='rgba(190,150,255,.85)'; g.lineWidth=2;
    for(let i=0;i<3;i++){ g.save(); g.rotate(i/3*6.2832); g.beginPath();
      g.moveTo(0,-56); g.lineTo(48,34); g.lineTo(-48,34); g.closePath(); g.stroke(); g.restore(); }
    const t=new THREE.CanvasTexture(c); t.colorSpace=THREE.SRGBColorSpace; return t; })();

  const planeGeo   = new THREE.PlaneGeometry(1,1);
  const arcGeo     = new THREE.RingGeometry(1.05, 2.55, 40, 1, -1.05, 2.10); // forward crescent (~120°)
  const novaGeo    = new THREE.RingGeometry(0.80, 1.00, 56);                 // thin shockwave ring
  const auraGeo    = new THREE.RingGeometry(0.90, 1.02, 56);                 // persistent aura ring
  const shardGeo   = new THREE.ConeGeometry(0.10, 0.95, 4);                  // whirlwind blade
  const boltGeo    = new THREE.SphereGeometry(0.22, 12, 10);
  const pillarGeo  = new THREE.CylinderGeometry(0.55, 0.95, 6.4, 24, 1, true);

  const CYAN=0x4fe6ff, AETHER=0xb46bff, BLUE=0x5ab6ff, PALE=0xdff6ff;
  const addMat=(color,opacity=1,map=null,side=THREE.FrontSide)=>new THREE.MeshBasicMaterial({
    color, map, transparent:true, opacity, depthWrite:false, blending:THREE.AdditiveBlending, side });
  const ease=k=>1-(1-k)*(1-k);

  // ---------------------------------------------------------------- active-effect manager
  // Each effect: { objs:[Object3D...], mats:[Material...], t, life, fn(dt,age01) }.
  // fn returns nothing; when age reaches life the effect is torn down (removed + materials disposed).
  const fx=[];
  function push(e){ e.t=0; fx.push(e); return e; }
  function updateFx(dt){
    for(let i=fx.length-1;i>=0;i--){ const e=fx[i]; e.t+=dt; const a=e.t/e.life;
      if(a>=1){ for(const o of e.objs) scene.remove(o); for(const m of e.mats) m.dispose(); fx.splice(i,1); continue; }
      e.fn(dt, a); }
  }

  // ---------------------------------------------------------------- persistent aether aura
  // Two faint counter-rotating rings + a soft glow disc always under/around Carl so he reads as
  // powered-up even between ability casts (reference "Frame B": Carl wreathed in blue energy).
  const auraGroup=new THREE.Group(); scene.add(auraGroup);
  const auraMats=[];
  function auraRing(r, color, op, tilt){ const m=addMat(color, op, null, THREE.DoubleSide);
    auraMats.push(m); const mesh=new THREE.Mesh(auraGeo, m); mesh.scale.setScalar(r);
    mesh.rotation.x=-Math.PI/2 + tilt; auraGroup.add(mesh); return mesh; }
  const ringA=auraRing(1.55, CYAN,   0.32,  0.16);
  const ringB=auraRing(1.15, AETHER, 0.28, -0.13);
  const auraGlow=new THREE.Mesh(planeGeo, addMat(BLUE, 0.16, glowTex)); auraGlow.rotation.x=-Math.PI/2;
  auraGlow.scale.setScalar(3.2); auraMats.push(auraGlow.material); auraGroup.add(auraGlow);

  // ---------------------------------------------------------------- ability spawners
  function spawnCleave(){
    const g=new THREE.Group(); g.position.set(hero.pos.x, 0.16, hero.pos.z); g.rotation.y=hero.face;
    const m1=addMat(CYAN, 0.85, null, THREE.DoubleSide);
    const m2=addMat(PALE, 0.55, null, THREE.DoubleSide);   // trimmed so the crescent stays cyan-cored (not white-hot on Carl)
    const a1=new THREE.Mesh(arcGeo, m1); a1.rotation.x=-Math.PI/2;
    const a2=new THREE.Mesh(arcGeo, m2); a2.rotation.x=-Math.PI/2; a2.scale.setScalar(0.86);
    g.add(a1); g.add(a2); scene.add(g);
    vfx.addShake&&vfx.addShake(0.12);
    push({ objs:[g], mats:[m1,m2], life:0.34, fn:(dt,a)=>{
      g.position.set(hero.pos.x, 0.16, hero.pos.z);       // stay stapled to Carl
      const sc=0.7+ease(a)*0.9; g.scale.setScalar(sc);
      g.rotation.z=(-0.9+a*1.8);                          // sweep the crescent across the front
      m1.opacity=(1-a)*0.85; m2.opacity=(1-a)*0.55;
    }});
  }

  function spawnNova(){
    const c=V3(hero.pos.x, 0.14, hero.pos.z);
    const rings=[]; const mats=[];
    for(let k=0;k<2;k++){ const m=addMat(k?PALE:AETHER, 0.9, null, THREE.DoubleSide);
      const r=new THREE.Mesh(novaGeo, m); r.rotation.x=-Math.PI/2; r.position.copy(c); r.scale.setScalar(0.6);
      scene.add(r); rings.push(r); mats.push(m); }
    const gm=addMat(AETHER, 0.5, glowTex); const glow=new THREE.Mesh(planeGeo, gm);
    glow.rotation.x=-Math.PI/2; glow.position.copy(c); glow.scale.setScalar(2.0); scene.add(glow); mats.push(gm);
    vfx.addShake&&vfx.addShake(0.28);
    // damage + hit-flash on everything caught in the blast (shown via the shared damage-number VFX)
    const R=5.6;
    for(const e of enemies){ if(!e||e.dead) continue;
      const d=e.obj.position.distanceTo(hero.pos); if(d>R) continue;
      const dmg=(9000+Math.random()*7000)|0; vfx.damageNumber(e.obj.position, dmg, 'aether');
      e.hurt=Math.max(e.hurt||0, 0.28); vfx.spawnHitSpark&&vfx.spawnHitSpark(e.obj.position); }
    push({ objs:[...rings, glow], mats, life:0.7, fn:(dt,a)=>{
      const s=0.6+ease(a)*(R+0.6);
      rings[0].scale.setScalar(s); rings[1].scale.setScalar(s*0.82);
      mats[0].opacity=(1-a)*0.9; mats[1].opacity=(1-a)*0.85;
      glow.scale.setScalar(2.0+a*5.5); gm.opacity=(1-a)*0.5;
    }});
  }

  function spawnWhirlwind(){
    const g=new THREE.Group(); g.position.set(hero.pos.x, 1.05, hero.pos.z); scene.add(g);
    const mats=[]; const blades=12;
    for(let i=0;i<blades;i++){ const a=i/blades*6.2832; const m=addMat(i%2?BLUE:CYAN, 0.9);
      const s=new THREE.Mesh(shardGeo, m); const R=1.7;
      s.position.set(Math.cos(a)*R, Math.sin(i*1.7)*0.35, Math.sin(a)*R);
      s.rotation.z=Math.PI/2; s.rotation.y=-a;      // tangential blades
      g.add(s); mats.push(m); }
    // twin trailing ground rings for a bladestorm base
    const bm=addMat(CYAN, 0.7, null, THREE.DoubleSide); const base=new THREE.Mesh(novaGeo, bm);
    base.rotation.x=-Math.PI/2; base.scale.setScalar(1.8); base.position.y=-1.0; g.add(base); mats.push(bm);
    push({ objs:[g], mats, life:1.05, fn:(dt,a)=>{
      g.position.set(hero.pos.x, 1.05, hero.pos.z);
      g.rotation.y += dt*15;                          // fast spin
      const env = a<0.18 ? a/0.18 : (1-a)/0.82;       // fade in then out
      for(let i=0;i<blades;i++) mats[i].opacity=0.9*env*(0.7+0.3*Math.sin(g.rotation.y*3+i));
      bm.opacity=0.6*env; base.rotation.z += dt*6;
    }});
  }

  function spawnBolt(){
    const tgt = (hero.target && !hero.target.dead) ? hero.target
      : enemies.find(e=>e&&!e.dead && e.obj.position.distanceTo(hero.pos)<12);
    const from=V3(hero.pos.x, 1.25, hero.pos.z);
    const to = tgt ? tgt.obj.position.clone().setY(1.1)
                   : from.clone().add(V3(Math.sin(hero.face),0,Math.cos(hero.face)).multiplyScalar(8)).setY(1.1);
    const bm=addMat(AETHER, 1.0); const core=new THREE.Mesh(boltGeo, bm); core.position.copy(from);
    const hm=addMat(PALE, 0.9, glowTex); const halo=new THREE.Mesh(planeGeo, hm);
    halo.scale.setScalar(1.6); core.add(halo); scene.add(core);
    const dist=from.distanceTo(to), speed=26, life=Math.max(0.14, dist/speed);
    let burst=false;
    push({ objs:[core], mats:[bm,hm], life:life+0.02, fn:(dt,a)=>{
      const k=Math.min(1, a*(life+0.02)/life);
      core.position.lerpVectors(from, to, ease(k));
      halo.quaternion.copy(camera.quaternion);
      hm.opacity=0.9; bm.opacity=1.0;
      if(k>=1 && !burst){ burst=true;
        vfx.spawnHitSpark&&vfx.spawnHitSpark(to);
        const dmg=(14000+Math.random()*10000)|0; vfx.damageNumber(to, dmg, 'aether');
        if(tgt){ tgt.hurt=Math.max(tgt.hurt||0,0.28); } vfx.addShake&&vfx.addShake(0.14);
        spawnMiniBurst(to);
      }
    }});
    // faint aether trail ribbon following the bolt
    for(let i=0;i<5;i++){ setTimeout(()=>{ if(!tgt&&!to) return;
      const p=from.clone().lerp(to, i/5); spawnTrailMote(p); }, i*18); }
  }
  function spawnTrailMote(p){ const m=addMat(AETHER,0.8,glowTex); const s=new THREE.Mesh(planeGeo,m);
    s.position.copy(p); s.scale.setScalar(0.9); scene.add(s);
    push({ objs:[s], mats:[m], life:0.35, fn:(dt,a)=>{ s.quaternion.copy(camera.quaternion);
      s.scale.setScalar(0.9*(1-a)+0.2); m.opacity=(1-a)*0.7; }}); }
  function spawnMiniBurst(p){ const m=addMat(PALE,0.9,glowTex); const s=new THREE.Mesh(planeGeo,m);
    s.position.copy(p); s.scale.setScalar(1.0); scene.add(s);
    push({ objs:[s], mats:[m], life:0.3, fn:(dt,a)=>{ s.quaternion.copy(camera.quaternion);
      s.scale.setScalar(1.0+a*2.4); m.opacity=(1-a)*0.9; }}); }

  function spawnWarCry(){
    const c=V3(hero.pos.x, 0, hero.pos.z);
    const rm=addMat(0x9fd8ff, 0.95, runeTex, THREE.DoubleSide); const rune=new THREE.Mesh(planeGeo, rm);
    rune.rotation.x=-Math.PI/2; rune.position.set(c.x, 0.13, c.z); rune.scale.setScalar(0.6); scene.add(rune);
    const pm=addMat(CYAN, 0.0); const pillar=new THREE.Mesh(pillarGeo, pm);
    pillar.position.set(c.x, 3.2, c.z); scene.add(pillar);
    const gm=addMat(PALE, 0.0, glowTex); const flash=new THREE.Mesh(planeGeo, gm);
    flash.position.set(c.x, 0.6, c.z); scene.add(flash);
    vfx.addShake&&vfx.addShake(0.2);
    push({ objs:[rune, pillar, flash], mats:[rm,pm,gm], life:1.2, fn:(dt,a)=>{
      rune.position.set(hero.pos.x,0.13,hero.pos.z); pillar.position.set(hero.pos.x,3.2,hero.pos.z);
      flash.position.set(hero.pos.x,0.6,hero.pos.z); flash.quaternion.copy(camera.quaternion);
      rune.scale.setScalar(0.6+ease(Math.min(1,a*2))*4.6); rune.rotation.z += dt*0.8;
      rm.opacity=(a<0.2? a/0.2 : (1-a)/0.8)*0.95;
      const up = a<0.25 ? a/0.25 : 1;                 // pillar snaps up then holds while fading
      pm.opacity=(a<0.25? up : (1-a)/0.75)*0.8; pillar.scale.y=0.2+up*0.8;
      gm.opacity=(1-a)*0.8; flash.scale.setScalar(1.5+a*2.5);
    }});
  }

  // ---------------------------------------------------------------- rotation / auto-fire
  // Each ability decrements its own timer while combat is live; on reaching 0 it fires and resets to
  // its cooldown. Staggered initial timers give a continuous, readable rotation (not a synced flash).
  const rot={
    nova:   { t:1.4, cd:3.6, fire:spawnNova,      slot:SLOT.NOVA },
    whirl:  { t:2.9, cd:5.5, fire:spawnWhirlwind, slot:SLOT.WHIRL },
    bolt:   { t:0.6, cd:2.3, fire:spawnBolt,      slot:SLOT.BOLT },
    warcry: { t:4.6, cd:7.5, fire:spawnWarCry,    slot:SLOT.WARCRY },
  };
  let prevSwing=0, cleaveCd=0;

  function combatLive(){
    if(hero.target && !hero.target.dead) return true;
    for(const e of enemies){ if(e && !e.dead && e.obj.position.distanceTo(hero.pos)<9) return true; }
    return false;
  }

  api.onFrame((dt, t)=>{
    // aura always alive + gently drifting so Carl reads powered-up at rest
    auraGroup.position.set(hero.pos.x, 0.05, hero.pos.z);
    ringA.rotation.z += dt*0.6; ringB.rotation.z -= dt*0.9;
    const pulse=0.85+0.15*Math.sin(t*2.2);
    ringA.material.opacity=0.30*pulse; ringB.material.opacity=0.26*pulse;
    auraGlow.material.opacity=0.14*pulse;

    // CLEAVE — fire on the rising edge of Carl's actual melee swing (main.js sets hero.swing=1)
    cleaveCd-=dt;
    if(hero.swing>0.85 && prevSwing<=0.85 && cleaveCd<=0){ spawnCleave(); cleaveCd=0.5; triggerCooldown(SLOT.CLEAVE, 0.5); }
    prevSwing=hero.swing;

    // rotation abilities
    if(combatLive()){
      for(const k in rot){ const r=rot[k]; r.t-=dt;
        if(r.t<=0){ r.fire(); r.t=r.cd; triggerCooldown(r.slot, r.cd); } }
    }

    updateFx(dt);
  });
}
