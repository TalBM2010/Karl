# Godot whole-game cohesion pass

Final capture: `captures/gd/coh_final/` (5 shots + 6 strip frames, 1600x1000)
Files touched: `godot/scripts/modules/combat.gd`, `godot/scripts/modules/enemies.gd`,
`godot/scripts/game.gd`. **Not** touched: `world.gd`, `player.gd`, `hud.gd`, `capture.gd`,
`project.godot`, `tools/*`, `src/*`.

## The problem

Four modules built in isolation composited into a frame that did not read as Diablo IV. The
single biggest offender was VFX volume: `combat.gd`'s demo director fired an ability every
0.95s from a 4-ability rotation whose effects run 0.8-2.1s each, so the war-cry pillar, the
aether nova, the whirlwind and the cleave crescent were routinely all alive at once — on top of
a *persistent* aura whose rings sat at 50-62% alpha across Carl's torso and head. All of it was
additive at HDR magnitudes of ~1.7, summing past the white point and clipping to a flat
orange/white blob over ACES + bloom that buried both the cavern and the hero.

## What changed

**VFX restraint (combat.gd)**
- Added a `_big_lock` arbiter. Every ability (`cleave`/`aether_nova`/`whirlwind`/`war_cry`)
  now calls `_claim_big(lock)` and silently drops its effect if another big effect is still
  playing. One screen-filling effect at a time, globally — not just in the demo path.
- Demo ability cadence 0.95s -> 3.1s, gated on the same lock. Hit cadence 0.60s -> 0.85s.
- War cry was the worst: the light shaft went from a 2.3x11.0m, 55%-alpha column to a
  1.15x5.2m, 20%-alpha flare; its life 1.2s -> 0.70s; its alpha envelope changed from
  `sin^0.7` (a plateau at full brightness) to `sin^1.5` (a quick spike). Ground rune scale
  3.2 -> 2.15 and alpha x0.42.
- Nova ring radius 7.6 -> 5.4m, life 1.15 -> 0.85s; whirlwind blades/bands 0.72/0.62 alpha ->
  0.30/0.24, duration 2.1 -> 1.35s; cleave alpha 0.85 -> 0.52.
- **Additive clipping:** dropped the HDR magnitudes of the ability palette (`COL_VIOLET`
  1.70 -> 1.18, `CLEAVE_COL` 2.00 -> 1.42, `COL_GOLD`, `COL_CYAN` likewise) and the impact
  flash (alpha 0.55 -> 0.30, light 2.8 -> 1.4). Two overlapping surfaces now stay in gamut and
  keep their hue instead of summing to white.
- **Persistent aura is now a hint:** floor pool 4.6 -> 3.4m at 10% alpha, the shoulder-height
  ring deleted entirely, the two survivors at 17%/10% alpha, motes 18 -> 11 and smaller. Carl
  reads clearly *through* his own aura.

**Damage numbers (combat.gd)** — crit `pixel_size` 0.00062 -> 0.00039, normal 0.00042 ->
0.00026 (a crit was ~115px tall and a third of the frame wide; it covered the boss). Max
simultaneous 5 -> 3, life 1.35 -> 1.15s, slot spread widened 1.15x -> 1.75x so pops separate.
Spawn scale-punch floor raised 0.25 -> 0.82: at the framerate software Vulkan actually renders,
frames regularly land inside the first 0.1 of a number's life, and a quarter-size crit next to
a full-size normal hit just read as a bug.

**Nameplates (enemies.gd)** — they were *world-space* labels: a 96px glyph squeezed into ~10
screen pixels at the camera's standoff, i.e. a 10:1 downsample into mush. Now `fixed_size` at
font 44 with mipmapped filtering, so glyphs raster near their display size and hold a constant
legible screen height. Plates are grouped under one holder and fade out past ~10.5m from Carl,
so two or three engaged arachnids carry plates instead of six competing for the eye. The boss's
world plate is gone — the HUD already owns his identity with a full broadcast boss bar, and the
floating label landed right on top of it as doubled text.

**Boss framing (game.gd + enemies.gd)** — `CAM_OFFSET_BOSS` was declared but never used, so the
Juicer was always cropped to legs. The camera now eases toward it on a distance weight, forced
fully open during `telegraph`/`slam` so the wind-up always plays as a full-body wide shot.
Critically the look-at stays **welded to Carl** and only the camera *distance* opens up: leaning
the aim toward the boss (my first attempt) slid Carl down and off the bottom edge behind the
skill bar whenever the boss happened to be up-screen. Boss hold distance 9.5 -> 9.0m.

**Camera follow bug (game.gd)** — the follow used raw per-frame lerp weights (0.08/0.10). That
is fine at 60fps but catastrophic under software Vulkan: at the ~8fps the capture renders, a
0.06 weight is a ~2-second time constant, so Carl — sprinting at 4.2 m/s — literally outran his
own camera and left the frame. Converted to exponential decay on `delta`; the follow is now
identical at any framerate. This was the actual cause of the "Carl is missing" frames.

**Boss legibility (enemies.gd)** — added a low warm omni fill riding with the Juicer. The
cavern grade is deliberately moody and was crushing an 8.9m dark-red hulk into a flat black
silhouette at boss-cam distance. This lifts his musculature out of the shadows **without
touching world.gd's global grade** — the deep blacks and the moody tone map are untouched, which
was the explicit constraint.

## Result

Verified across 7 capture cycles. The frame now reads as a Diablo IV screenshot: moody crystal
cavern with deep blacks intact, Carl heroic and readable at game distance (heart boxers, muscle
suit, cyan axe all legible), Princess Donut padding alongside, arachnids with crisp nameplates,
the Juicer fully framed and menacing during his telegraph, punchy-but-restrained VFX that
punctuate rather than erase, and the broadcast HUD crisp on top. Colour harmony holds — cyan
axe, violet crystals, red boss and orange crits sit together with nothing blown out.

Every piece still works: world (cavern + Forward+ grade, untouched), Carl (rig, muscle suit,
axe), enemies (Donut, 5 arachnids, the Juicer with his whey jug and glowing red eyes), the full
ability set, and the HUD (orbs, skill bar, boss bar, audience feed, minimap, objectives,
ticker). Contracts preserved: `KarlWorld.build()/crystals/set_mood()`,
`KarlPlayer.build()/set_state()/attack()`, module `setup(game)`, game.gd's loader and signals.

Full engine log checked on the final run — no SCRIPT ERROR, no parse errors, no null-instance
warnings. Capture runs complete in ~60-75s.

## Known residual (minor)

In one of five frames a secondary crit renders smaller than its neighbour with its "CRITICAL!"
sub-label crowded against it. It is low-alpha and peripheral and does not read as broken, but it
is not the scale-punch (raising the punch floor to 0.82 did not change it), so something in the
pooled-Label3D `fixed_size` sub-label offset path is worth a look if this gets another pass.
