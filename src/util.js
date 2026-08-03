// Shared math + THREE helpers used across modules.
import * as THREE from 'three';
export const V3=(x=0,y=0,z=0)=>new THREE.Vector3(x,y,z);
export const clamp=(v,a,b)=>Math.min(b,Math.max(a,v));
export const lerp=(a,b,t)=>a+(b-a)*t;
export const rand=(a,b)=>a+Math.random()*(b-a);
export const AUTO=new URLSearchParams(location.search).has('auto');
// low-poly crystal shard geometry shared by env / actors / vfx
export const crystalGeo=new THREE.ConeGeometry(0.5,2.2,5);
// soft contact-shadow blob under actors
export function makeBlob(size=0.9){
  const m=new THREE.Mesh(new THREE.CircleGeometry(size,20),
    new THREE.MeshBasicMaterial({color:0x000000,transparent:true,opacity:.35,depthWrite:false}));
  m.rotation.x=-Math.PI/2; m.position.y=.02; return m;
}
