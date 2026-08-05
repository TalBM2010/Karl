# Screen-space text arbiter — one readability round

**Goal:** the three floating-**TEXT** systems (damage numbers, loot/ground labels, enemy
nameplates) drew into screen space without coordinating, so on the boss cam — where every blow
lands at screen-centre — their rects collided and the text became an unreadable smear. Add ONE
shared arbiter so their rects stop overlapping, **without changing the look** of any label.

Priority when two rects clash: **damage numbers > loot labels > nameplates**. Lower-priority text
yields (slides to the nearest free vertical band, or dims out if boxed in under a damage number).
Damage numbers keep their existing vertical-lane system and win ties.

## The gap (before)

- `captures/gd/coh8lab2/shot_05.png` — a nameplate/loot label lands on the fading PHYSICAL number
  near screen-centre.
- `captures/gd/coh8lab2/shot_07.png` — the big orange "175,764 CRITICAL!" overlaps "Gold Loot Box",
  "Crystal Arachnid (6)" plates and "SYSTEM SEALED / BLOCKED".

## Design

A tiny, passive node — `godot/scripts/modules/text_arbiter.gd` — that the three systems consult
each frame. It holds no game state and never runs `_process`; it is a pure screen-space rect
registry.

**Ownership / coupling.** It is created lazily by whichever text module runs first (`_ensure_arbiter`
is mirrored, guarded, in all three) and stashed on `game.modules["text_arbiter"]`. Every cross-module
reach is guarded (`"modules" in game`, `is_instance_valid`, `has_method`), so a missing or failed
arbiter simply restores the old un-coordinated behaviour — never a crash. It uses `preload`, not a
`class_name`, so it stays loosely coupled and adds no global type.

**Rects.** Each label's screen rect is keyed by its `get_instance_id()` and stamped with the
process-frame it was touched on. The first arbiter call of each new frame prunes anything not
refreshed last frame, so retired labels self-expire (no leak) and the set stays tiny.

**Two entry points:**
- `register(id, world_pos, half_w, half_h, pri)` — damage numbers stamp a top-priority keep-out
  rect without moving (they keep their lane system, so they only need to be *avoided*).
- `place(id, world_pos, half_w, half_h, pri) -> {pos, hidden}` — loot labels and nameplates scan
  vertical bands (up first), find the nearest one clear of every **equal-or-higher** rect, register
  the result and return an adjusted world position. `hidden` is true only when boxed in directly
  under a damage rect.

**Order-independence.** Combat processes before enemies/loot (tree order), so damage rects are
always registered first each frame and lower-priority text always sees the *current* damage
positions. The only cross-priority stale case — a nameplate yielding to a loot label processed
later the same frame — reads last frame's loot rect, which is near-static, so it is visually
identical. No process-priority juggling and no edit to `game.gd` were needed.

**Two subtleties that mattered (both found via capture, not reasoning):**
1. *Screen→world mapping.* `Camera3D.project_position` at a fixed camera-forward depth slid labels
   **down-and-back** under the 43°-pitched iso cam (a nudge "up" moved text the wrong way). Fixed by
   mapping the screen-vertical nudge to a pure **world-Y** move: the camera has no roll, so world +Y
   projects to a pure vertical screen shift; the arbiter measures that px-per-world-Y factor directly
   (`unproject` a point 1 unit up) and inverts it.
2. *Two-line blocks + outline.* Each label is really two Label3D lines (name + type, or number +
   "CRITICAL!/PHYSICAL"), and the sub-line hangs well **below** the anchor — plus a heavy 9–14px
   outline. A rect sized to the top line alone let the sub-line land on other text. Fixed by
   extending each keep-out down past its sub-line (via a new `px_per_world` helper) and inflating
   every rect by a `MARGIN` (13px) so "touching" becomes a readable gap.

The search range is bounded (`band ≈ half_h·0.5`, 16 steps ⇒ ~200–270px) so a fully-blocked column
nudges a label a sane distance and then yields/hides, never flinging it across the frame.

## Files changed

- **`godot/scripts/modules/text_arbiter.gd`** — NEW. The shared arbiter (~180 lines, passive).
- **`godot/scripts/modules/combat.gd`** — `preload` + guarded `_ensure_arbiter`/`_arbiter`; each
  live damage number `register`s its keep-out rect every frame in `_update_texts` (gated on
  `alpha > 0.12` so a fading ghost never shoves other text). Height spans the number + its sub-label.
  The lane system and `_big_lock` arbiter are untouched.
- **`godot/scripts/modules/loot.gd`** — `preload` + guarded helpers; `_arbitrate_label` runs each
  frame for every drop/box label (idle, collect, box). Resets to the label's natural local-Y first
  (no accumulation), then re-applies only the screen-clearing delta; dims via the existing
  `_set_label_alpha` when boxed under a crit. Look/fade unchanged.
- **`godot/scripts/modules/enemies.gd`** — `preload` + guarded helpers; `_arbitrate_plate` slides
  the whole nameplate holder (label + health bar, as a unit) for every spider plate (in
  `_tick_spiders`) and Princess Donut's plate (in `_tick_donut`), dividing by the creature's scale.
  Boss has no plate (unchanged); the boss-cam contract, `_boss_phase`, scale and timing are untouched.

No label font, colour, size, outline or the crit look was changed — only positions (and, only when
boxed under a damage number, a temporary dim/hide).

## Before / after (boss-cam)

- **Before:** `captures/gd/coh8lab2/shot_05.png`, `captures/gd/coh8lab2/shot_07.png`
- **After:**
  - `captures/gd/textarb/after_bosscam_crit_shot04.png` — Juicer boss cam with a physical crit at
    centre: "Mongo's Prized Rock / Legendary Spiked Club" (loot) sits cleanly **above** "78,433
    PHYSICAL" with a gap; "7,148 Gold", "1,982 Gold" and three "Crystal Arachnid (6)" plates are all
    separated and readable.
  - `captures/gd/textarb/after_gameplay_shot06.png` — "12,923 BLOCKED", "Crystal Render", "Bronze
    Loot Box", "581 Gold", "7,148 Gold" and multiple arachnid plates, all cleanly separated.
  - `captures/gd/textarb/after_floorsintro_shot00.png` — floors intro overlay still occludes; the
    "70,880" number and plates behind it don't collide.

## Verification

- Warm capture (final source, 1600×1000, 7 shots): `CAPTURE_OK`, **no** `SCRIPT ERROR` / `Parse
  Error`. Menu-overlay wins (inventory with heart-boxers+axe, character sheet, floors intro) and
  boss hulk legibility all intact.
- **Cold cache caveat (pre-existing, not this change):** with `.godot` deleted, the run fails to
  load `game.gd` — `Could not find type "KarlWorld" / "KarlPlayer"`. Those are `class_name` globals
  declared in `world.gd`/`player.gd` (both untouched by me), and `game.gd` uses them at parse time
  (`var world: KarlWorld`, `KarlWorld.new()`). The project **ships** the resolved registry at
  `godot/.godot/global_script_class_cache.cfg` (dated before this task); this headless `--out`
  invocation does not rebuild it, so even a second cold run fails identically. Every prior capture
  round works because `cp -r godot lab` copies that shipped `.godot`. **None of the four files I
  touched appears in any cold error line**, and the arbiter deliberately uses `preload` (no
  `class_name`), so the failure reproduces with or without my work and is orthogonal to it —
  `game.gd` never references my modules or the arbiter at parse time (modules load dynamically at
  runtime). The meaningful cold signal I *can* give: the warm run compiled my **brand-new**
  `text_arbiter.gd` fresh (it had no prior artifacts in the copied tree) and reached `CAPTURE_OK`
  with zero parse errors. Making the literal one-run cold check pass would require editing `game.gd`
  or the `class_name` files, which is outside this task's contract.

## Honest read

**Screen-text readability now: 7.5 / 10.** No overlapping floating text in any sampled frame,
including the boss-cam crit that was the named gap; loot labels and nameplates dodge the numbers and
each other, and every label keeps its exact look.

**Residual gaps:**
- On the boss cam the loot label and the centre number end up **stacked in the same column** with a
  ~45px gap — separated and readable, but the region is still text-dense; it reads as "a lot going
  on" rather than a spacious layout. A horizontal fan (nudge X as well as Y) would spread the column,
  but that risks pushing loot labels off their items and was left out to keep the change minimal.
- When a rising crit fully covers the column, a low-priority label can briefly **dim/hide** for a
  frame or two rather than find a slot — intended, but at 1–8fps capture a still can catch that hidden
  moment (a plate momentarily absent).
- The nameplate-vs-loot yield uses last-frame loot rects (order artefact). Loot is near-static so
  this is invisible in practice, but a fast-moving future loot label could show a one-frame nip.
- Rect sizes are estimated from font metrics (width uses a ~0.6 glyph aspect), so packing is
  generous rather than pixel-tight — deliberately safe, occasionally spacing labels a touch more than
  strictly necessary.
