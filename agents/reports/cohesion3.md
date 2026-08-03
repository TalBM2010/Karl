# Cohesion pass 3 — smoothing Wave-3 abilities + model-fidelity into the whole

Fresh whole-game polish pass over the two Wave-3 additions (the `abilities.js` skill VFX
system and the `actors.js`/`boss.js` model-fidelity work). Minimal surgical edits — **only
`src/abilities.js` was touched** (8 insertions / 5 deletions). Every capture booted with
`"errors": []`. No other module edited; all Wave-1/2 wins preserved.

## Issue 1 — SKILL-BAR READABILITY (the real bug, fixed)
Root cause found by cropping the live `#slots` bar and dumping per-slot computed styles: the
injected cooling wedge was `conic-gradient(rgba(2,7,12,.9) …)` — a **90%-opaque black** wedge
covering the whole 52px slot. A freshly-triggered cooldown (`--a≈360°`) therefore painted the
slot almost solid black, erasing the `.ic` icon underneath — captured proof: the "0.7" R-Click
slot and strip frames showed cooling slots as black holes while the other 8 icons stayed bright.

Fix (in the injected `<style>`):
- Cooling wedge dropped to **`rgba(4,10,16,.55)`** (semi-transparent) so the dimmed skill icon
  stays clearly visible *under* the sweep — the Diablo-IV read (icon + dark wipe + number, never
  an empty slot). The recharged sector keeps its faint cyan tint.
- Added `#slots .slot.cooling .ic{ filter:brightness(.9) saturate(.92) }` so a cooling icon reads
  as *dimmed-but-present*, not erased.
- Strengthened the `.cdnum` timer's shadow so it stays legible over the now-lighter wedge.
- Verified by forcing the **worst case** (5 slots cooling simultaneously with near-full wedges):
  the purple "5", cyan "4", gold "2", red "1" icons and colors all read through the sweep with
  legible timers — vs. black holes before. The sweep + border-glow + number still clearly signal
  "cooling".

## Issue 2 — ABILITY VFX vs HERO (tuned so Carl stays readable)
Across all boss-fight and swing frames Carl already read through his aura / war-cry rune /
whirlwind. The one stack-to-white risk was the **CLEAVE crescent** firing right on top of him
(cyan .95 **plus** pale-white .9, additive). Trimmed to cyan `.85` + pale `.55` (both the spawn
opacities and the per-frame fade) so the crescent stays **cyan-cored** rather than a white bloom
that swallows Carl — like Frame B where Carl is still clearly visible amid the energy. Aura rings
(cyan .30 / aether .26) and glow (.14) were already balanced and left untouched.

## Issue 3 — HARMONY (verified, no edit needed)
Under the existing bloom/grade the palette sits together well: the abilities' cyan and
aether-purple, the Juicer's glowing red veins + amber eyes, the purple/cyan gem crystals, and the
rarity loot beams all read as one scene. Aether damage numbers stay legibly purple; the cyan axe
arc reads cyan (not white); nothing is blown to pure white and nothing is muddy. The cleave trim
above also helps keep the brightest additive stack off the white ceiling.

## Wins preserved (all intact, confirmed in captures)
- **World/grade/bloom** (env.js — untouched): crystal cavern, teal/indigo fog, motes, lighting.
- **Combat VFX** (vfx.js — untouched): floating damage numbers (incl. big orange "497,734
  Critical!"), aether/physical types, crystal-shatter kills, sparks, shake — all firing.
- **Boss** (boss.js — untouched): the veiny Juicer, `#bossbar` name/subtitle/level-78 diamond/HP%
  /affix pips, red slam telegraph + shockwave, glowing eyes + Mutant Whey jug — logic & look intact.
- **Models** (actors.js — untouched): defined heroic Carl (cyan axe swing arc), gem arachnids,
  glowing crowned Donut in Specimen Vitals.
- **Loot** (loot.js — untouched): rarity beams + ground labels + gold piles + boxes.
- **Screens** (screens.js) + **HUD** (index.html) — untouched; broadcast frame, orbs, buff pips,
  ticker, minimap, objectives, combat analysis all present.
- **Boss-fight camera** frames the whole Juicer head→feet with Carl below (cohesion2 win intact).
- **Contracts** honored: abilities auto-load via `init(api)`, `window.__KARL` API/hooks, slot DOM
  structure untouched (only the injected style + owned `.cdnum` behavior changed), `#slots` order,
  all userData/vfx/env contracts.

## Captures (all `"errors": []`, fps 22–24, software GL)
- `captures/cohesion3/` — baseline (pre-fix): black cooling-slot holes visible.
- `captures/slots_worst/` — forced 5-slot cooldown: icons now readable through the sweep.
- `captures/cohesion3b/` — post-fix full run: Carl readable through a cyan-cored cleave + aura,
  harmonized palette, boss/loot/HUD/world all intact.
