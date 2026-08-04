# Godot Floors — "THE SYSTEM" floor-intro broadcast + floor progression

**File owned:** `godot/scripts/modules/floors.gd` (399 lines, new — did not exist before).
**Rubric target:** "Content order (must follow the books)" + the DCC "System" floor-intro screens.
**Not touched:** game.gd, hud.gd, world.gd, player.gd, other modules, tools. Only floors.gd + this report.

## What was built

A floor-progression state machine plus a full-screen **"System" announcement overlay** — the DCC
in-world AI showrunner dropping a blue-system-text, dry/menacing/showbiz broadcast between floors.
Built entirely in code (Control + custom `_draw`) on its **own `CanvasLayer` at layer 20** (above
the HUD's layer 10) so the intro takes over the frame, then animates out to reveal gameplay.

Contract met: `extends Node`, `func setup(g)`. On every floor change it emits
`g.floor_changed.emit(index)` — the HUD listens and its Objectives panel retitles to the floor
(verified: Floor 2 capture shows the HUD reading "THE BRAMBLE").

### Floor data (book order)
| # | Name | Subtitle | Accent | Objective |
|---|------|----------|--------|-----------|
| 1 | THE CRAWL | THE COLLAPSED NEIGHBORHOOD | orange | Escape the Starter Neighborhood |
| 2 | THE BRAMBLE | THE OVERGROWN TRANSITION | green | Survive the Bramble |
| 3 | THE IRON TANGLE | THE OVER CITY / DESERT SET-PIECE | gold | Cross the Iron Tangle |

Each floor carries **original** System copy (reworded in the System's flavour, not verbatim from
any book) and a 3-line audience "react" feed with per-name colours. The accent colour tints the
whole announcement — border, corner filigree, rule, subtitle, react swatches — so each floor's
broadcast reads as *that* floor (orange Crawl → green Bramble → gold Iron Tangle).

### Intro-screen design (matches hud.gd)
- Radial-darken **scrim** (GradientTexture2D, FILL_RADIAL) — cheap "world dims for the
  announcement" without a backdrop blur (blur times out the software-GL capture, per the JS note).
- **`SysFrame`** panel (custom `_draw`): dark rounded body, 1px accent border, a *tasteful* rounded
  accent halo (5 low-alpha stylebox rings — kept restrained so bloom doesn't smear the bright
  border), corner filigree brackets, top sheen, and a pulsing red "REC" dot in the header.
- Header `THE SYSTEM // DUNGEON BROADCAST` + `LIVE / GALACTIC FEED`, hairline rule, gold
  `FLOOR N`, huge white floor name, subtitle, accent rule, wrapped blue system text, 3 react
  chips (colour swatch + coloured name + grey line), and a gold-bevelled `NEW OBJECTIVE` chip
  (`ObjChip`) with the per-floor objective.
- Fonts are `FontVariation` (letter-spaced / embolden) mirroring the HUD; every string runs
  through a `_san()` that drops glyphs the bundled font can't render (no emoji tofu).

### Demo cycle / animation
`_process` drives a ~16s-per-floor loop; `floor = cycle % 3`. Visibility is a **pure function of
absolute time-into-cycle** (`_vis()` with smoothstep in/out) — **not** per-frame weights — so it
never pops regardless of framerate. Timeline (process-seconds): in 0→0.7, hold →3.8, out →4.5,
dismissed after. Slide+slight-scale on the panel; whole overlay fades via `root.modulate.a`;
`root.visible` is forced off once dismissed so it never fights sibling overlays (loot/screens).

## The critical timing finding (documented in-file)

Under Xvfb + lavapipe the engine **clamps frame delta to ~0.14s**, so `_process` time advances at
~0.14s **per rendered frame**, decoupled from wall clock. Consequence: a short capture (warm 6 +
a few gaps of 10) only spans ~6–7 *process*-seconds — exactly Floor 1's window. The intro timeline
is tuned to that: the first ~3 shots land on the readable intro, later shots on clean gameplay.
Floors 2/3 roll in at t≥16 / t≥32, i.e. only in a **longer** capture (see below). This is why the
16s cycle is safe against a sibling `screens.gd` window (intro confined to 0–4.5s, fully gone after).

## What holds up
- Floor-1 System intro reads as a genuine DCC broadcast and matches the HUD product language
  (cyan-family bevels, filigree, glow, letter-spaced caps). Clean take-over then clean dismissal.
- Book order verified live: Floor 1 (orange) → Floor 2 (green), and the HUD objective panel
  retitles in sync via `floor_changed` — proving the signal contract works.
- Runs clean (no SCRIPT ERROR / Parse Error) standalone and alongside the new sibling `loot.gd`.
- Framerate-independent: the absolute-time timeline means no popping at 1–2 fps.

## What's weak / honest gaps
- **Floors 2 & 3 need a long capture** (t≥16 / ≥32 → ~114 / ~228 rendered frames). A default
  5-shot run only ever shows Floor 1. Mitigation is the recommended long path below; the
  data-driven `_apply_floor` makes all three identical, so Floor 3 was reasoned-fit not shot
  (its name "THE IRON TANGLE" is only ~1 word longer than the comfortably-fitting "THE BRAMBLE").
- Because shot spacing (~1–2 process-s) is close to the 0.7s out-transition, an occasional shot can
  land mid-fade (a soft dissolve of the whole overlay). It reads as intentional animation, not a
  bug, but it's a coin-flip which frame catches it.
- The intro only drives the **UI + floor tracker + HUD objective**; it does not re-terraform the 3D
  world per floor (out of scope per brief — the world stays the Crystal Depths sub-level).

## Best capture paths
```
LAB=/tmp/claude-0/-home-user-Karl/ac8e63f5-175a-5bd6-bfea-559174670f72/scratchpad/lab_floors
rm -rf "$LAB"; cp -r /home/user/Karl/godot "$LAB"
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json

# Floor-1 intro THEN clean dismissal (primary target):
timeout 200 xvfb-run -a -s "-screen 0 1600x1000x24" /opt/godot/godot --path "$LAB" \
  --resolution 1600x1000 -- --out "$LAB/cap_short" --shots 5 --gap 10 --warm 6
#   shot_00/01/02 = System intro readable; shot_03/04 = dismissed to gameplay.

# Book-order cycling Floor 1 -> Floor 2 (HUD objective retitles in sync):
timeout 280 xvfb-run -a -s "-screen 0 1600x1000x24" /opt/godot/godot --path "$LAB" \
  --resolution 1600x1000 -- --out "$LAB/cap_long" --shots 12 --gap 15 --warm 6
#   early shots = Floor 1; shot_08/09 = Floor 2 "THE BRAMBLE" (green accent).
```
Reference frames captured this session:
- Floor 1 intro: `lab_floors/cap_short/shot_00.png`
- Clean dismissal to Juicer gameplay: `lab_floors/cap_short/shot_04.png`
- Floor 2 cycling + HUD sync: `lab_floors/cap_long/shot_08.png`
