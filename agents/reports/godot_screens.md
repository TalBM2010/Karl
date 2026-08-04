# Godot SCREENS — Inventory + Character-Sheet overlays

**File owned:** `godot/scripts/modules/screens.gd` (new, ~1084 lines)
**Reference frames:** `captures/gd/screens_final/` — `inventory_a/b.png`, `charsheet_a/b.png` (1600×1000)
**Rubric section covered:** 13 (Inventory & character sheet), aesthetic per 11.

## What was built

A new module (`extends Node`, `setup(g)`) that builds its **own** `CanvasLayer` (layer 20, above the
HUD's layer 10) and two full-screen dark overlays drawn entirely in code, in the same "Galactic
Observation Protocol" broadcast language as `hud.gd` — dark glass panel, thin cyan bevels, four-corner
filigree, letter-spaced small-caps (`FontVariation.spacing_glyph`), rarity colours reused from the HUD
convention (common grey / magic blue / rare gold / legendary orange / mythic red).

Both screens are one inner `Screen extends Control` class switched by `mode` ("inv"/"char"). Everything
is drawn via `_draw` + `draw_string`/`draw_*` (no per-item Label nodes), scaled uniformly into a
1600×1000 design space via `draw_set_transform`, so item cells and star ranks stay crisp Control
drawing rather than tiny world-space text.

### INVENTORY (Frame C) — `inventory_a/b.png`
- Tab bar **CHARACTER** (active, cyan-filled) / ABILITIES / PARAGON / CODEX; `INVENTORY` title; eyebrow.
- **Carl on a lit rotating crystal pedestal** — a hand-drawn heroic statue: solid blue-steel body with
  a cyan rim light + warm key, broad deltoid shoulders, shaded pecs/abs, **heart-pattern boxers** with
  waistband, bare feet, bearded face, and a **big glowing blue axe** planted at his side. Five crystals
  orbit the feet (depth-sorted front/back, scaling with a rotating `t`) over three cyan-rimmed pedestal
  discs and a floor glow. Class label "PRIMAL WARRIOR · ASCENDED".
- **Equipment paperdoll** — ARMOR column (HEAD/CHEST/GLOVES/LEGS/BOOTS) left of the pedestal, WEAPONS
  column (WEAPON/OFFHAND/AMULET/RING I/RING II) right, each a rarity-bordered slot with a vector icon.
- **Item grid** — 6×5 rarity-bordered cells: coloured border + outer glow, top rarity bar, vector item
  icon (sword/axe/helm/chest/gloves/legs/boots/ring/amulet/gem/shield/wand), quality tag (C/M/R/L/MY),
  and **star-rank pips** (small diamonds) bottom-centre. A few empty slots, deterministically seeded.
- **EQUIPPED STATS** card (right) — 10 rows, colour-coded values.
- **Currency row** — Gold / Platinum / Crystals with glowing coloured coins.

### CHARACTER SHEET (Frame D) — `charsheet_a/b.png`
- Header: **CARL** (huge), `LEVEL 78 · PRIMAL WARRIOR` (gold), `◆ PARAGON TIER 4` (cyan), and an
  animated **EXPERIENCE** bar (81.1%, shine sweep) with exact values + "NEXT LEVEL … TO GO".
- **Core attribute strip** — STRENGTH / DEXTERITY / INTELLIGENCE / WILLPOWER / VITALITY boxes, each with
  a big tabular value + mini fill bar.
- **Three full stat columns** — OFFENSE (gold, sword glyph) / DEFENSE (cyan, shield glyph) / UTILITY
  (blue, star glyph), 8 rows each, values coloured by type (Aether purple, highlight cyan, gold-find gold).
- **Equipment row** — 7 rarity slots (HEAD/CHEST/GLOVES/WEAPON/LEGS/BOOTS/AMULET) with quality tags.
- **Play-time metrics row** — Time Played / Monsters Killed / Bosses Defeated / Areas Discovered.

## Self-drive (capture) demo cycle

No player input. `_process(delta)` accumulates `t` and, after a 5s gate (so `floors.gd`'s 0–5s
floor-intro owns the opening), runs a 9.5s cycle: **INVENTORY** (≈5–8.5s), a **1.5s gameplay beat**,
then the **CHARACTER SHEET** (≈10–13.5s), another gameplay beat, and repeats. Open/close is exponential
decay on `delta` (framerate-independent) with a smoothstep pop; screens set `visible=false` when fully
closed so gameplay reads through. The 1.5s inter-screen gap was tuned specifically so a shot can never
catch the two panels crossfading (an early narrow gap produced a ghost frame; widening it fixed it).

## Best capture paths

Under Xvfb + lavapipe the accumulated render-`t` grows with **total rendered frames**, so the gap
matters more than shot count. A large gap is required to reach the character-sheet window:

```
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
xvfb-run -a -s "-screen 0 1600x1000x24" /opt/godot/godot --path <dir> --resolution 1600x1000 -- \
  --out <dir>/cap --shots 8 --gap 24 --warm 10
```
- `--gap 24 --shots 8` (≈190 frames) reaches `t≈24`, sweeping ~2 full cycles → lands multiple shots on
  **both** screens plus gameplay. `--gap 30 --shots 6` works equally well.
- **Avoid small gaps** (`--gap 6`): the whole capture only reaches `t≈6`, so every overlay shot is the
  first inventory window and the character sheet is never seen.
- In `final3/`: inventory = shot_02/shot_05, character sheet = shot_03/shot_06 (saved as the four
  reference PNGs above).

## What holds up vs Frames C/D
- Both screens read immediately as Diablo-IV menus in the HUD's exact visual language — same panel
  glass, cyan bevels, corner filigree, small-caps, rarity palette. They look like the same game.
- Inventory: rarity-bordered grid with crisp star pips + quality tags, dual equipment columns, the
  Carl-on-lit-pedestal-with-crystals centrepiece, and the currency row all land the Frame C beats.
- Character sheet: the three OFFENSE/DEFENSE/UTILITY columns, core-attribute strip, XP/paragon header,
  equipment row and play-time metrics land the Frame D beats cleanly, no overlap.
- Runs clean: no `SCRIPT ERROR` / `Parse Error` across many capture cycles.

## What's weak / residual
- **Carl portrait** is a stylised 2D vector statue, not a lit 3D SubViewport render. It reads clearly
  (muscle, heart boxers, blue axe, beard) but is flatter than a true rendered pedestal; the arm/torso
  joints are stylised. A small lit SubViewport stand-in is the obvious future upgrade if stability allows.
- Item/equipment **icons are generic vector glyphs**, not per-item art — the axe glyph in particular
  reads a little abstract at cell size. Fine as rarity-coded placeholders; distinct art would help.
- No tab **content switching** (tabs are decorative; CHARACTER is always active) and no real inventory
  data — everything is deterministically seeded flavour, which is all the capture needs.
- Timing is tuned to the capture's render-`t` behaviour; on a very short capture the character sheet
  may not be reached (use `--gap ≥ 22`, documented above).

## Constraints honoured
- Only `screens.gd` + this report + reference PNGs written. `game.gd`, other modules, `hud.gd`,
  `world.gd`, `player.gd`, tools untouched. No git run.
- GDScript: all locals explicitly typed (no Variant-inferred `:=`); `minf/maxf/clampf/lerpf` throughout.

## Self-score vs rubric §13: **8/10**
Both frames' required elements are present, crisp, and cohesive with the HUD. Biggest remaining gap:
the hero pedestal is a 2D vector portrait rather than a lit 3D render, and item icons are generic.
