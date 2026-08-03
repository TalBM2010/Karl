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

## Update — bulked into a heroic barbarian (round 2)
The first pass read as a scrawny mannequin. Kept the rig + skeletal animation and made him
**BUILT**, editing only `buildCarl` in `src/actors.js`:

1. **Broader frame via bone-scaling** the skinned rig itself: Spine2 ×1.16 (broad chest +
   pushes shoulders wide), both Arms ×1.16 (beefy upper arms), both UpLegs ×1.2 (thick
   thighs). Scales kept **uniform** per bone (non-uniform scale shears rotated child bones)
   with **counter-scales** on Neck (÷1.16), Hands (÷1.16²) and Feet (÷1.2) so head/hands/feet
   stay proportioned and the axe grip keeps its size. Done BEFORE the height-fit so he stays
   ~2.4u.
2. **Muscle suit** (`buildMuscleSuit`) — sculpted volume parented to bones so it deforms with
   the animation: broad traps + wide deltoid caps (own the V-taper width) + slabby pecs on
   Spine2, a cut six-pack + linea-alba/tendon grooves + obliques on Spine, bicep/tricep on the
   Arms, forearm bellies, quad sweeps on the thighs, gastroc on the calves, a thicker neck.
   Lit "crown" skin on the bellies + thin dark "groove" skin in the separations = reads cut.
3. **Real bearded face** on the Head bone: heavy brow, cheekbones, squared jaw, nose, deep-set
   eyes, a FULL dark beard (jaw wrap + under-chin mass + sideburns + mustache) and swept-back
   hair — reads clearly at range.
4. **Warmer skin**: colour pushed warm (`0xe0975a`) with a touch of warm emissive so he reads
   as tan flesh, not cold/blue under the teal IBL.
5. **Axe de-bloomed**: blade/core/pommel emissive and the PointLight intensity dropped (glow
   1.9, blade emissive .85) so it glows cyan and the blade SHAPE stays legible instead of
   blowing out to a white flare.

Accessory holders were generalised to compute each bone's own (post-scaling) world scale
**per-axis**, so shorts/hair/axe/muscle all stay correctly sized after bulking. Re-verified in
`captures/carltest` (idle_full/run_a/run_b/atk_a-c) and in-game (`captures/gltfcarl`): no
shearing, smooth idle/run/chop, heart boxers + cyan axe legible.

## Verdict
Carl now **loads and animates cleanly as a muscular, bearded, heroic barbarian** — broad
V-taper torso, big arms/thighs, six-pack, full beard, warm tan skin, gripping a legible cyan
double-bit axe that swings with the skeletal idle/run + additive overhead chop. Clearly reads
as heavyweight and heroic both in isolation and at game scale beside the boss. Game runs with
`"errors":[]`, ~24fps under headless software GL (skinned mesh + muscle suit + boss); fine on
real GPU. `main.js` animation wiring untouched.
