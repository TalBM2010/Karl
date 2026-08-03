// Dungeon Karl — orchestration & game loop. Owns hero state, input, AI, camera, and the
// auto-demo director. Visual pieces live in env.js / actors.js / vfx.js / hud.js so builder
// subagents can improve them in parallel without colliding here.
import * as THREE from 'three';
import { V3, lerp, rand, AUTO } from './util.js';
import { initEnvironment } from './env.js';
import { buildCarl, buildDonut, buildSpider } from './actors.js';
import { createVfx } from './vfx.js';
import { initHud } from './hud.js';
import { makeBlob } from './util.js';

// ---- renderer / scene / camera
const container=document.getElementById('game');
const renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio,2)); renderer.setSize(innerWidth,innerHeight);
renderer.shadowMap.enabled=true; renderer.shadowMap.type=THREE.PCFSoftShadowMap;
container.appendChild(renderer.domElement);
const scene=new THREE.Scene();
const camera=new THREE.PerspectiveCamera(38, innerWidth/innerHeight, 0.1, 400);
// Diablo-IV framing: fixed pitched iso angle (same ~44° pitch as before), pulled in tighter
// so Carl reads as a prominent hero (~1/6 frame height) sitting in the lower-middle.
const CAM_OFF=V3(11.5,15.5,11.5); let camTarget=V3(), camPos=camTarget.clone().add(CAM_OFF);
// Boss framing: SAME fixed iso pitch (uniform scale of CAM_OFF preserves the angle exactly),
// pulled BACK + UP so the whole ~11u-tall Juicer (head→feet) plus Carl are comfortably framed.
const CAM_OFF_BOSS=CAM_OFF.clone().multiplyScalar(1.62);
let bossW=0; // 0 = tight hero framing, 1 = full-boss framing (lerped so the transition is smooth)

const env=initEnvironment(scene, renderer);
const vfx=createVfx(scene, camera, document.getElementById('fct'));
const hud=initHud();

// ---- actors
const carl=buildCarl(); scene.add(carl); const carlBlob=makeBlob(1); scene.add(carlBlob);
const donut=buildDonut(); donut.position.set(-2,0,1.5); scene.add(donut); const donutBlob=makeBlob(.5); scene.add(donutBlob);
const enemies=[];
// Generic enemy registration (used by spiders AND plug-in modules like the boss).
function addEnemy(obj, {hp=1200, scale=1, isBoss=false, blobSize=null, onUpdate=null}={}){
  scene.add(obj); const b=makeBlob(blobSize ?? (.8*scale)); scene.add(b);
  const e={obj,blob:b,hp,maxhp:hp,scale,dead:false,hurt:0,phase:rand(0,6),isBoss,onUpdate}; enemies.push(e); return e; }
function spawnSpider(x,z,scale=1,hp=1200){ const s=buildSpider(scale); s.position.set(x,0,z); return addEnemy(s,{hp,scale}); }
for(let i=0;i<6;i++){ const a=rand(0,6.28),r=rand(6,13); spawnSpider(Math.cos(a)*r, Math.sin(a)*r, rand(.8,1.3)); }

// ---- hero
const hero={pos:V3(),vel:V3(),face:0,target:null,moveTo:null,hp:15932,maxhp:16800,mp:1275,maxmp:1600,attackCd:0,swing:0,moving:false};
let KILLS=247;

// ---- integration API + hooks (loot/boss/screens plug in here; no main.js edits needed by them)
const hooks={ kill:[], frame:[], hit:[] };
const KARL={ THREE, scene, camera, hero, enemies, vfx, env, spawnSpider, addEnemy, makeBlob, V3,
  onKill:cb=>hooks.kill.push(cb), onFrame:cb=>hooks.frame.push(cb), onHit:cb=>hooks.hit.push(cb),
  get kills(){return KILLS;}, isAuto:AUTO };
window.__KARL=KARL;

// ---- input
const raycaster=new THREE.Raycaster(), mouse=new THREE.Vector2(), keys={};
addEventListener('keydown',e=>keys[e.key.toLowerCase()]=true);
addEventListener('keyup',e=>keys[e.key.toLowerCase()]=false);
renderer.domElement.addEventListener('pointerdown',e=>{ mouse.x=(e.clientX/innerWidth)*2-1; mouse.y=-(e.clientY/innerHeight)*2+1; raycaster.setFromCamera(mouse,camera);
  for(const en of enemies){ if(en.dead) continue; if(raycaster.intersectObject(en.obj,true).length){ hero.target=en; return; } }
  const hitG=raycaster.intersectObject(scene.children.find(o=>o.geometry&&o.geometry.type==='PlaneGeometry')||scene, true);
  if(hitG.length){ hero.target=null; hero.moveTo=hitG[0].point.clone(); } });

// ---- loop
let last=performance.now(), fpsAcc=0, fpsN=0, fps=60, autoT=0;
function frame(now){
  const dt=Math.min(.05,(now-last)/1000); last=now; fpsAcc+=1/dt; fpsN++; if(fpsN>=20){ fps=fpsAcc/fpsN; fpsAcc=0; fpsN=0; }

  if(AUTO){ autoT+=dt; const live=enemies.filter(e=>!e.dead);
    if(live.length){ let best=null,bd=1e9; for(const e of live){ const d=e.obj.position.distanceTo(hero.pos); if(d<bd){bd=d;best=e;} }
      hero.target=best; hero.moveTo = bd>2.4 ? best.obj.position.clone() : null; }
    else hero.moveTo=V3(Math.sin(autoT*.5)*4,0,Math.cos(autoT*.5)*4); }

  // movement
  let mv=V3(); if(keys['w'])mv.z-=1; if(keys['s'])mv.z+=1; if(keys['a'])mv.x-=1; if(keys['d'])mv.x+=1;
  if(mv.lengthSq()>0){ mv.normalize(); const rmx=mv.x*Math.cos(-Math.PI/4)-mv.z*Math.sin(-Math.PI/4), rmz=mv.x*Math.sin(-Math.PI/4)+mv.z*Math.cos(-Math.PI/4);
    hero.pos.x+=rmx*8*dt; hero.pos.z+=rmz*8*dt; hero.face=Math.atan2(rmx,rmz); hero.moving=true; hero.moveTo=null; }
  else if(hero.moveTo){ const d=hero.moveTo.clone().sub(hero.pos); d.y=0; const dist=d.length();
    if(dist>.15){ d.normalize(); hero.pos.addScaledVector(d, Math.min(8*dt,dist)); hero.face=Math.atan2(d.x,d.z); hero.moving=true; } else { hero.moving=false; hero.moveTo=null; } }
  else hero.moving=false;

  // attack
  hero.attackCd-=dt;
  if(hero.target && !hero.target.dead){ const d=hero.target.obj.position.distanceTo(hero.pos);
    if(d<2.6){ hero.moving=false; hero.face=Math.atan2(hero.target.obj.position.x-hero.pos.x, hero.target.obj.position.z-hero.pos.z);
      if(hero.attackCd<=0){ hero.attackCd=.55; hero.swing=1; const crit=Math.random()<.387, type=Math.random()<.4?'aether':'phys';
        const dmg=crit?(30000+Math.random()*20000|0):(11000+Math.random()*9000|0);
        hero.target.hp-=dmg; hero.target.hurt=.25; vfx.damageNumber(hero.target.obj.position, dmg, crit?'crit':type, crit);
        vfx.spawnHitSpark(hero.target.obj.position); vfx.addShake(crit?.35:.15);
        for(const cb of hooks.hit) cb(hero.target, dmg, crit);
        if(hero.target.hp<=0){ killEnemy(hero.target); hero.target=null; } } } }
  hero.swing=Math.max(0,hero.swing-dt*2.7);

  // carl transform + anim
  carl.position.copy(hero.pos); carl.rotation.y=lerp(carl.rotation.y,hero.face,.25); carlBlob.position.set(hero.pos.x,.02,hero.pos.z);
  const t=now/1000, {armPivotR,armPivotL,legL,legR,torso}=carl.userData;
  if(hero.moving){ const gg=Math.sin(t*11)*.6; legL.rotation.x=gg; legR.rotation.x=-gg; armPivotL.rotation.x=-gg*.7; if(hero.swing<.05)armPivotR.rotation.x=gg*.7; vfx.spawnDust(hero.pos); }
  else { torso.position.y=1.5+Math.sin(t*2)*.05; legL.rotation.x*=.8; legR.rotation.x*=.8; armPivotL.rotation.x*=.8; }
  // weighty overhead chop: brief anticipation (arm cocked high), quadratic snap-down, follow-through
  if(hero.swing>.02){ const ph=1-hero.swing, e=ph*ph; armPivotR.rotation.x=-2.0+2.6*e; armPivotR.rotation.z=Math.sin(ph*Math.PI)*.5;
    armPivotL.rotation.x=-.35*e; torso.rotation.y=-.4*Math.sin(ph*Math.PI); }
  else { armPivotR.rotation.z*=.8; torso.rotation.y*=.8; }

  // donut follows — kept on Carl's camera-near side (+X/+Z) with a gentle weave so she's ALWAYS
  // clearly visible padding beside him and never hidden behind Carl or the boss; keeps pace closer.
  const dtar=hero.pos.clone().add(V3(1.2+Math.sin(t*.8)*.55,0,1.55+Math.cos(t*.8)*.55)); donut.position.lerp(dtar,.06);
  donut.rotation.y=lerp(donut.rotation.y, Math.atan2(hero.pos.x-donut.position.x,hero.pos.z-donut.position.z)-Math.PI/2,.1);
  donutBlob.position.set(donut.position.x,.02,donut.position.z);

  // enemies
  for(const e of enemies){ if(e.dead){ e.obj.position.y-=dt*2; e.obj.scale.multiplyScalar(1-dt*2); e.blob.material.opacity*=(1-dt*2);
      if(e.obj.scale.x<.05){ scene.remove(e.obj); scene.remove(e.blob);} continue; }
    const d=hero.pos.clone().sub(e.obj.position); d.y=0; const dist=d.length();
    if(dist>2.2){ d.normalize(); e.obj.position.addScaledVector(d,2.4*dt); }
    e.obj.rotation.y=lerp(e.obj.rotation.y, Math.atan2(d.x,d.z)-Math.PI/2,.1);
    e.phase+=dt*8;
    if(e.obj.userData.legs) e.obj.userData.legs.forEach((l,i)=>l.rotation.x=(.6+Math.sin(e.phase+i)*.4)*(i<3?1:-1));
    e.blob.position.set(e.obj.position.x,.02,e.obj.position.z);
    e.hurt=Math.max(0,e.hurt-dt); if(e.obj.userData.mat) e.obj.userData.mat.emissiveIntensity=.7+e.hurt*4;
    if(e.onUpdate) e.onUpdate(e,dt,hero); }

  env.update(dt); vfx.update(dt);
  for(const cb of hooks.frame) cb(dt, now/1000);

  // camera follow + shake — when a boss is on the field, smoothly pull BACK+UP and raise the aim
  // so the whole towering Juicer (head→feet) and Carl are framed (reference boss shot); return to
  // the tight hero framing once it's gone. Same fixed iso angle throughout (no free orbit).
  const bossE=enemies.find(e=>e.isBoss&&!e.dead);
  bossW=lerp(bossW, bossE?1:0, .04);
  const camOff=CAM_OFF.clone().lerp(CAM_OFF_BOSS,bossW);
  let followPt=hero.pos; if(bossE) followPt=hero.pos.clone().lerp(bossE.obj.position,.30*bossW); // center the Carl↔boss composition
  camTarget.lerp(followPt,.08); camPos.lerp(camTarget.clone().add(camOff),.1);
  const sh=vfx.consumeShake(dt); camera.position.copy(camPos).add(V3(rand(-1,1)*sh,rand(-1,1)*sh,rand(-1,1)*sh));
  camera.lookAt(camTarget.x, camTarget.y+2.5+4.0*bossW, camTarget.z); // raise aim so the boss's head clears the top while Carl stays in-frame

  // hud
  hero.mp=Math.min(hero.maxmp, hero.mp+dt*24); hud.update(hero); hud.setKills(KILLS);
  window.__gameState={fps:Math.round(fps), enemies:enemies.filter(e=>!e.dead).length, kills:KILLS, hp:Math.round(hero.hp), ready:true};

  env.render(camera); requestAnimationFrame(frame);
}
function killEnemy(e){ e.dead=true; KILLS++; vfx.addShake(e.isBoss?.6:.3); vfx.killBurst(e.obj.position);
  for(const cb of hooks.kill) cb(e);
  if(!e.isBoss) setTimeout(()=>{ const a=rand(0,6.28),r=rand(8,14); spawnSpider(Math.cos(a)*r+hero.pos.x, Math.sin(a)*r+hero.pos.z, rand(.8,1.3)); },1200); }

addEventListener('resize',()=>{ camera.aspect=innerWidth/innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth,innerHeight); });
document.getElementById('loading').style.display='none'; window.__READY=true;

// Auto-load optional plug-in modules if present; each exports init(api). Missing = silently skipped.
for(const m of ['loot','boss','screens','abilities','floors','lootbox']){ import(`./${m}.js`).then(mod=>mod.init&&mod.init(KARL)).catch(()=>{}); }

requestAnimationFrame(frame);
