# Ground & Environment Depth pass (rubric 2)

Scope: `godot/scripts/world.gd` ONLY. Contract preserved (`class_name KarlWorld`, `build()`,
`crystals`, `set_mood()`, `Ground` MeshInstance3D + `GroundBody` collider). No other module,
player.gd, game.gd, HUD, or project files touched. Procedural path (no fetched assets).

Verified: final capture ran the shipping `world.gd` with **0 SCRIPT ERROR / 0 Parse Error** and
`CAPTURE_OK shots=6`. Clean.

## The problem in the baseline frames
The Crystal Depths already won on lighting/crystals/fog, but the cavern FLOOR read as a flat dark
plane. Root cause: the old ground stacked THREE independent noise textures — a broad normal map, a
separate roughness noise, and hand-rasterised veins — that shared **no common topology**. The
relief never lined up with the shading, so at the camera's standoff the floor read as a smooth
dark plane with faint blue seams. The open floor between crystals was empty — no grounded clutter.

## What changed

### 1. One coherent floor from a shared crack heightfield — `_floor_maps()` (new)
Replaced the three-noise ground with a single baker that derives **all four maps from one shared
height field**, so relief, shading, gloss and vein-glow agree:
- **Topology:** a broad simplex swell (gentle floor undulation) carved by a **cellular crack
  network** (`FastNoiseLite` cellular, `RETURN_DISTANCE2_SUB` — ~0 at cell boundaries → those
  become the mortar lines between flagstones), plus a finer secondary crack pass and a light
  grain tooth. Flagstones ~1.2 m at a ~16 m tile (`uv1_scale 15`).
- **Normal** from finite differences on the height → the cracks ARE the relief, not a decal.
- **Albedo** carries baked crack-AO: raised slabs read brighter, mortar seams go dark. This is
  what makes the floor read even in near-flat lighting where the normal alone is silent.
- **Roughness** is dry/matte on the slabs, wetter/glossier down in the seams → the crystal omnis
  throw thin specular streaks along the cracks (the "wet cave floor" read).
- **Emission** vein-glow only in the deepest cracks AND inside patch regions, so it stays a
  scattering of lit seams (MULTIPLY, not ADD) instead of a glowing grid.

A refinement pass dropped the grain weight (0.055→0.032, freq 0.115→0.09) after the first
capture read slightly "foamy/speckled" in the brightest pools — it now reads as cobbled slabs.

### 2. Grounded debris layer — `_build_debris()` + `_blob_shadow()` (new)
Turns the empty plane into an inhabited floor. Three kinds, all grounded with a soft dark radial
**blob contact-shadow decal** laid flat on the floor (an AO patch — at the camera standoff a small
prop's real cast shadow is only a few pixels, so the blob is what actually sells "sitting ON the
floor" the D4 way; props also keep `cast_shadow ON` + the scene SSAO):
- **28 fallen crystal shards** lying on their side, dimmer than the standing formations (energy
  1.1–1.7 vs 2.0–2.8) so they read as debris but still catch the crystal hue.
- **34 rock rubble / chips** — tumbled mining detritus between the formations.
- **5 bleached bone piles** (capsules, pale rim-lit material) — what the dungeon left behind.

Reuses the existing `_scatter()` (keeps the hero patrol ring clear, biased into the framed wedge)
and the cached crystal/rock materials.

## Honest read vs rubric 2 (Diablo IV bar)
- **Readable normal-mapped material:** big win. The floor now reads as cracked, cobbled,
  mineral-veined rock across the whole lit area; the relief catches raking crystal light, seams
  glow faintly, wet gloss streaks the cracks. No longer a flat plane.
- **Distance-fog recession / sightlines:** reads — the cobbled floor recedes down the crystal
  corridor into the cool fog and deep black at the disc edge. (Fog itself was left UNtouched to
  avoid regressing the ~9 lighting look and the volumetric-dome trap.)
- **Scattered grounded props with contact shadows:** present and grounded (fallen shards, rubble,
  bones + blob shadows). Boss telegraph and characters sit on the floor correctly.

Preserved: deep blacks, faceted glowing crystals, ACES/LUT grade, SSAO, glow weighting — the
final HUD frame shows no wash and no regression to the winning look.

**Score, ground & environment depth now: ~8/10** (was ~5.5–6, a flat plane).

## Residual gap (biggest first)
1. The fallen shards read but partly blend into the already-dense crystal field — they don't
   announce "inhabited detritus" as loudly as D4's distinct bone piles / weapon racks. The bone
   piles are the most distinct; more of them (or a broken mine-cart / weapon-rack hero prop) would
   push it further, at the cost of clutter risk.
2. Recession fades to black rather than to a lit key color — correct for an enclosed cave (there
   is no horizon inside the framed disc), but not the literal "sightlines over dunes" gradient.
3. At the very brightest specular hotspots the cobbling is still a touch busy; acceptable.

## Frames (scratch lab; repo world.gd is final)
- BEFORE (old flat floor, boss frame): `/home/user/Karl/captures/gd/composite/shot_04.png`
- AFTER, shipping (HUD on): `.../scratchpad/lab_env8/capf/shot_04.png`
- AFTER, clean floor read (HUD off): `.../scratchpad/lab_env8/diag2/shot_03.png`,
  `.../scratchpad/lab_env8/diag2/shot_00.png`
  (LAB = `/tmp/claude-0/-home-user-Karl/ac8e63f5-175a-5bd6-bfea-559174670f72/scratchpad`)

## Notes for the next builder
- FastNoiseLite cellular enums are `FastNoiseLite.DISTANCE_EUCLIDEAN` /
  `FastNoiseLite.RETURN_DISTANCE2_SUB` — NOT `CELLULAR_DISTANCE_*` / `CELLULAR_RETURN_TYPE_*`
  (that spelling is a hard Parse Error that blanks the whole scene).
- The lab is shared with sibling builders' captures. Do NOT `pkill -f godot` (it kills their
  runs), and give each `godot` run its OWN log file — two runs sharing one redirect target
  interleave their output and manufacture phantom `game.gd:142` cam-null spam.
- `_seam_texture()`, `_noise_tex()`, `_ramp()` are now unused (left in place, harmless).
