# Loot & Drops — changelog

Scope: implemented entirely in `src/loot.js` (previously a stub). No other files touched.
Plugs into `main.js` via `init(api)` using `api.onKill`, `api.onFrame`, `api.vfx`, `api.scene`,
`api.camera`, `api.THREE`, `api.V3`. Judged against rubric section 12 (rarity beams, ground
name+type labels, loot-box open flourish, pickup pops).

## What was built

### Rarity system
- 5 tiers with book/Diablo colors + weighted rarity (higher tier = rarer, taller & brighter beam):
  Common `#c8d2d8`, Magic `#5a9cff`, Rare `#ffd54a`, Legendary `#ff8a3d`, Mythic `#e5484d`.
- Beam height (3.0 → 6.8) and intensity (0.85 → 2.25) scale with tier.

### Ground drops (on enemy kill)
- `onKill` roll: 10% System loot box, 52% normal drop, ~38% nothing (keeps the ground readable).
- Each drop spawns at the death position (`enemy.obj.position`) with:
  - A vertical **rarity-colored light beam** — additive `CylinderGeometry` with a vertical
    alpha-gradient texture (bright base, feathering to nothing at top), a brighter white inner
    core, and a soft ground light-pool disc. Bloom in `env.js` makes it glow.
  - A **small item mesh**: coins pile / weapon (handle+head+spike+gem) / gem (octahedron+ring) /
    armor plate — `MeshStandardMaterial` with rarity-tinted emissive; bobs and slowly spins.
  - A **floating DOM label** (name + type sub-label), rarity-colored with a full black outline +
    shadow so it reads over the dark scene.
- Drop types: 22% gold pile ("1,086 Gold" / CURRENCY, gold styling + gold beam), else
  weapon/gem/armor. On-theme name tables: "Stinger of Xy'Rathul", "Mongo's Prized Rock",
  "Aetherwrought Cleaver", "Gravebite", "Soulstone", etc., with class sub-labels
  (e.g. "Legendary Spiked Club").

### System loot boxes
- Floating metal cube (`BoxGeometry` + banding + glowing octahedron lock), 4 tiers Bronze/Silver/
  Gold/Platinum with matching metal color + emissive glow (bronze common → platinum rarest).
- Slow spin + hovering bob + pulsing lock glow; a pre-pop shiver as anticipation.
- After ~1.4–1.9s **pops open**: `vfx.killBurst` (shards + flash) + `vfx.spawnHitSpark` + a
  camera shake, then ejects a ground drop whose rarity is biased upward by box tier.
- Label reads "Silver Loot Box / SYSTEM · SEALED".

### Auto-collect + cleanup
- Idle for ~3.4–4.8s, then **collect**: item lifts, spins up, shrinks & fades; beam collapses into
  the ground; the DOM label streaks toward the loot orb (bottom-center of screen) and fades; a
  `spawnHitSpark` pickup pop lands. Everything is then removed.
- Full cleanup: `scene.remove` + geometry/material dispose on every mesh (shared beam/disc geos and
  the two shared canvas textures are pooled and never disposed), and the DOM node is removed.
- Concurrency capped at 8 (`MAX`); when exceeded the oldest idle drop is force-collected — no leaks.

### DOM
- Own layer `#karl-loot` (z-index 12, `pointer-events:none`) appended to `document.body`, styled via
  an injected `<style>` (`#karl-loot-style`). Idempotent — safe against a double `init`.

## Verification
- `node tools/capture.mjs --out captures/buildD --shots 6 --gap 1100 --strip 12 --stripgap 160`
- `capture.json`: `errors: []`. FPS ~26 in the SwiftShader software renderer — in line with other
  full-scene captures (cohesion 23, buildA 24, smoke 21); no regression.
- Captures show rarity beams (white/blue/gold/orange), ground labels (e.g. "Gravebite / Magic War
  Pick", "Soulstone / Legendary Crystal", "1,086 Gold / Currency"), gold coin piles, and a
  "Silver Loot Box / System · Sealed" that pops with a shard flourish.
