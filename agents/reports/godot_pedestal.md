# Pedestal hero — Option B: the real rigged Carl in a live SubViewport

Targeted refinement of the INVENTORY pedestal figure in `godot/scripts/modules/screens.gd`.
Everything else on the screen (tabs, equipment columns, item grid, stat card, currency row,
class label, char sheet) and the cohesion fix (opaque scrim + guarded `_occlude()`) is untouched.

## The gap
The pedestal hero was a stylised 2D vector statue (`_carl()` immediate-mode draw). It read as a
STIFF GREY MANNEQUIN — flat torso, thin T-stance limbs — holding the whole screen below the D4 bar.
Before: `captures/gd/coh7e/shot_03.png`.

## Option taken: **B (higher ceiling)** — the actual rigged hero, rendered
Instead of hand-drawing a better statue, the pedestal now shows the REAL `KarlPlayer` — the same
~50-volume muscle suit, heart boxers and glowing cyan double-bit axe used in gameplay — rendered in
a small off-screen 3D `SubViewport` and composited into the pedestal region. This is the true D4
inventory approach (an actual lit hero on a pedestal) and it proved stable under software Vulkan
(lavapipe), so there was no need to fall back to Option A.

### How it works (all inside the `Screen` inner class)
- `_ensure_stage()` builds the stage **once** (guarded by `_stage_tried`):
  - a `SubViewport` (420×720, `transparent_bg`, `own_world_3d`, `render_target_update_mode =
    UPDATE_ALWAYS`, `MSAA_2X`) so it renders every frame independent of the gameplay world;
  - its own **camera** (fov 30, slight low hero angle, full-body framing with headroom + floor);
  - its own **lights**: warm broadcast **key** (front-upper-right, models pecs/abs/delts), a strong
    **cyan rim** (behind-left-above, carves the heroic edge off the dark well), a cool **fill**, and
    a warm **up-light** OmniLight from the pedestal catching the underside of the beard/pecs;
  - an ACES `Environment` with cool ambient + gentle bloom (`glow_hdr_threshold 0.95`) so only the
    emissive axe / red-heart print bloom, not the skin;
  - a fresh `KarlPlayer` (loaded via `res://scripts/player.gd`), `build()`, posed idle.
- **Idle-pose fix:** `KarlPlayer.build()` ends with `set_state("idle")` while `_state` is already
  `"idle"`, so its guard no-ops and NO clip plays — the rig freezes in the rest **T-pose** (this is
  exactly what the first capture showed). We force a real transition `set_state("move")` →
  `set_state("idle")` so the idle clip actually starts (arms down, relaxed, subtle breathing).
- **Facing + framing:** the rig's front is `+Z`; base yaw `0.0` faces the pedestal camera, with a
  framerate-independent absolute-time yaw sway `sin(t*0.45)*0.42` (~±24°) so EVERY captured frame
  reads as a heroic front-3/4 statue, never his back.
- **Compositing:** in `_pedestal()` the back crystals draw first, then the viewport texture
  (`draw_texture_rect`) so the rig sits over the dark well, then the FRONT crystals + pedestal discs
  draw on top — correct depth ordering, crystals orbiting in front of and behind him.
- **Fallback preserved:** if the rig fails to build (no `Xbot.glb`, no skeleton), `_stage_ok` stays
  false and `_pedestal()` falls back to the original drawn `_carl()` statue. A flaky viewport can
  never leave the pedestal empty. The drawn `_carl()` and all its helpers are kept intact.

### Tuning notes
First render was blown-out pale (skin clipping to white, red hearts washed out). Dialed the rig back
to a bronze lit-statue read: key 0.86, rim 2.3, fill 0.40, up 0.5, ambient 0.26, exposure 0.72.
That restored pec/ab shadow modeling and brought the red heart print back on the boxers.

## Before / after
- Before (mannequin): `captures/gd/coh7e/shot_03.png`
- After, front:        `captures/gd/pedestalB/inv_front.png`
- After, 3/4 hero:     `captures/gd/pedestalB/inv_3quarter.png`
Confirmed rendering from the real repo build (not just the lab), no parse errors.

## Honest read vs the D4 bar
The pedestal is now a genuine muscled, bearded, barefoot Carl in heart boxers, holding his cyan
double-bit axe, standing on the lit pedestal with crystals orbiting in front and behind — lit with a
warm key and cyan rim like a broadcast statue. It is unmistakably the in-game hero, not a tailor's
dummy. This clears the mannequin bar decisively and reads as a real Diablo-IV inventory pedestal.

**Self-score for the pedestal figure: 8.5/10** (was ~4/10 as a mannequin).

### Residual gaps
- The **red heart print** on the boxers reads clearly at the 3/4 angle but is subtler head-on
  (bright frontal cloth). Can't push it further without editing `player.gd`'s cloth material.
- The **axe head** glows cyan but blooms modestly under lavapipe; a touch more emissive punch would
  need a material change in `player.gd` (out of scope — only `screens.gd` edited here).
- Micro-shadow contrast on the skin is good but slightly softer than a hero-portrait ideal; the
  single warm key keeps it broadcast-clean rather than dramatic.

## Constraints honoured
- Only `screens.gd` + this report + after-frame PNGs written. `game.gd`, `player.gd`, other modules,
  and the rest of `screens.gd` (tabs/grid/stats/currency/char sheet) untouched. Opaque scrim +
  `_occlude()` cohesion fix intact. No git run.
- GDScript: all locals explicitly typed (no Variant-inferred `:=`); animation is framerate-independent
  (absolute-time yaw sway); `SubViewport` uses `UPDATE_ALWAYS` with its own lights and verified to
  render content (not black) in capture.
