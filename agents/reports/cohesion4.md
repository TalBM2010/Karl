# Wave 4 Cohesion + QA — build report

**Files edited (only these):** `src/lootbox.js`, `src/floors.js`. No commits/pushes. `api.floors` and
`api.lootbox` preserved; both modules keep their auto-load `init(api)`. Build boots with `"errors":[]`.

## The two seams fixed

### 1. Loot-box ceremony now dims the live game cleanly (lootbox.js)
The ceremony's `.veil` previously darkened to only `.30` alpha at center, so the boss + combat showed
through and fought the reward card for attention. Replaced it with a proper full-screen dimming backdrop
behind the ceremony content: a flat darken (`rgba(3,8,13,.55)`) layered under a radial vignette
(`.56 → .82 → .95`), giving ~74% dark dead-center rising to ~95% at the edges. The reward now reads on a
deep, clean, focused field while the box glow / light-leak / shard particles (screen-blended, on top) still
pop. It fades in and restores with `#karl-lbx.on`, so the game returns smoothly. **No `backdrop-filter`
blur** — floors.md documented that a full-screen blur times the software-GL capture out; the layered darken
gives the same "world dims for the reveal" read cheaply (and fps held at 20-28, unchanged).

Verified: `cohesion4/shot_09` (settled Rare reveal) and `cohesion4b/shot_08` (charge phase) show the card /
box popping on a deep-dark, boss-ghosted background.

### 2. Overlays never stack messily — bidirectional gate (lootbox.js + floors.js)
Three z-full-screen layers exist: loot ceremony (z30) < floor-intro (z40) < character/inventory (z60). Two
races were producing stacked overlays (baseline `cohesion4_pre/shot_00` showed the gold box + light-leak
bleeding through the FLOOR 1 intro; the coordinator saw a GOLD ceremony over the FLOOR 3 intro). Fixed both
directions:
- **lootbox.js** — `open()` now no-ops (returns false) while a floor-intro is showing **or fading** (reads
  `#floor-intro.on` + a `data-busy` flag floors sets across its 0.55s fade-out) or while the C/I screen is
  open (`#ks-root.open`). In `?auto` the demo loop **defers** (retries in 1.3s) instead of skipping, so a
  ceremony still fires — and gets captured — the instant the other overlay clears.
- **floors.js** — when a floor-intro takes over the frame it first calls `api.lootbox.close()`, which
  **synchronously** tears down any active ceremony (new `dismiss(immediate)` path) before the intro paints,
  so the two can never share a single rendered frame. It also flags `data-busy` for the fade-out tail.

Verified: `cohesion4b/shot_00` (FLOOR 1) and `shot_04` (FLOOR 3) render clean with **no** ceremony bleeding
through; `shot_03/07/08/11` show Silver/Platinum/charge/Mythic ceremonies with **no** floor panel;
`cohesion4_c/shot_01` shows the character sheet clean with no ceremony intrusion.

## Whole-loop QA (rubric bar = Diablo IV)
Read coherently across the captures: floor intro (F1 amber / F2 bramble-green / F3 iron-tangle gold, each
retinted to match the world behind it) → retinted gameplay → combat with floating damage numbers
(11,889 / 12,731 / 16,363) and ability skill-bar → the Juicer boss with `#bossbar` (name, level diamond,
segmented HP %, affix pips) → loot beams + ground name-labels (still running, correctly dimmed *behind* the
ceremony veil — the faint bottom-center item labels are loot.js, not a leak) → the reward ceremony
(present / charge / burst / reveal / claim all intact) → character sheet. All under the bloom/grade, deep
blacks not blown out, HUD never wrongly occluded, no DOM/particle leaks, fps steady (20-28 under software GL,
same as baseline).

## Wins confirmed intact
world/grade/bloom, damage numbers + VFX, boss + `#bossbar`, abilities + skill-bar, loot beams + ground
labels, both screens (C/I), all three floor intros + per-floor retints, the full reward ceremony, the
broadcast HUD (title bar, LIVE feed + viewer count, minimap, objectives, combat analysis, chat ticker, orbs).

## Verification commands
- `node tools/capture.mjs --out captures/cohesion4 --shots 10 --gap 850 --strip 16 --stripgap 140` → `"errors":[]`
- `node tools/capture.mjs --out captures/cohesion4b --shots 12 --gap 800` → `"errors":[]` (catches both a floor-intro and a separate ceremony; none stacked)
- `node tools/capture.mjs --out captures/cohesion4_c --key c --shots 2` → `"errors":[]` (character sheet clean/unaffected)
