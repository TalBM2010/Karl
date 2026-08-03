# Experiment: Rigged glTF Carl (mixamo Xbot) vs. procedural Carl

## Summary
Replaced the primitive procedural hero with a **real rigged glTF humanoid** (mixamo
`Xbot.glb`) driven by a `THREE.AnimationMixer`, retextured and accessorized into Dungeon
Crawler Carl. He now loads and animates cleanly: warm bare skin, dark swept-back hair +
beard, **white heart-print boxer shorts** (with legible red hearts), bare feet, and the
**glowing double-bit cyan energy axe** gripped in the right hand — the exact axe extracted
from the old procedural Carl (haft + emissive cyan blades + cyan `PointLight`). Locomotion
cross-fades between **idle** and **run** (run when moving); attacks blend a fast additive
right-arm **overhead chop** over the base clip so the held axe swings through an arc. The
game runs with `"errors":[]`, the boss/donut/enemies/HUD are untouched and still work.

## What changed (scope-respecting)
- **`src/actors.js`** — `buildCarl()` fully rewritten. Extracted the axe into a shared
  `buildAxe()` (reused by both the rigged Carl and a fallback). `buildCarl()` returns a
  `THREE.Group` immediately and async-loads `/assets/models/Xbot.glb`; on load it retextures
  every SkinnedMesh to a warm skin `MeshStandardMaterial` (roughness .6), scales the model to
  ~2.4u tall, drops feet to y≈0, and attaches accessories to bones via "holder" groups. It
  exposes `userData.update(dt,state)` and `userData.attack()`. `buildDonut`/`buildSpider`
  untouched.
- **`src/main.js`** — only the Carl transform/animation block replaced: keeps
  `carl.position.copy(hero.pos)` + `rotation.y` lerp, detects the rising edge of `hero.swing`
  to fire `carl.userData.attack()` once per swing, computes `state` (`attack`/`move`/`idle`)
  and calls `carl.userData.update(dt,state)`, and keeps `vfx.spawnDust` on move. Added one
  module-level `carlPrevSwing` edge-detector var. Movement/attack/camera/enemy/donut logic
  untouched.
- **`test/carltest.html`** (new, verification only) — isolated viewer that renders `buildCarl`
  under the same IBL + bloom + tone-mapping as the game, cycling idle/run/attack. Used because
  in the live game the boss framing + floor-intro modals keep Carl tiny/occluded, making
  close-up A/B inspection hard.

## Key technical notes
- **Bone-scale gotcha (the one real bug):** the mixamo rig lives under an `Armature` scaled
  `0.01` (bone space is centimetres) wrapped by the glTF scene node (scale `F≈1.33` after
  height-fit). A bone's true world scale is `F*0.01≈0.0133`, **not** `model.scale` (`1.33`).
  Using `model.scale` made accessories 100× too small (axe = a hand-sized glow blob, shorts/
  hair invisible). Fixed by reading the real world scale off the Hips bone
  (`getWorldScale`) and giving each accessory a "holder" group scaled `1/boneWorldScale`, so
  inside a holder everything is authored in world metres, world-aligned (bind-pose bone axes
  align to world).
- **Attack chop:** no attack clip exists, so after `mixer.update()` the code additively
  `rotateX`es `mixamorigRightArm` (+ ForeArm/Shoulder) on an anticipation→snap-down envelope
  for `CHOP_DUR=0.42s`. Because the mixer resets the clip pose each frame, the rotation is a
  clean per-frame additive swing that self-clears when the timer ends. Verified the axe swings
  overhead → down through the sequence.
- **Robustness:** everything is null-guarded (update/attack are safe before load); a visible
  skin-toned capsule + axe placeholder is shown if the glTF fails, so the game never breaks.
  Skinned meshes get `frustumCulled=false`.

## Verdict
Carl **loads and animates cleanly** — smooth skeletal idle/run + axe-swinging chops, with the
heart boxers and cyan axe clearly legible in isolation and at game scale (`captures/carltest`,
`captures/gltfcarl`). This is a clear visual step up from the procedural primitive Carl in
motion quality and silhouette. Minor: the short beard is subtle at game distance, and skin
reads a touch cool under the dim teal IBL (same lighting the procedural hero used). FPS ~22
under headless software GL (skinned mesh + boss); fine on real GPU.
