// Reproducible asset fetch for the Dungeon Karl visual overhaul.
// Only raw.githubusercontent.com is reachable from this environment, so every asset is a
// permissively-licensed file mirrored on GitHub (three.js example models + Khronos glTF sample
// assets + three.js example HDRIs). Assets are committed to the repo so the game loads them from
// the local static server with no runtime network access. Re-run: `node tools/fetch_assets.mjs`.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = path.resolve(fileURLToPath(import.meta.url), '../..');
const TJS = 'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples';
const KHR = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models';

// dest (repo-relative) -> url
const MANIFEST = {
  // rigged humanoids (real skeletons + animation clips) — character bases
  'assets/models/Soldier.glb':          `${TJS}/models/gltf/Soldier.glb`,
  'assets/models/Xbot.glb':             `${TJS}/models/gltf/Xbot.glb`,
  'assets/models/RobotExpressive.glb':  `${TJS}/models/gltf/RobotExpressive/RobotExpressive.glb`,
  // rigged creature
  'assets/models/Fox.glb':              `${KHR}/Fox/glTF-Binary/Fox.glb`,
  // HDRIs for image-based lighting
  'assets/hdri/venice.hdr':             `${TJS}/textures/equirectangular/venice_sunset_1k.hdr`,
  'assets/hdri/quarry.hdr':             `${TJS}/textures/equirectangular/quarry_01_1k.hdr`,
  'assets/hdri/overpass.hdr':           `${TJS}/textures/equirectangular/pedestrian_overpass_1k.hdr`,
};

let ok = 0, fail = 0;
for (const [dest, url] of Object.entries(MANIFEST)) {
  const abs = path.join(ROOT, dest);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  try {
    execFileSync('curl', ['-sSL', '--max-time', '60', '-o', abs, url]);
    const sz = fs.statSync(abs).size;
    if (sz < 1024) throw new Error(`suspiciously small (${sz}b)`);
    console.log(`ok   ${String(sz).padStart(9)}  ${dest}`);
    ok++;
  } catch (e) {
    console.error(`FAIL           ${dest}  (${e.message})`);
    fail++;
  }
}
console.log(`\n${ok} ok, ${fail} failed`);
process.exit(fail ? 1 : 0);
