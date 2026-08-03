# Actors builder — changelog (src/actors.js)

Scope: only `src/actors.js` was edited. Animation contract with main.js preserved
(exports, userData part names, Group/pivot semantics, castShadow traverse).

## CARL (buildCarl) — was a tiny plain blob, now a big heroic barbarian (~2.4u, g.scale 1.1)
- Rebuilt as a broad-shouldered, muscular, bare-chested barbarian:
  - `torso` is now a Group (rest center y=1.5, so main.js's idle bob still works) holding
    a broad V-taper chest, traps/deltoid mass, pecs, an ab suggestion, and lat taper.
  - Readable head with dark hair cap, beard, brow tuft and eyes (`head` at ~2.15).
  - WHITE BOXER SHORTS with cuffs + ~10 emissive RED HEARTS (3-sphere heart clusters,
    emissiveIntensity 1.1) scattered across front/sides so they read from the iso cam.
  - BAREFOOT: leg groups end in simple foot boxes.
  - `legL`/`legR` are now Groups pivoted at the HIPS (y≈0.98) so main.js's `.rotation.x`
    swings them from the hip (thigh+knee+calf+foot). Was: bare meshes pivoting mid-shin.
  - `armPivotL`/`armPivotR` Groups at the shoulders (y≈1.82) with deltoid/upper/elbow/
    forearm/hand; the axe is a child of `armPivotR` and swings convincingly.
- GLOWING BLUE ENERGY BATTLE-AXE (`axe`): dark wrapped haft + glowing pommel, a double-bit
  head of two flared triangular energy bits (emissive cyan, ~3.0), a bright energy core
  (emissive ~3.6) and a blue PointLight. Seated in the right hand, canted for a ready pose.
  Reads clearly both at rest and mid-swing (bright cyan arc).

## PRINCESS DONUT (buildDonut) — crowned companion cat, more character
- Persian-ish body: fluffy body, tortoiseshell patch, big round head with cheek ruff,
  flat muzzle, cream chest ruff, ears with inner pink, green glowing eyes, pink nose,
  four paws, proud upright fluffy tail.
- GOLDEN GEM CROWN: brighter gold band (emissive 1.8) + 6 points + pink octahedron gem
  (emissive 2.4) + warm PointLight, so the crown reads as a glow beside Carl. Small next
  to the hero, clearly a companion.

## CRYSTALLINE ARACHNIDS (buildSpider) — sharper, menacing, and leaner
- Faceted (flatShading) violet crystal abdomen + cephalothorax, 3 jagged back shards
  (shared crystalGeo), two forward fangs/chelicerae, a bright predatory eye cluster (3
  emissive eyes).
- Eight sharp single-shard crystal legs (4 per side) as Groups fanned front-to-back;
  main.js drives each `leg.rotation.x` for the crawl.
- `userData = {legs, mat}` kept; `mat` is the body MeshStandardMaterial whose
  emissiveIntensity main.js raises on hit-flash.
- Leg count went 6→8 for a true spider silhouette but each leg is now a single mesh
  (was multi-segment in an intermediate pass) to keep mesh count in check across the 6+
  spawned spiders.

## Contract verification
- Exports unchanged: buildCarl, buildDonut, buildSpider.
- Carl userData: {armPivotR, armPivotL, legL, legR, axe, torso, head} — all present.
- Spider userData: {legs (array of Groups), mat (MeshStandardMaterial)} — present.
- All meshes cast shadows via `g.traverse(... castShadow=true)`.
- Capture runs clean: `"errors":[]`; walk cycle, idle bob, and attack swing all render
  (verified in captures/buildB — Carl mid-swing with glowing axe arc, spiders crawling).

## Performance note
- Capture (software/swiftshader GL) reports ~20–24 fps on the full 4-shot run. This is
  NOT from the characters: a controlled A/B with a stripped near-empty actors.js produced
  the identical ~21 fps under the same command, i.e. the fps floor is the concurrently
  evolving environment/VFX + software rendering, and the detailed actors are perf-neutral.
  Early-scene fps reads 60. No per-spider lights were added (only Carl's axe + Donut's
  crown carry a PointLight); no shadow-casting lights were added.
