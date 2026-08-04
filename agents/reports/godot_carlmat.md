# Carl material refinement — heart boxers + glowing cyan axe

Scope: two materials in `godot/scripts/player.gd`, nothing else. No proportions, rig,
muscle suit, beard, skin, stance touched.

## 1. Heart-print boxers (`m_cloth` + `_heart_textures()`)

**Root cause:** `emission_operator` was left at its default `ADD`. With an emission
*texture* set, Godot emits `emission_colour * energy + texture` — the base emission
`Color(1,1,1) * 0.45` was added across the ENTIRE short, flooding it to white and
burying the hearts as faint pink smudges. (Same trap `world.gd` calls out on its floor
seams, which already use MULTIPLY.)

Changes:
- `emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY` — confines emission to the
  heart mask instead of the whole surface. This is the primary fix.
- Emission texture is now a **white-on-hearts mask** (was red-on-hearts); the material
  carries the red via `emission = Color(0.85, 0.07, 0.10)` at `energy 0.85`. Under
  MULTIPLY the hearts self-light to ~0.6 red — enough to hold under strong key light,
  below the 0.95 glow threshold so they don't bloom.
- `albedo_color 0.90,0.89,0.86 → 0.76,0.72,0.70`: light off-white, not near-white, so the
  cloth no longer clips under ACES and the hearts have real contrast.
- Heart albedo `0.40,0.022,0.06 → 0.52,0.028,0.055`: a cleaner, more saturated red that
  reads at gameplay distance.

## 2. Cyan energy axe (`m_energy` + omni glow)

Goal: a genuine "big glowing blue axe" (rubric 4) without blowing to white.

- `emission = 0.02,0.55,1.0 → 0.0,0.52,1.0`, `energy 0.85 → 1.5`. Blue peak 1.5 sits well
  above the 0.95 glow HDR threshold so the blade actually blooms; green kept moderate and
  **red pinned at 0** so bloom can only smear cyan — it can never average toward a white
  blob no matter how hot. (An earlier 0.60/1.6 pass read slightly white-hot at the front
  angle; dialling green/energy down restored a saturated-cyan core.)
- Omni fill light nudged `energy 1.4 → 1.8`, `range 2.6 → 2.9` for a slightly larger local
  halo (local light, not global glow — global glow untouched).

`emission_operator` on the axe stays default ADD, which is correct here: no emission
texture, so the whole blade is meant to glow uniformly.

## Verification (isolated lab, 9 shots @ gap 20, 1600x1000, lavapipe)

No `SCRIPT ERROR` / `Parse Error`. Checked both contexts.

Before:
- Pedestal: `captures/gd/pedestalB/inv_3quarter.png` (blown-white shorts, modest pale axe)
- Gameplay: `captures/gd/coh7e/shot_05.png`

After (lab render `scratchpad/lab_carlmat/cap2/`):
- Pedestal close-up: `cap2/shot_03.png`, `cap2/shot_02.png` — hearts are unmistakable bold
  red hearts on a light short; axe blade glows cyan with a clean bloom, silhouette intact,
  core stays cyan (not white).
- Gameplay: `cap2/shot_05.png` — Carl small near the boss; a red heart still reads on the
  boxers at distance, nothing blows out, rest of Carl unchanged.

## Honest read
- **Boxers: 9/10.** Signature red-heart look is now obvious close-up and still registers in
  combat. Only nit: at extreme gameplay distance the hearts compress to a red patch rather
  than distinct hearts, which is expected and fine.
- **Axe: 8/10.** Clearly a glowing cyan axe that blooms tastefully; safely not a white blob.
  Could push the halo marginally bigger, but that risks the white-clip the brief warns about,
  so it's held at a saturated, safe level.
- No regression to the in-game Carl.
