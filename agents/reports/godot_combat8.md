# Combat impact-feel pass 8 — `combat.gd` (rubric §7 & §8)

**Owns / edits:** `godot/scripts/modules/combat.gd` only. No other file touched. The module
contract (`setup(game)`, `hero_attacked`/`enemy_killed` hookups, pooling, fault isolation), the
floating damage-number system and the `_big_lock` big-effect arbiter are all preserved unchanged.

**Goal:** push the *impact* so a hit reads as weighty even in a still, without spending the
additive-white budget that clips the frame the instant two additive surfaces overlap.

## What changed (three new impact layers)

1. **Dust — kicked up on run and on impact.** A persistent low ground emitter (`_build_run_dust`
   / `_update_run_dust`) rides Carl's feet and only emits while he is actually moving (speed is
   measured from `hero_pos` deltas, smoothed, with an upper guard that rejects teleport spikes).
   Impact dust (`_dust_burst`) fires a one-shot puff at the point of every hit — a light scuff on
   a normal blow, a real cloud at the point of a heavy hit, plus a puff on death.
   **Crucially the dust is ALPHA (`BLEND_MODE_MIX`) blended in a warm cavern grey, not additive**
   (`_dust_particle_mat`, render_priority 2). It grounds the action and reads as kicked earth
   while costing *zero* of the additive budget — it can never nudge the frame toward white.

2. **Attack arc VFX — a per-swing axe trace.** `swing_arc()` spawns a tight cyan-edged crescent
   (`_mesh_swing`, reach ~1.3–2.4 m, 152°, energy hard on the leading edge) at Carl that sweeps
   through the chop and fades (`sin`-envelope, peak α 0.66, life 0.50 s). It fires on every real
   hit (signal path *and* the capture demo path) and, being a per-hit cue rather than an ability,
   deliberately does **not** claim `_big_lock` — but it sits at the hero, spatially clear of the
   hit flash out on the target, so the two additive transients never co-locate into a blob. Its
   edge colour `SWING_COL` (1.46) sits under the cleave ability's `CLEAVE_COL` so a swing + a hit
   flash in the same frame still hold their hue.

3. **Hit flash + knockback cue on the struck point.** `hit_flash()` replaces the old tinted
   impact flash with a punchy white/additive pop (cyan-white on normals, hot amber on crits) that
   persists ~0.4–0.46 s on an exp-decay envelope so it still *lands* in a 1–8 fps capture, plus a
   short additive `_streak` smear shot along the knockback axis (`pos - hero`) that stretches out
   and fades — a directional impulse cue readable in a still. Flash peak α is held at 0.40–0.46 so
   it punctuates without clipping against the co-located sparks.

`_flash` gained an optional `peak` arg (default 0.30, so every existing ability caller is
unchanged); the effect updater gained `swing` and `streak` cases and a `peak`-aware `flash` case.
All new effects are pooled through the existing kind-keyed free list; nothing allocates per hit.

## Verification

Ran under Xvfb + lavapipe at 1600×1000. **0 `SCRIPT ERROR` / `Parse Error`** across the import
passes and the capture runs; `CAPTURE_OK`.

Environment note worth recording for the next builder: `world.gd`'s `FastNoiseLite` cellular-enum
names don't parse from source in this Godot build, so the project only runs off its committed
`.godot` script cache. Editing *any* module (here `combat.gd`) makes the copied cache stale, which
triggers a project-wide hot-reload that re-parses `world.gd` and surfaces those latent enum errors
— killing the scene with a `KarlWorld.new()` cascade even though `combat.gd` itself parses cleanly
(`can_instantiate=true`). The fix is to rebuild the cache from scratch in the lab: `rm -rf
$LAB/.godot`, run `--headless --import` **twice** (the second pass resolves the `KarlWorld` /
`KarlPlayer` class-name ordering), *then* capture. With that, the final run was 0-error.

## Before / after frames

Both are floor-intro-window gameplay frames of the same Crystal-Depths scene (Carl sits at
bottom-centre below the broadcast panel). Demo hits are stochastic in exact position, so these are
not pixel-matched, but the added grounding is clear.

- Before (original combat): `captures/gd/combat8/before_floorintro_carl.png`,
  crop `captures/gd/combat8/before_carl_region.png` — sparks + numbers + loot beam, but Carl's
  feet are dark and ungrounded, no swing trace, no impact flash.
- After (this pass): `captures/gd/combat8/after_floorintro_carl_dust.png`,
  crop `captures/gd/combat8/after_carl_impact_ember_streak.png` — a warm impact ember, cyan
  swing/knockback streaks and a tan dust puff at Carl, on top of the same sparks + numbers.
- Additive-budget check: `captures/gd/combat8/after_panel_fade_embers.png` — the panel fading out
  over live combat; embers + dust punctuate, the grade stays deep and moody, nothing clips white.

## Concurrent edit note (important for the shipped file)

A sibling edit to `combat.gd` landed **while I was working**: the damage-number layout in
`spawn_damage` was reworked from camera-right "slots" to per-number **vertical lanes**
(`PS_MAX`, lane-claim loop). That is not my code and I left it in place — it is isolated to the
number-positioning block and does not touch my impact functions. The final shipped
`combat.gd` (1473 lines) therefore carries **both** my impact work and that lane layout. I
re-ran the full rebuild-and-capture on this **combined** file (not just my own version): parses
`can_instantiate=true`, **0 SCRIPT ERROR**, and in gameplay the numbers read as single legible
values ("175,764 CRITICAL!", "70,880 PHYSICAL") with my dust/arc/flash live and the frame still
deep and moody — no clipping. Final combined-source frames:
`captures/gd/combat8/after_final_boss_crit.png`, `after_final_floorintro.png`.

## Honest read vs §7 & §8

- §7 "impactful hits / flash on the struck enemy / dust on run and impact / attack VFX arcs":
  all four are now present and — the load-bearing point — **in gamut**. Across every gameplay
  frame captured (floor-intro window, panel-fade, and a boss-telegraph crit frame showing
  "175,764 CRITICAL!"), the frame never clips to white; deep blacks and the moody grade survive
  with crits, sparks, dust, arc and flash all live at once. The `_big_lock` arbiter and the
  damage-number system are untouched and still hold the cadence.
- §8 "additive glow not muddy alpha": the *light* cues (arc, flash, sparks) stay additive and
  bloom; the *dust* is intentionally alpha-blended so it occludes like earth instead of glowing —
  which is what keeps the run/impact grounding from stealing budget from the punch.

**Score for combat impact now: ~8.7 / 10.** The hits read weightier and better grounded than the
~8.6 baseline, and the hard-budget failure mode (additive soup washing the frame) is firmly
avoided.

## Biggest residual gap

The capture director keeps Carl dead-centre behind its broadcast / inventory / character panels,
so I could not land a *pristine, unobstructed* hero still where the swing arc dramatically traces
the axe — in the frames available it reads as a crisp cyan streak rather than a showcased
follow-through. The effect is wired, in-budget and visible, and will read cleanly in
unobstructed gameplay, but its hero-still prominence is unverified. Secondarily, run-dust
visibility in any given still depends on Carl actually moving at capture time (it is movement-gated
by design); it shows in motion but a stationary sampled frame won't carry it.
