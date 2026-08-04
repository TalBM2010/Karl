# Godot characters — Carl + the creatures

Owned files: `godot/scripts/player.gd`, `godot/scripts/modules/enemies.gd`. Nothing else touched.

## Method
The real capture runs at ~2 fps under lavapipe, and game.gd's follow camera lags per-frame, so at
that framerate Carl drifted off the bottom of frame — unusable for judging a character. I built a
throwaway **character lab** in the scratchpad (`scratchpad/lab/`, a tiny Godot project that
symlinks `player.gd` / `enemies.gd` and the assets, with a rock-steady camera and named framing
modes: `front / face / legs / iso / spider / donut / boss / wide`). That cut the critic loop from
~40 s to ~11 s and let me look at faces and silhouettes close up. The repo scene was used for
final verification only.

## Carl
- Xbot.glb still drives real skeletal animation (idle/run + the layered chop). On top of it sits a
  **muscle suit**: ~55 sculpted volumes on `BoneAttachment3D` nodes — pecs, delts, traps, lats,
  biceps/triceps, forearms, a 3x2 ab block, obliques, glutes, quads, calves — each paired with
  thin dark "crease" slivers that read as the cut between bellies. Plus `BROADEN` on the model
  scale for a heavyweight V-taper.
- Everything is authored in **skeleton rest space** (i.e. sculpting on the T-pose) and converted
  to bone-local via `_gr(bone).affine_inverse()`, so no code guesses a Mixamo bone axis. All sizes
  are multiples of `_u` (shoulder-joint span), so it survives any rescale of the .glb. Two traps
  cost me a cycle each and are now documented in the file: the rig is in **centimetres** while the
  mesh AABB is in metres, and the head furniture must be sized in skull radius `hr`, not `_u`.
- Head: dark swept-back hair, heavy brow, deep-set eyes with glints, nose, and a full dark beard
  built as jaw + chin + cheeks + moustache, all anchored *below* the nose so it frames the face
  instead of swallowing it (first attempt was a black mask).
- Boxers: a fitted trunk + waistband + a loose tube down each thigh with a hem ring, so it reads
  as shorts with leg openings. White cloth with a **procedurally generated red-heart print**
  (implicit heart curve baked to an ImageTexture, deliberately dark red so the hearts survive
  the highlight clipping on white cloth).
- Axe: a real double-bit silhouette from an extruded lens-section blade mesh (flat normals, sharp
  rim). It is **not** parented to the hand bone — a Mixamo hand tumbles through a run cycle and
  took the axe with it (head at the ground, blade across the face). It now lives in character
  space, tracking the fist's position with an authored carry orientation, and the chop drives the
  arc explicitly (windup → strike → follow-through → recovery). Emission tuned down from a
  blown-out white flare to a saturated cyan.

## Creatures (`enemies.gd`)
- **Princess Donut** — Fox.glb rescaled to ~0.55 m and re-dressed as a cream Persian: fluffy ruff,
  flat muzzle, ears, nose; and a five-point **glowing golden crown** with a violet gem, held level
  each frame against the fox's rolling head bone. She heels at Carl's left-rear with a bob, plays
  the fox walk clip, and carries a "Princess Donut ⟨8⟩" plate.
- **Crystalline arachnids** (5) — built from a flat-shaded `_unit_shard` ArrayMesh so every facet
  catches light like a real gem. Reared abdomen, dorsal spines, fangs, six emissive eyes, a violet
  emissive core (2 of them carry an omni light, for the light budget). Eight legs built from
  *connected endpoints* (hip → knee up-and-out → foot on the floor) so the armature can't come
  apart — the first version placed meshes and pivots independently and read as scattered plates.
  They encircle the hero on assigned arcs (rather than piling into one blob), skitter, and cycle
  their legs.
- **The Juicer** — 8.9 m, ~3.7x Carl. Trunk legs, huge quads, a rib cage/lat/pec mass, absurd traps
  swallowing the neck, and a **tiny angry head** with glowing red eyes poking out above them. Arms
  forced out wide with bulging veins. **MUTANT WHEY** jug (Label3D text on the drum) in his left
  fist, four glowing-green syringes jabbed into his back. Matte flushed flesh with dark crevices
  between muscle groups so he stops reading as stacked balloons. He lumbers in, holds at ~9.5 m
  (any closer and an 8.9 m hulk falls straight out of the game's fixed iso frame), and runs a
  telegraph → slam → recover cycle with an expanding red ground ring, arm rear-back, and a red
  light flash.
- Every creature gets a billboarded nameplate + level + tiny health bar.

## Result
Capture is clean (no SCRIPT ERROR / parse errors) and a 3-shot run takes ~38 s, inside the budget.
Carl reads as a muscular bearded barbarian in white heart boxers with a glowing cyan axe; Donut is
an unmistakable crowned cat at his heel; the arachnids surround him with real threatening
silhouettes; the Juicer dwarfs him.

Final capture: `captures/gd/chars_final/`  (lab close-ups: `scratchpad/out/h_*`, `out/y_front`)
