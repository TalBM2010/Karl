# Cohesion pass — hero prominence + whole-game coherence

Goal: fix the critic's #1 gap (HERO PROMINENCE / mid-swing "abstract white wedge") and
cohere the three parallel builds (world/lighting, characters, combat-VFX) at the Diablo-IV
bar without regressing any win. Edits limited to `src/main.js` and `src/actors.js`.
`env.js`/`vfx.js` untouched. Every capture booted with `"errors": []`.

## The #1 gap — HERO PROMINENCE

### (a) Camera framing — src/main.js
- `CAM_OFF` pulled in from `V3(15,20,15)` (dist ~29) to `V3(11.5,15.5,11.5)` (dist ~23.3),
  keeping the same fixed ~44° pitched iso angle (not a free-orbit cam). Carl now occupies
  roughly one-sixth of the frame height instead of ~1/12.
- `camera.lookAt` aim height raised from `camTarget.y+1` to `camTarget.y+2.5` (aim above
  Carl's head), so he sits in the lower-middle third with generous ground/sightlines ahead —
  the Diablo-IV reference framing. FOV kept at 38.

### (b) Carl — src/actors.js
- **Killed the white wedge.** The attack-swing frames used to collapse into a flat white
  triangle: the axe "bits" were huge 3-sided cones (`CylinderGeometry(.66,.14,.13,3)`, ~1.5u
  wide) in near-white cyan at `emissiveIntensity 3.0` + a `3.6` near-white core, which bloom
  blew out to a solid white face whenever the swing turned them toward camera. Rebuilt the
  axe head: compact 4-seg cones (`ConeGeometry(.30,.56,4)`, diamond edge, thinned front-to-back
  `scale z .55`), saturated cyan `0x5fc2ff` / emissive `0x2a8fff` at `1.8`, core dropped to
  `0.16` radius at `2.3`. It now reads as an axe head and blooms to a cyan halo, never a white
  blob — verified clear in every swing frame.
- Scale nudged `1.1 → 1.22` for heroic presence and to sit clearly above the arachnids.
- Boxer white toned `0xf4f4f2 → 0xe9e6dd` (warm off-white, roughness .85) so the shorts don't
  bloom into a solid white blob; the red heart print now reads at game distance.

### Attack weight/readability — src/main.js
- Swing decay slowed `dt*3.2 → dt*2.7` for a heavier beat.
- Pose reshaped from a linear arc into an anticipation → quadratic snap-down → follow-through
  overhead chop (`rot.x = -2.0 + 2.6*ph²`), with a cross-body `rot.z` arc, a supporting
  left-arm counter, and a slight torso twist (`torso.rotation.y`) into the blow — the glowing
  axe now visibly arcs and the hit lands with weight.

## Whole-game cohesion
- **Scale harmony:** Carl (scale 1.22, ~2.85u) now clearly dwarfs the crystal arachnids and
  reads right against the crystal formations.
- **Color cohesion:** the saturated (not white) axe and Donut's warm gold crown now bloom as
  colored halos inside the teal/indigo grade instead of blowing out or looking pasted-on;
  Carl's warm skin catches the scene's warm rim naturally.
- **Donut visibility:** scaled `1.15` so she reads as a crowned cat companion beside Carl
  (her orbit-follow in main.js unchanged), consistently visible with her crown glow.
- **Ground contact:** the existing shadow blobs sit correctly under Carl/Donut/spiders at the
  tighter framing.

## Wins preserved (unchanged files)
- env.js: crystal cavern, cool teal/indigo fog + grade, bloom, dust motes, lighting — intact.
- vfx.js: floating damage numbers, crystal-shatter kill bursts, crit rings, impact sparks,
  dust, camera shake — intact.
- Contracts intact: `initEnvironment`→`{crystals,update,render}`, `env.render(camera)` render
  path, Carl userData `{armPivotR,armPivotL,legL,legR,axe,torso,head}`, spider `{legs,mat}`,
  `createVfx` API, the pickable PlaneGeometry click-to-move ground. HUD/tools/overlay untouched.

Captures: `captures/cohesion/` (4 stills + 14-frame motion strip), `"errors": []`.
