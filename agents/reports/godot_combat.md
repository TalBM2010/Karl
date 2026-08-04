# Godot combat feel — floating damage numbers, impact VFX, ability VFX

**Owns:** `godot/scripts/modules/combat.gd` (new, ~1130 lines). Nothing else was touched.
**Final capture:** `captures/gd/vfx_final/` (4 shots + 8 motion-strip frames, 1600x1000, ~59 s run, no SCRIPT ERROR).

## What shipped

**1. Floating combat text.** `Label3D` pop-ups, billboarded, `no_depth_test`, DejaVu Sans Bold via
`SystemFont` with MSDF so the glyphs stay crisp at any size, and a heavy pure-black outline so they
read over crystal glow or black rock alike. Four styles matching the reference frames: molten-orange
crits with a gold **CRITICAL!** sub-label, bone-white **PHYSICAL**, violet **AETHER**, dull grey
**BLOCKED**, all comma-formatted. Each pop scale-punches from 0.25 to an overshoot of 1.22, settles,
rides a ballistic arc upward, holds full opacity for ~60 % of its life and then fades.

The labels use `fixed_size = true`, so they occupy a constant share of the screen no matter where the
camera sits — important because the camera framing kept changing under me while other agents worked.
Every layout offset (sub-label drop, the 4-slot anti-overlap spread along the camera-right axis) is
therefore multiplied by camera distance, since a fixed-size Label3D's apparent world size is
`pixel_size * font_size * distance`. Screen spacing stays constant as a result.

**2. Impact VFX.** `GPUParticles3D` with additive unshaded materials and procedurally generated glow
sprites: hit sparks on every blow, a billboard impact flash with a short `OmniLight3D` pop, an
expanding radial ground shock ring on crits, and a crystal-shard death burst (emissive `PrismMesh`
draw pass with angular velocity). All ring/crescent geometry is built with `SurfaceTool` as an annulus
with a caller-supplied **radial alpha profile**, so the same generator makes a thin hot shock ring, a
fat nova wave, and a crescent whose energy concentrates on its leading edge.

**3. Ability VFX.** CLEAVE — a thin bright cyan crescent that sweeps ~115° through Carl's swing arc
while it stretches. AETHER NOVA — twin violet ring shockwaves plus a ring-emitter burst of aether
motes. WHIRLWIND — six leaning energy blades and two tilted bands spinning around Carl, kicked off by
a cyan ground ring. WAR CRY — a generated ground rune texture (bands, twelve spokes, glyph ticks) that
scales and rotates up, under an upward light pillar built from three crossed soft-gradient planes
(a cylinder gave a hard silhouette that read as a solid white column; crossed planes read as an actual
shaft of light from any angle). Plus a persistent AETHER AURA — three counter-rotating rings, a soft
floor glow pool and slow rising motes — so Carl always looks powered-up.

**4. Camera shake.** Applied only through `cam.h_offset` / `cam.v_offset` with a decaying two-frequency
wobble, and forced back to exactly zero when it expires. It never touches `cam.position`, so it cannot
fight `game.gd`'s camera follow.

## Engineering notes

- **Everything is pooled.** A kind-keyed free list backs text holders, particle emitters, rings,
  crescents, runes, flashes and pillars; nothing is allocated per hit and nothing is left emitting.
- **Delta is clamped to 0.12 s.** Software Vulkan delivers 1–2 fps under Xvfb, so raw deltas of ~1 s
  would skip every effect entirely between frames.
- **Self-driving demo.** In `game.is_capture` the module runs its own director — an 8-beat hit cycle
  (never two crits back to back) every 0.6 s and a four-ability rotation every 0.95 s — so captures
  always show the work. It also connects to `hero_attacked` / `enemy_killed` when those fire.
- **Tuning was mostly about restraint.** The first passes were badly overexposed: additive VFX on top
  of ACES tonemapping plus bloom clip to white the moment two effects overlap. Crits came out yellow
  until the green channel was pulled well below red; the aether ring came out magenta until red was
  pulled down. Final HDR values sit just past the glow threshold, and the flash sprites peak at 0.55
  alpha rather than 1.0.

## Iteration log (captures)

`vfx1` numbers far too large, crits yellow → `vfx4` abilities visible but nuclear white → `vfx5/6`
intensities halved, cleave reshaped from a soft fan into a blade → `vfx9/10` text switched to fixed
screen size → `vfx11` distance-aware layout → `vfx_final` spread tightened to stay inside the HUD's
central play window.

## Known limits

- Overlapping pops still happen occasionally during a dense burst. The reference frames stack numbers
  too, and the crit always wins the read, so this was left as juice rather than suppressed further.
- If a future floor uses a much brighter environment, the additive ability colours will want another
  pass — they are tuned against the dark Crystal Depths grade.
