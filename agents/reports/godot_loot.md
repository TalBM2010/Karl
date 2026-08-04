# Godot loot & drops — rarity beams, ground labels, System loot boxes, pickup pops

**Owns:** `godot/scripts/modules/loot.gd` (new, ~380 lines of logic / 952 lines w/ comments).
Nothing else was touched. game.gd already lists `"loot"` in its module loader, so the file just
had to appear at `res://scripts/modules/loot.gd` and implement `setup(game)`.

**Best capture frames:** `/tmp/claude-0/-home-user-Karl/ac8e63f5-175a-5bd6-bfea-559174670f72/scratchpad/lab_loot/cap/`
- `shot_00.png` — Frame B: "Gravebite / Legendary Warhammer" under an orange beam + a single
  "1,513 Gold / CURRENCY" pile with visible coins and a warm gold shaft.
- `shot_02.png` — a "Gold Loot Box / SYSTEM · SEALED" metal cube hovering next to Carl, alongside
  "Mongo's Prized Rock / Legendary Spiked Club" and a gold pile.
- `shot_03.png` (previous run) — gold pickup-pops streaking upward as drops auto-collect.

(Lab-only capture per instructions — no final capture against the real repo path, to avoid the
shader-cache write race with the sibling builders on floors.gd/screens.gd.)

## What shipped (rubric 12)

1. **Rarity drops.** Five tiers Common→Mythic, color-coded white / blue / purple / orange / red
   exactly per the rubric line. Each drop is a Node3D holder carrying:
   - a **light shaft** built from two crossed soft-gradient vertical quads (the war-cry-pillar
     trick — a cylinder reads as a solid tube; crossed feathered planes read as light from any
     camera angle) plus a thin brighter inner shaft and a ground light-pool disc. Shaft height and
     alpha scale with rarity.
   - a **spinning item mesh**: weapon (handle + spiked head + spike + rarity gem), gem
     (octahedron core + torus ring), armor (plate + trim), or a **gold pile** (scattered coin
     cylinders). Item bobs and rotates on an idle loop.
   - a **crisp ground label**: name in the rarity color over an uppercase type line
     ("Legendary Spiked Club" / "CURRENCY"), both `Label3D` `fixed_size` at font 48/34 with
     `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`, so they stay legible at camera standoff instead of
     downsampling to mush.
2. **Loot-box open flourish.** A floating tiered metal cube (Bronze/Silver/Gold/Platinum, weighted)
   with banding seams and a glowing keyhole lock. It hovers, bobs, spins, pulses its lock, then
   **shivers and bursts**: a `PrismMesh` shard explosion (`GPUParticles3D`), a billboard light
   flash + `OmniLight3D` pop (both faded via a `Tween` so it's framerate-independent), a camera
   kick borrowed from the combat module, and it ejects a rarity-biased item drop onto the ground.
3. **Pickup pop.** After a few seconds a drop auto-collects: item lifts, spins up, shrinks and
   fades; the beam collapses down into the ground; the label rises and fades; and a bright glow
   streak shoots upward (the "pops to inventory" flourish, kept world-space so it never reaches
   into the HUD's loot orb).

## Signals & demo

- Connects `enemy_killed` → ~12% chance of a loot box, ~50% a normal rarity drop at the death spot.
- `is_capture` demo director keeps a fresh **legendary weapon + gold pile** planted ahead of Carl
  at all times (Frame B), retiring the previous showcase pair each cycle so labels don't stack,
  and cycles a System loot box through its ceremony every ~7.5s.

## Root causes / gotchas navigated

- **No Variant `:=`.** Every local is explicitly typed; dictionary reads that feed typed vars are
  wrapped (`Color(d["disp"])`, `int(tier["bias"])`) so nothing infers Variant. Clean parse on
  first capture.
- **Additive-over-ACES restraint.** Beam colors are HDR pushed just past the white point on the
  dominant channel only (orange stays orange, purple stays purple under bloom); per-plane alphas
  are kept ~0.22–0.30 so a single shaft reads as clean colored light, not a white blob. Verified
  across four frames — nothing blows out.
- **Framerate independence.** Idle/collect easing runs on delta-clamped `_process` math; all
  one-shot fades (flash, streak, particle reap) use `Tween`s (wall-clock), never per-frame weights.
- **Label crispness** copied straight from the enemies.gd nameplate fix (`fixed_size` + mipmaps).

## Holds up vs rubric 12 — and what's still weak

Holds: all four rubric-12 bullets are visibly present in-scene without fighting the HUD or the
cavern grade, and Frame B (legendary weapon on the ground under a colored beam + a gold pile) is
present in essentially every frame. Colour harmony is intact — orange/gold loot sits alongside the
violet crystals and red boss with nothing clipped.

Weak / remaining gaps:
- The demo only *guarantees* the Legendary (orange), Rare (purple) and Gold beams on screen; the
  full white→blue→red ladder exists but only appears from random `enemy_killed` drops, so a single
  4-shot capture won't always show all five rarity colours side by side.
- The loot-box **burst** instant (shards + flash) is brief; captures reliably catch the *sealed*
  hovering box, but landing the exact pop frame is luck at ~2 fps.
- Ground labels can still occasionally overlap the combat damage numbers, since both cluster around
  Carl; there's no 3D equivalent of the reference's screen-space HUD-clamp.

## Self-score

**8 / 10** vs rubric 12. Biggest remaining gap: the full five-colour rarity ladder isn't
guaranteed in any one capture frame (only Legendary/Rare/Gold are demo-forced), and the loot-box
burst moment is capture-luck rather than reliably framed.
