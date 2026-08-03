# Cohesion pass 2 — boss-fight camera + whole-game coherence

Fresh senior integration/polish pass. Fixed the #1 named gap (boss-fight camera cropping the
Juicer's head) and smoothed cross-module inconsistencies, with minimal surgical edits. Every
capture booted with `"errors": []`. Edited only `src/main.js`, `src/loot.js`, `src/actors.js`.

## THE #1 GAP — BOSS-FIGHT CAMERA (src/main.js)
Before: the fixed close melee framing (`CAM_OFF`) cropped the ~11u-tall Juicer at mid-chest —
his signature snarling head/traps were entirely off the top of the screen behind the boss bar.

Fix: the camera now smoothly pulls **back + up** and **raises the aim** whenever a boss is on the
field, framing the ENTIRE Juicer (head→feet) plus Carl, then eases back to the tight hero framing
once the boss is gone. The fixed pitched Diablo-IV iso ANGLE is preserved in both modes (no free
orbit):
- Added `CAM_OFF_BOSS = CAM_OFF.clone().multiplyScalar(1.62)` — a **uniform scale** of the melee
  offset, so the iso pitch is byte-for-byte identical; only distance/height change.
- A smoothed weight `bossW` lerps 0→1 (`.04`/frame) on `enemies.find(e=>e.isBoss&&!e.dead)`, driving
  `camera` between `CAM_OFF` and `CAM_OFF_BOSS`, and the lookAt height between `+2.5` and `+6.5`
  (`2.5+4.0*bossW`) so the boss's head clears the top while Carl stays in-frame.
- While a boss is live the follow target is nudged 30% toward the boss (`hero.pos.lerp(boss.pos,
  .30*bossW)`) so the Carl↔Juicer composition centers like reference Frame A.
- Verified in motion: whole Juicer (head, glowing eyes, traps, jug, legs, feet) framed with Carl
  small below; head clears the boss bar with margin. Normal play returns to the tight hero framing
  (Carl prominent, lower-middle third) — unchanged behavior when `bossW==0`.

## Whole-game cohesion (minimal edits)
- **Princess Donut visibility (main.js + actors.js).** She was present but a dim brown blob that
  sometimes orbited to Carl's far/occluded side. Her full-circle orbit is now confined to Carl's
  camera-near side (`+X/+Z`, gentle weave) and follows a touch closer (`lerp .04→.06`), so she's
  ALWAYS clearly padding beside him and never hidden behind Carl or the boss. Her crown PointLight
  was brightened (`2.6→3.4` intensity, `4.5→6.0` range) so she reads as a glowing crowned companion
  against the dark floor. Confirmed clearly visible front-left of Carl in normal play and the boss
  fight.
- **Loot labels vs HUD (loot.js).** Added a `clampLabel()` guard on the ground-drop and loot-box DOM
  labels so a name/type label can never sit under the left audience feed, the right minimap/objectives/
  analysis panels, the top bars, or the bottom dock — it rides the safe-area edge instead. Labels near
  center (the common case, e.g. "Aether Shard / Common Gem") are untouched. The collect streak to the
  loot orb is intentionally left flying to bottom-center.

## Wins preserved (all intact, verified in captures)
- **World/env:** crystal-cavern, teal/indigo fog + grade, bloom, dust motes, lighting — untouched
  (env.js not edited). Boss/spiders/crystals/loot beams read consistently under the grade, nothing
  blown out.
- **Combat/VFX:** floating damage numbers, crystal-shatter kills, crit rings, sparks, dust, shake —
  untouched (vfx.js not edited). Carl's overhead-chop swing + cyan axe arc intact.
- **Boss:** the Juicer, boss bar (`#bossbar` populated + live HP%), red slam telegraph ring +
  shockwave, enrage path — untouched (boss.js not edited), now fully framed.
- **Loot:** rarity beams, item meshes, gold piles, System loot boxes, auto-collect — intact.
- **Screens:** CHARACTER (C) and INVENTORY (I) both open, complete and legible — untouched
  (screens.js not edited).
- **HUD:** broadcast frame, orbs, skill dock, boss bar — untouched (index.html/hud.js not edited).
- **Contracts:** `env.render(camera)` render path, `window.__KARL` API + hooks (onKill/onHit/onFrame),
  `addEnemy`/`spawnSpider`, click-to-move PlaneGeometry ground, Carl/spider userData, `createVfx`,
  `initEnvironment→{crystals,update,render}`, screens c/i/Esc, boss-driven `#bossbar` — all honored.

## Captures (all `"errors": []`)
- `captures/cohesion2c/` — full boss run (6 shots + 14-frame strip): whole Juicer framed head→feet.
- `captures/cohesion2_norm2/` — pre-boss normal play: tight Carl framing + glowing Donut companion.
- `captures/cohesion2_char/`, `captures/cohesion2_inv/` — screens open, intact.
