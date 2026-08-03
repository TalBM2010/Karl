# Boss build report — THE JUICER (floor-boss set-piece)

Owned file: `src/boss.js` (was a stub). No other files touched. Judged vs rubric §14 (boss battle) & §6 (enemies).

## What ships
A grotesque, enormous steroid-swollen humanoid built entirely from THREE primitives, registered as a
targetable enemy via `api.addEnemy` so the hero auto-attacks it and the existing floating damage
numbers fire on it for free. Plugs in through `init(api)` only.

### Model
- ~3.4x Carl's height (`BOSS_SCALE=2.45`), heavy **forward hunch** so his tiny head + huge traps
  loom *over* Carl. Reddish flushed veiny skin (shared material refs so enrage can re-tint them).
- Absurd over-muscled anatomy: barrel chest, huge pecs/traps/lats, massive two-segment arms
  (shoulder + elbow pivots), thick planted legs, painted-on veins (thin cylinders) on arms/chest/legs.
- **Tiny angry face**: heavy brow, glowing furious eyes, snarling open mouth with clenched teeth,
  buzzed hair — juts forward off the hunched neck so it reads from the iso cam.
- Holds a giant **MUTANT WHEY** protein jug (canvas-texture label, toxic-green tub, purple lid,
  handle) raised in the left fist. Five glowing **syringes/vials** (colored cylinders + needles)
  jabbed into traps/shoulders/back. A red rim `PointLight` that intensifies on rage.
- Grounding: the built body is lifted inside an outer group so the feet sit on the floor while the
  obj origin stays at ground level (keeps main.js's hero↔boss distance / 2.2 standoff honest).

### Encounter
- Spawns `hp: 53,000,000`, `isBoss:true`, ahead of the hero (3.5s after load in `isAuto`, 1.2s
  otherwise). main.js lumbers him to a 2.2 standoff; the hero closes and swings — big crits (~30–50k)
  chip him so he stays near full, matching the reference "80%" framing.
- **Slam telegraph state machine** (approach → windup → slam → recover): draws a pulsing **red ground
  hazard ring** (fill + two rings, own meshes) locked at the hero's position, rears the arm overhead,
  then snaps down into an expanding **shockwave ring + hit sparks + weighty `vfx.addShake`**, and
  punishes the hero with a little damage + a damage number if still inside the ring. Slow and heavy.

### Boss bar (drives the existing #bossbar DOM, doesn't recreate it)
- Shows the bar (`display:flex`); sets name "JUICER", subtitle, level 78; every frame updates the HP
  fill width % and `cur / max (pct%)` text from the live enemy record.

### Phases
- Below 40% hp he **ENRAGES**: skin flushes to an angrier red + higher emissive, all four affix pips
  turn red, subtitle flips to "RAGE PUMP — VEINS POPPING", rage particles emit continuously, and
  slam cadence/windup speed up.
- On death: multi-burst `vfx.killBurst` + shockwaves + triple screen-shake, then the boss bar hides.

## Verification
Ran the harness repeatedly (`node tools/capture.mjs --out captures/buildF --shots 6 --gap 1200
--strip 12 --stripgap 170`). All runs report `"errors": []`. Confirmed in captures: the giant Juicer
dwarfing Carl with visible snarling face + jug + syringes, the boss bar populated and its HP%
decrementing live, the red telegraph hazard ring under Carl, expanding shockwave, and huge damage
numbers on the boss. Enrage + death paths were exercised with temporary low-HP runs (reverted):
subtitle change, red affix pips, redder skin, rage motes, death burst, and bar-hide all fire cleanly
with no errors. HP is back to 53,000,000 for shipping.
