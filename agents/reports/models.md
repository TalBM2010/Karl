# Model-fidelity pass — Carl, the Juicer, crystalline arachnids

Owned files edited: **`src/actors.js`** (buildCarl, buildDonut, buildSpider) and **`src/boss.js`**
(Juicer model geometry/materials only). No encounter logic, HUD/#bossbar wiring, telegraphs,
phases, `api.addEnemy`, hp, or `isBoss` touched. No other files modified. Judged against rubric
§4/§6 and the reference frames.

## Core technique
The old sculpts read as soft balloons for two fixable reasons: (1) "definition" pieces (abs,
knees, lats) used a *darker* skin on the muscle **bellies** — backwards, so muscles looked
bruised/soft instead of lit; (2) every surface shared one flat roughness with no micro-relief.
Both are now inverted/fixed:

- **Inverted muscle/groove shading.** Muscle bellies are lit skin crowns (`skinLt`); the
  *separations* are thin dark `skinDk` "groove" boxes that fake AO shadow lines (sternum,
  linea alba, tendinous ab lines, under-pec fold, quad split, bicep/tricep split, neck-trap
  valley). This is what makes pecs/abs/delts/quads read as *cut* muscle groups.
- **Procedural detail maps (generated in-code, no assets).** A shared grayscale `bumpMap`
  (pores + fibre striations) makes the directional key/rim lights pick out skin relief. Shared
  module-level so the 6+ spawned spiders and Carl all reuse one canvas.

## CARL (buildCarl) — heroic barbarian, less inflated
- Leaner V-taper chest; distinct deltoid caps, two angled pecs with a sternum groove + under-pec
  cut; a real **six-pack** (lit ab bumps cut by a linea-alba + two tendon grooves); serratus
  steps; lat taper. Legs got a rectus-femoris sweep + VMO teardrop split by a groove, a calf
  diamond and shin; arms got a split bicep-peak/tricep with a groove, forearm brachioradialis and
  gnarled knuckles.
- **Face** rebuilt for a tiny-but-readable structure: heavy angled brow ridge (the strongest read
  at distance), cheekbones, squared jaw, a nose cone, deep-set eyes, swept-back hair, a fuller
  shaped beard + sideburns + mustache.
- Boxers slimmed (less "diaper") with a subtle waistband band; **10 red heart clusters** kept and
  still legible; barefoot with toe shaping; leather-wrapped haft rings on the glowing double-bit
  cyan axe (unchanged blade/core/PointLight so the swing arc reads exactly as before).
- Height/scale unchanged: torso rest y=1.5, head ~2.15, hips ~0.98, shoulders ~1.82, `g.scale 1.22`.

## THE JUICER (boss.js model) — veiny detailed hulk, not a balloon
- New **flesh detail maps**: a blotchy `bumpMap` for clammy steroid skin, and a branching-vein
  **emissiveMap** so engorged veins glow subsurface-red through the skin. Because it's the emissive
  channel, the existing hit-flash and enrage `emissiveIntensity` ramps now make the **veins pulse
  brighter on damage** — a free upgrade that respects the flash/enrage code untouched.
- Added `skinLt` pumped-muscle crown material (added to `skinMats` so enrage/flash still tint it),
  separated muscle groups with groove crevices (pec sternum, ab lines, quad split, arm splits),
  lit crowns on pecs/traps/quads/biceps/forearms, more bulging two-segment surface veins across
  chest/arms/legs, gnarled knuckles.
- **Nastier face**: heavy square lantern jaw, jutting cheekbones, deeper scowl brow + furrowed
  glabella, busted flat nose, clenched teeth **plus protruding lower fangs**.
- Mutant Whey jug + back/trap/shoulder syringes, forward hunch, tiny loomed head, transform origin,
  ground alignment, `BOSS_SCALE 2.45`, and `BOSS_HP 53,000,000` all unchanged.

## CRYSTALLINE ARACHNIDS (buildSpider) — sharper, gem-like, meaner
- More gem-like material (roughness .08, metalness .45, flat-shaded facets) with a bright
  **emissive inner core** (Icosahedron) bleeding through the semi-transparent shell — reads as a
  lit crystal, not a rock. Taller/sharper back shards (now 4), longer sharper fangs + pedipalp
  spikes, a 5-eye predatory cluster, and knee-bent two-facet legs for a meaner silhouette.
- `userData = {legs, mat}` preserved exactly — main.js still wiggles `legs` and flashes
  `mat.emissiveIntensity` on hit (the body material is `mat`).

## Contract verification (all intact)
- Carl `userData = {armPivotR, armPivotL, legL, legR, axe, torso, head}` — same names/pivot
  semantics (legs pivot at hips, arms at shoulders, axe child of armPivotR, torso is the bobbed
  group). Walk cycle, idle bob, and overhead-chop with cyan arc all confirmed in captures.
- Spider `userData = {legs, mat}` preserved; Donut still the crowned cat on Carl's camera-near side.
- Juicer `root.userData = {tG, armL, armR, jug, head, rageLight}`, `buildArm`→`{pivot, elbow, fist}`,
  `api.addEnemy(...isBoss:true...)`, telegraph/slam state machine (windup→slam→recover), boss bar,
  and enrage/flash material logic all unchanged — the slam and breathing animations verified in the
  strip frames.

## Captures / performance
`node tools/capture.mjs --out captures/buildH --shots 6 --gap 1200 --strip 12 --stripgap 170` →
**`"errors": []`**, ~22 fps (identical to the pre-existing software-GL floor documented in
actors.md/boss.md — the new detail maps are perf-neutral: one shared bump canvas + one shared
Juicer flesh canvas, no new lights, no per-spider textures). Verified in-scene: Carl reads as a
defined heroic barbarian mid-swing, the Juicer as a veiny detailed hulk with glowing vein network
+ separated muscle + jug/syringes, spiders sharper and gem-like — with the boss bar, affix pips,
level 78, telegraph ring, shockwave, and floating damage numbers all still firing.
