# Godot world.gd — Crystal Depths visual overhaul

Scope: `godot/scripts/world.gd` only. Contract preserved (`class_name KarlWorld`, `build()`,
`crystals`, `set_mood()`, `MeshInstance3D` named `Ground` + `StaticBody3D` collider).

Final capture: `captures/gd/world1/` (3 shots, full game incl. HUD/combat modules).
Capture run: **~35 s**, well under the 90 s budget. No `SCRIPT ERROR` in the log.

## Root causes found (these caused the reported flaws, not the tuning values)

1. **`emission_operator` defaults to ADD.** Godot emits `emission_color + emission_texture`, so
   the base colour glowed across the *entire* surface and the texture only modulated on top.
   This was simultaneously the "whole frame drowning in blue" (the ground emitted uniformly) and
   the "flat neon paper slabs" (every crystal emitted uniformly, so its gradient never showed).
   Both materials now use `EMISSION_OP_MULTIPLY`.
2. **Wide glow levels smeared emissives into a full-screen wash.** Levels 4-6 are a 1/16-1/64
   res blur; at full weight they turn thin bright details into a screen-wide colour cast.
   Re-weighted to a tight halo (levels 1-4, tapering) with the HDR threshold raised.
3. **Directional lights scattering in volumetric fog** rendered as a uniform blue dome that
   swallowed all geometry. All three directionals now have `light_volumetric_fog_energy = 0`.
4. **Emission clipping past 1.0** flattened the gems: every facet saturated to the same value.
   Energies are now tuned to peak near 1.0-2.0 so facet structure survives, with glow catching
   only the hottest cores.

## Grade / environment
- ACES tonemap, exposure 0.92, white 8.0; ambient near-off (energy 0.38, cool teal).
- Per-channel 1D LUT (`GradientTexture1D`) as a filmic curve for a crushed toe with a cool
  shadow tint — real blacks without the mud that an over-aggressive curve produced.
- Vignette via a `CanvasLayer(layer = -1)` + shader `ColorRect` (Environment has no vignette);
  `MOUSE_FILTER_IGNORE` so it never eats click-to-move, and it sits under any HUD.
- SSAO for contact darkening. Exponential depth fog + low height-fog mist for the floor.
- Volumetric fog kept to a whisper (froxel grid is too coarse here to look like anything else).

## Measured and rejected
- **SSR**: +5 s per run, no visible return — floor is too rough for a coherent reflection.
  The wet look comes from the roughness map instead (glossy patches, long specular streaks).
- **SSIL**: +5 s per run, no read at this light level, and banded on large flat rock faces.

## Geometry
- `_facet_mesh()`: flat-shaded procedural solids from stacked irregular rings + an off-centre
  apex. Drives crystals (long prism, chiselled termination), stalagmites, boulders, and the
  cavern wall. UV.v = height fraction, UV.u = angle around the axis.
- Crystals: 4 deliberate depth layers (hero spires / mid field / near shards / far rim) with
  per-layer light budgets, clusters of graduated shards fanning from a dominant blade, each
  erupting from a mound of rock chunks.
- Cavern shell: a ring of near-black rock masses just outside camera reach, plus talus at the
  floor junction, so the frame closes off and reads as underground.
- Ground: dark wet stone, broad soft normal relief (the old map tiled a 5-octave noise 26x,
  which is what read as sandpaper), a second noise driving roughness, and hand-rasterised
  glowing mineral veins.

## Framing note that drove every placement
The camera is welded to `hero + (7.4, 9.6, 7.4)` at 38° FOV (~37° pitch): the top of frame hits
the ground ~29 m out, so **nothing past ~32 m is ever on screen and there is no horizon or sky**.
All depth is manufactured inside that disc, and `FIELD_BIAS` offsets the scatter down the -X/-Z
diagonal the camera actually faces — an origin-centred scatter spent half its props behind the
camera.

## Textures generated in code
`_seam_texture()` (mineral veins — ridges where noise crosses zero, patch-masked),
`_facet_glow_texture()` (per-facet emission columns × height falloff with a hot tip),
`_dot_texture()` (soft radial speck; a bare quad reads as a hard grey square).
