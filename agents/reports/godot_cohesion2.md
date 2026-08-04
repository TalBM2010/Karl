# Whole-Game Cohesion Pass 2 — Screens bleed-through regression

Agent: WHOLE-GAME COHESION. Scope: fix the INVENTORY / CHARACTER-SHEET bleed-through
regression found in the first real composite of loot + floors + screens, then sweep the
whole game for collateral damage. Only `godot/scripts/modules/screens.gd` was edited.

## Root cause of the bleed

The screens overlays were never actually opaque — they only *looked* opaque in the
builder's isolated lab because nothing bright sat behind them (the 3D world is deep-black,
so a 0.985-alpha panel over black reads as solid). In the real composite there is a bright
live HUD (layer 10: JUICER bar, audience feed, orbs, skill bar, sector map), world-space
3D loot labels/beams (`loot.root`), and floating damage numbers (`combat.root`) behind the
panel. Three separate leak paths let them through:

1. **Full-screen scrim was only alpha 0.66** (`Color(...,0.66*e)`), and its opacity was
   tied to the panel's eased reveal `e`. The panel body itself was ~0.985 but only spans
   the inner rect — the margins were scrim-only, and even 1.5%/34% of a bright HUD reads
   clearly against near-black.
2. **The panel *content* draws at fixed full alpha/size the instant `a > 0.003`** (item
   cells, text, hero are not alpha-scaled; the "pop" is a sub-pixel scale). But the scrim
   and panel-body *backing* scaled with `a`. So any mid-fade frame — and at the capture's
   effective step rate `anim` frequently lands at ~0.04–0.13 — rendered **crisp content
   floating over a see-through backdrop**. That is exactly what `shot_03`/`shot_05` caught:
   a "half-open" panel with the whole HUD + loot labels + `12,923 BLOCKED` behind it.
3. **No cross-layer suppression** — the live HUD/loot/combat kept rendering full-blast
   under the menu.

A cross-module `CanvasLayer.visible=false` toggle in `_process` (approach I tried first)
is *not* reliable here: the capture's framebuffer grab does not consistently reflect a
sibling-node visibility change made the same tick, so mid-fade frames still bled. The
fix had to be drawn by the screens layer itself.

## What I changed (screens.gd only)

1. **Scrim is now a near-instant, fully-opaque cover.** `alpha = 1.0` (was 0.66) with a
   very steep ramp `sa = clampf(a*50, 0,1)` — fully opaque by `a≈0.02`, the same threshold
   at which content starts drawing. A subtle centre-lift (6 faint concentric circles) keeps
   it reading with depth instead of a flat black slab. Because the scrim sits behind the
   entire panel in screen space, an opaque scrim blocks **every** source (HUD, enemy
   nameplates from `enemies.gd`, boss, crystals, loot, damage numbers) in one move,
   regardless of which module owns them.
2. **Draw gate raised** from `a<=0.003` to `a<=0.02`, so crisp content is *never* laid over
   a not-yet-opaque scrim. Below that the menu simply isn't present.
3. **`_occlude()` added** as belt-and-suspenders for the fully-present state: while a panel
   is up (`max(inv.anim,chr.anim) > 0.04`) it hides `hud.layer` (CanvasLayer), `loot.root`
   and `combat.root` (both Node3D world-FX roots), restoring them on close. Every reach is
   guarded (`game != null`, `"modules" in game`, `mods is Dictionary`, `mods.has(...)`,
   `"layer"/"root" in x`, null checks) so a missing/renamed sibling can never crash screens
   — fault isolation and every public contract preserved. It only toggles on transition.

No Variant-inferred `:=`; all cross-module locals use plain `var x = ...` or typed
`var x: T = ...`. Uses `clampf/minf/maxf`. Nothing touched in loot/floors/hud/combat/game.

## Before / after frames

- Bleed BEFORE (builder's composite): `captures/gd/composite/shot_03.png` (inventory),
  `shot_05.png` (char sheet) — HUD + loot labels + damage numbers straight through.
- Iteration showing the residual mid-fade leak I chased down:
  `captures/gd/coh7/shot_05.png`, `captures/gd/coh7c/shot_05.png`.
- CLEAN AFTER (final, `coh7e`):
  - Inventory: `captures/gd/coh7e/shot_02.png`, `shot_03.png`, `shot_06.png`
  - Character sheet: `captures/gd/coh7e/shot_04.png` (+ strip_02, strip_04)
  - Gameplay + loot composite: `captures/gd/coh7e/shot_05.png`
  - Floors broadcast interruption over live HUD: `captures/gd/coh7e/shot_00.png`, `shot_01.png`
- Pixel proof: menu-frame backdrop samples dropped from readable HUD to near-black
  (boss-region 3/1/2, grid-gaps 6–12, vs the clean fully-open frame's 8/18/27).

## Whole-game read (vs the Diablo-IV bar)

Holds up:
- **Menus (inventory + char sheet):** now genuine clean, near-opaque full-screen pages.
  Dense, letter-spaced small-caps, rarity-bordered cells with star ranks, three stat
  columns, XP bar, currency row. This is the strongest new work — reads D4-grade.
- **Floors intro:** correctly sits ON TOP of the live HUD as a "DUNGEON BROADCAST"
  interruption (not hidden). Left it untouched; no z-fight with screens (both layer 20 but
  floors fires t<5, screens open only t>=5 — never simultaneous).
- **Gameplay + loot:** loot beams / Bronze Loot Box / `7,148 Gold` / `Crystal Render`
  legendary labels *punctuate* rather than clutter; deep blacks, faceted blue crystals,
  whole-boss JUICER framing, readable `12,923 BLOCKED` damage numbers, crisp HUD. No
  additive-over-bloom white clipping — the loot mote bursts (`_spark`, 16 one-shot
  particles per drop) are controlled; assessed, no dial-back needed.

Still weak:
- **The hero render inside the inventory pedestal** is the weakest link — Carl reads as a
  stiff grey mannequin (flat blue-steel body, thin limbs) rather than a heroic muscled
  statue, which undercuts the "hero portrait" moment on an otherwise excellent screen. The
  gameplay hero at camera distance is also small/ambiguous next to Donut.

### Per-piece (0–10)
- Inventory screen: **9** (backdrop now solid; only the Carl figure holds it back)
- Character sheet: **9** (dense, readable, well composed)
- Floors intro: **8.5** (strong broadcast interrupt, composes over HUD)
- Loot in gameplay: **8.5** (punctuates cleanly, good rarity color, no clipping)
- HUD crispness: **8.5**
- World grade (blacks / crystals / boss framing): **8.5**
- Composite cohesion (the deliverable this pass): **9** (was ~5 with the bleed)

### Single biggest remaining gap
The **inventory pedestal Carl** — a mannequin, not a hero. It's the one element that keeps
the best screen in the game from fully clearing the Diablo-IV bar; sculpting a real
muscled, lit heroic statue there (and making the gameplay hero read bigger/clearer beside
Donut) is the highest-value next push.
