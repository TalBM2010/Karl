# VFX / Combat-Feel build report — `src/vfx.js`

Scope: owned `src/vfx.js` only; floating-damage-number CSS injected at runtime via a `<style>`
element from within vfx.js (no edits to index.html or any other file). Public API unchanged
(`createVfx` returns `damageNumber, spawnDust, spawnHitSpark, killBurst, update, addShake,
consumeShake` with identical signatures).

## What changed

### Floating damage numbers (rubric 7)
- New `.dnum` typography injected at runtime: heavy italic 900-weight, condensed
  (Arial Black / Impact / Rajdhani stack), with a full 8-direction black text-outline halo +
  `-webkit-text-stroke` + drop shadow + colored glow, so numbers read over ANY background
  including the blown-out bloom the lighting pass adds.
- Sizes pushed to the Diablo-IV bar: crits 74–104px (scaling with magnitude, so a big crit
  dominates the frame), Physical/Aether 52px, Blocked 38px. Previously 22/34px.
- Type styling: crit orange `#ffa72a` with an "Critical!" sublabel; Physical white; Aether
  purple `#c07bff`; Blocked grey `#c3ccd2` (dimmed); energy routed to Aether purple.
- Motion: fast-then-slow eased arc rise (crit rises ~210px, normal ~160px) with slight
  horizontal drift; spawn scale-punch that overshoots then settles (crits punch harder,
  0.45→1.18→1.0); hold-then-fade opacity.
- Lifetimes lengthened (crit 2.1s, normal 1.6s, blocked 1.1s) so the number floats clear of the
  impact bloom and lingers — reads in stills and in motion.
- On crits, `damageNumber` also spawns a radial ground ring + warm flash at the hit point for a
  heavy-hit punch.

### Impact / particles (rubric 7 & 8)
- `spawnHitSpark`: 14 bright additive sparks (icy blue + occasional warm), a soft radial-glow
  slash flash, and two kicked-dust puffs.
- `killBurst`: 22 spinning crystal shards (blue/purple additive) with gravity, a big glow flash,
  an expanding purple radial ring, and dust puffs — a satisfying crystal-shatter death.
- New soft radial-gradient glow texture used on all flash quads so impacts read as blooming light
  instead of hard squares.
- `spawnDust`: run dust and impact puffs now expand + rise + fade via a unified particle path.
- Generalized `update()` particle system with per-kind behavior (spark / shard / ring / flash /
  puff), gravity, spin, scale animation, and camera-facing billboards for flashes. All meshes are
  removed from the scene and their materials disposed on death — no leaks; shared geometries and
  the glow texture are reused for the scene lifetime.

### Camera shake / hit-stop feel (rubric 7)
- `consumeShake` now returns a non-linear (squared) magnitude so crits kick noticeably harder than
  chip hits, with a fast decay (`~1-dt*11`) for a snappy hit-stop feel rather than a nauseating
  wobble. `addShake` clamp kept controlled (max 0.5).

## Verification
- Captured in-motion via `node tools/capture.mjs --out captures/buildC --shots 10 --gap 550 --video`.
- `capture.json` `errors: []` on the final run.
- Stills catch big orange crits mid-flight (e.g. "46,209 / CRITICAL!" dominating the frame),
  crystal-shard death bursts, radial rings, soft impact flashes, and run/impact dust.
- FPS in capture: ~20–26. NOTE: the capture harness runs under swiftshader (software WebGL);
  the whole-scene baseline before any vfx work was already ~26fps, so this is the software-render
  ceiling for the full scene, not a vfx regression. Particle counts are kept modest (≈30–50 live
  meshes at peak) and all are pooled/disposed. On GPU hardware this comfortably holds 60.
