# Whole-game cohesion pass — Wave 8 reconciliation (cohesion3)

Files touched (in place, contracts preserved):
- `godot/scripts/modules/combat.gd` — floating damage-number anti-overlap (the priority fix).
- `godot/scripts/modules/enemies.gd` — arachnid core/eye emission dial-back (saturation).
- **Not** touched: `world.gd`, `screens.gd`, `floors.gd`, `hud.gd`, `loot.gd`, `player.gd`, `game.gd`.

Captures this pass:
- Baseline composite (pre-fix): `captures/gd/coh8/`
- Baseline gameplay-only, lab (pre-fix): `captures/gd/coh8lab/`
- **After** gameplay-only, lab: `captures/gd/coh8lab2/`
- **After** full composite, repo: `captures/gd/coh8final/`

All runs printed `CAPTURE_OK` with no `SCRIPT ERROR` / `Parse Error` (scene renders whole).

---

## PRIORITY 1 — Damage numbers overlapping/colliding (FIXED)

### Root cause
The float-text layout separated consecutive pops by cycling `_text_seq % 4` "slots" pushed along
the camera-right axis by `unit * 1.75`, where `unit = 128 * pixel_size * dist` is one label
line-height in world units. That spacing is ~one line-height in **screen** terms (~80–90px), but a
7-digit number like `294,890` is **~250px wide**. On the boss cam every blow lands on the boss at
screen-centre, so two numbers spawned within a life (`TEXT_LIFE 1.15s`, `MAX_TEXT 3`) piled onto
the same point, and the horizontal nudge was far smaller than the glyph run — a white
`78,433 PHYSICAL` and an orange `294,890 CRITICAL!` rendered **stacked and unreadable**. The
vertical component (`unit * 1.15 * (slot % 2)`) only offered two levels at ~half a line-height, so
it couldn't rescue the row either.

### The fix (combat.gd `spawn_damage` layout + velocity)
Replaced horizontal "slots" with a guaranteed **vertical lane** system:
- Added `const PS_MAX := 0.00039` (the crit pixel_size — the biggest number). Lane pitch is sized
  off `lane_h = 128 * PS_MAX * dist`, i.e. a full **crit** line-height in world units, so a lane
  always clears whatever number sits in it regardless of its digit width.
- Each new number **claims the lowest vertical lane not currently held by a live number** (scanned
  from `_texts`). Because we retire the oldest before exceeding `MAX_TEXT`, `MAX_TEXT` lanes always
  suffice, so two numbers can **never share a row** whatever their width.
- Vertical placement: `2.1 + lane * 2.55 * lane_h` (+ tiny jitter). A gentle per-lane horizontal
  fan (`0, +, -` × `0.85 * lane_h`) keeps the column from reading as rigid while staying centred on
  the target so numbers still read as "its" hit.
- Lowered the rise velocity (`crit 2.30 → 1.55`, `phys 2.00 → 1.35`) and horizontal drift
  (`±0.7/±0.5 → ±0.35/±0.25`). The old fast rise let a fresh high-lane number sink into an older
  low-lane one before the lane freed; the gentler rise stays well under the 2.55-line lane pitch
  over a full life, so lanes remain visually separated the whole time (the boss cam — larger
  `dist`, larger pitch — is the *safest* case, exactly where the bug used to show).

### Verified
`captures/gd/coh8lab2/shot_05.png` — the exact failure scenario: Juicer at screen-centre with an
orange `175,764 CRITICAL!` in an upper lane and a fading white `58,679 PHYSICAL` in a lower lane,
**cleanly separated, both fully readable**. `shot_07.png` holds even with three concurrent numbers
(CRITICAL / BLOCKED laned apart). No stacking in any frame across the run.

---

## PRIORITY 2 — Frame busyness / saturation (dialled back, blacks preserved)

Audited the two Wave-8 emission additions against the crystal field:
- **Floor crack-veins (`world.gd`)** — LEFT AS-IS. The vein emission is
  `EMISSION_OP_MULTIPLY` (modulates albedo, cannot act as a light source), patch-masked to only the
  deepest cracks, energy 1.5. It reads as wet mineral texture, not a light. No change warranted.
- **Arachnid core + eyes (`enemies.gd`)** — DIALLED BACK. Five arachnids each carry an **unshaded**
  violet core at emission energy `2.4`; past the glow threshold that bloomed into five extra violet
  light sources competing with the crystals. Pulled core `2.4 → 1.85` and eyes `2.6 → 2.1`. They
  still glow as a hot menacing heart / eyes, but stop washing the composite past the crystal field.

Result (`coh8lab/shot_00` vs `coh8lab2/shot_00`, same scene): the arachnids now read as menacing
silhouettes with contained cores; deep blacks in the corners/floor are intact; the hero and action
stay readable. The frame is thematically saturated (it *is* "The Crystal Depths") but no longer
tips into blue/purple overload from the enemy glows.

---

## PRIORITY 3 — Impact effects land, no additive white-clip (CONFIRMED)

In the gameplay lab frames the impact VFX all register in stills: dust puffs and sparks at the hit
point, the cyan swing-arc trailing the chop (`coh8lab2/shot_03`), hit flashes on struck enemies,
plus the aether nova (`shot_02`) and whirlwind. None clip to white — the `_claim_big` arbiter keeps
one screen-filling effect at a time, and the additive palette sits just past the white point so
two transients hold their hue rather than summing to a flat blob over ACES+bloom. No change needed.

---

## Whole-game sweep — nothing regressed

- **World crystals / grade** — deep blacks, faceted internal glow, ACES/LUT grade all intact
  (world.gd untouched). 
- **Broadcast HUD** — crisp; orbs, skill bar, boss bar, audience feed, minimap, objectives,
  ticker all present (`coh8final/shot_00`).
- **Boss cam** — Juicer framed head-to-feet with his red telegraph ring at his feet
  (`coh8lab2/shot_05/06/07`); the enemies `boss`/`_boss_phase` contract is untouched, so the
  distance-easing wide shot still fires on telegraph/slam.
- **Carl** — heroic, legible red heart-boxers + glowing cyan axe (`coh8final/shot_03`).
- **Princess Donut** — padding alongside in gameplay frames.
- **Loot** — beams, box, gold labels present (`Gravebite Legendary`, `1,513 Gold`).
- **Menus** — inventory / character sheet render as fully-opaque full-screen menus (opaque scrim +
  guarded occlude), gameplay fully hidden and fully restored on close (`coh8final/shot_03/05`);
  screens.gd untouched.
- **Timing** — floors intro composes over the live HUD in the early window (`coh8final/shot_00`)
  and the screens menus own the later windows without fighting or failing to dismiss.

---

## Before / after frames
- Overlap failure (before): `captures/gd/coh8/shot_00.png` (single, but the collision case is the
  boss-cluster the reviewer flagged) and the pre-fix boss frames in `captures/gd/coh8lab/`.
- Overlap FIXED (after): `captures/gd/coh8lab2/shot_05.png` (crit + physical laned),
  `shot_07.png` (three numbers laned).
- Saturation before/after: `captures/gd/coh8lab/shot_00.png` → `captures/gd/coh8lab2/shot_00.png`.
- Menu intact: `captures/gd/coh8final/shot_03.png`. Floors intro intact:
  `captures/gd/coh8final/shot_00.png`.

## Honest per-piece read (0–10 vs the Diablo-IV bar)
- World / crystal grade: **9** — deep blacks + faceted glow, still the strongest layer.
- Broadcast HUD: **9** — crisp, dense, product-grade.
- Boss framing (Juicer): **8.5** — head-to-feet with telegraph ring; the hulk material reads.
- Carl (hero, boxers, axe): **8.5** — heroic and legible at distance.
- Damage numbers: **8.5** (was ~5 when stacked) — now laned, readable, punchy.
- Enemies (arachnids): **8** — sharper, telegraphed, now correctly contained in light budget.
- Menus (inventory/char/floors): **9** — opaque, clean take-over and restore.
- Impact VFX: **8** — dust/arc/flash land without clipping.
- Composite cohesion: **8.5**.

## Single biggest remaining gap (whole game)
Cross-system label collision in busy boss moments. The damage-number system now self-separates, but
it does **not** coordinate with the *other* floating-text systems — loot pickup labels
(`Gold Loot Box`, `1,513 Gold`) and enemy nameplates (`loot.gd` / `enemies.gd`) can still land on
top of a damage number at screen-centre during a crit (see `coh8lab2/shot_07`). The next pass that
would most move the frame toward Diablo IV is a **shared screen-space text arbiter** that lanes
damage numbers, loot labels and nameplates against each other, not just within their own system.
