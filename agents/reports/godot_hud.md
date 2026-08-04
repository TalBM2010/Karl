# Godot HUD — "Galactic Observation Protocol" broadcast overlay

**File owned:** `godot/scripts/modules/hud.gd` (1614 lines, new)
**Final capture:** `captures/gd/hud_final/` (shot_00/01/02.png, 1600x1000)
**Rubric sections covered:** 9 (orbs), 10 (skill bar), 11 (broadcast frame), 14 (boss bar)

## What was built

Everything is code-built Control nodes on a `CanvasLayer` (layer 10) added by `setup(game)`.
Design space is 1600x1000; every block is edge-anchored (`_place()` maps a design-space `Rect2`
to left/right/centre/full-width + top/bottom anchors) so the layout scales with the window.
The middle of the screen is deliberately empty — gameplay reads through.

- **Top bar** — centred `GALACTIC OBSERVATION PROTOCOL` in a wide letter-spaced glowing cyan
  (`FontVariation.spacing_glyph` + outline halo), flanked by hairlines; left `◆ LIVE BROADCAST ·
  THE UNDERDEEP` (vector diamond, not a glyph); right `OBSERVATION NODE: XK-77 / ALPHA`, a cyan
  divider and a live clock.
- **Left — Inter-Sector Audience Feed** — pulsing red `● LIVE` chip, `17.8B` headline plus the exact
  count ticking up (~3.1M/s), a viewer sparkline, and 8 alien chat rows (avatar swatch, coloured
  name, timestamp, wrapped hype line). New messages arrive every 1.1–2.3 s, shift the stack up and
  fade in; seeded rows are back-dated so the feed looks like it has history. No repeat of the
  previous name or line.
- **Bottom-left — Specimen Vitals** — CARL (LVL 78) HP/Energy/Adrenaline and PRINCESS DONUT (LVL 78)
  HP/Focus/Mood, each with a drawn portrait box; every bar is a caption row (tag left, value right)
  over a thin segmented track with a bright leading tip.
- **Right column** — Sector Map (grid, rooms + corridors, radar sweep, pulsing hero blip driven by
  `game.hero_pos`, hostile marks), Objectives (gold floor title, checkbox main objective, gold bonus
  line), Combat Analysis (DPS / crit rate / kills / duration with cyan tabular values + a filled
  sparkline).
- **Bottom centre — D4 dock** — 128px red HP orb and blue resource orb with a real liquid sim
  (wave polygon intersected against the sphere via `Geometry2D.intersect_polygons`, vertical colour
  gradient, surface highlight, glass rim, specular blob, outer bloom) and `cur / max` centred;
  a 9-slot skill bar with hand-drawn vector icons (cleave, whirlwind, leap, shout, frost nova, dash,
  heal, ultimate, block), key hints (L-Click,1,2,3,4,Q,E,R,R-Click), radial cooldown sweeps with
  numeric timers, a 6-pip buff/timer row above, and an XP track with a gold level-78 diamond between
  the orbs.
- **Top centre — Boss bar** — JUICER / ENHANCED BEYOND NATURAL LIMITS, red level diamond, 16-segment
  HP bar with animated lag + `cur / max (pct%)`, four affix pips, and a soft dark scrim so it reads
  over bright scenes. Hidden by default; it auto-reveals ~1.8 s in **only** while no other module has
  driven it (any call to `show_boss`/`set_boss_hp`/`hide_boss` permanently disables the demo).
- **Bottom strip — Galactic Chat Ticker** — labelled chip, gradient fade, seamless horizontal scroll.
- Broadcast **corner filigree** on every panel and around the whole frame.

## API for other modules
`show_boss(name, subtitle, level)`, `set_boss_hp(cur, maxv)`, `hide_boss()`,
`set_objective(title, main_text)`, `set_vitals(hp, maxhp, energy, maxenergy)`,
`set_stat(key, value)`, `push_chat(name, text)`, `notify(text)`.
Also auto-reacts to `hero_attacked` (resource drain, DPS, boss damage + skill flash),
`enemy_killed` (kill counter) and `floor_changed` (objective title).

## Notes / gotchas hit
- Godot treats *"type inferred from a Variant value"* as a **hard parse error**: `min/max/clamp/lerp`
  return Variant, so every `:=` fed by them had to become `minf/maxf/clampf/lerpf` or an explicit type.
  Widget references are typed to their inner classes (`var orb_hp: Orb`) so property access is checked.
- `Control.size` is still `(0,0)` inside `_ready()`, so chat rows set their size **before** `add_child`.
- `Label` cannot shrink below its text width — top-right labels use `clip_text = true` so they can't
  push into the clock.
- `Font.has_char()` is used to sanitise every string: the bundled font has no emoji, so 🔥/👑/💪 in the
  spec's hype lines would render as tofu and are stripped automatically. Symbols that would tofu
  (◈, ●, ◆, checkboxes, level diamonds) are drawn as vectors instead.
- `game.gd` never emits `hero_attacked` yet, so the HUD self-drives a demo pulse (fires a random skill,
  drains resource, ticks adrenaline every 0.7–1.5 s) to keep orbs/cooldowns visibly alive. Real signals
  simply add to it.
- Runs clean: no `SCRIPT ERROR` in the capture log; capture cycle ~60–90 s when the box isn't
  contended (one earlier run failed with a `game.gd` camera nil error caused by another agent editing
  `world.gd`/`player.gd` mid-run — unrelated to this module, and it reproduced clean afterwards).
