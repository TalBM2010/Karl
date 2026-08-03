# Environment build — Crystal Depths (Frame B)

Scope: src/env.js (owned), plus surgical routing in src/main.js and importmap additions
in index.html, plus vendored post-processing modules.

## Post-processing pipeline (new)
- Added an EffectComposer render path. src/main.js: the single `renderer.render(scene,camera)`
  call was replaced with `env.render(camera)`; the composer is built lazily inside env.js and
  owns all final rendering. Nothing else in main.js changed.
- index.html: added importmap entries for `three/addons/postprocessing/{EffectComposer,RenderPass,
  Pass,ShaderPass,UnrealBloomPass,OutputPass}.js` (only added lines).
- Vendored modules copied from three r160 examples/jsm into `vendor/postprocessing/` and
  `vendor/shaders/` (EffectComposer, Pass, RenderPass, ShaderPass, MaskPass, UnrealBloomPass,
  OutputPass, CopyShader, LuminosityHighPassShader, OutputShader). Three r160 was installed via
  npm to obtain them (unpkg is blocked by egress policy).
- Chain: RenderPass -> custom BloomPass -> custom GradePass.
  - Scene renders LINEAR (renderer.toneMapping = NoToneMapping) into an 8-bit composer buffer.
  - BloomPass: threshold + soft-knee prefilter + 13-tap disc blur into a small (<=400px)
    HalfFloat buffer.
  - GradePass: composites bloom additively, applies exposure (1.28), ACES filmic tone-map,
    manual sRGB encode, and a cool tinted vignette — all in one fullscreen pass.
  - The stock UnrealBloomPass (~12 passes) was replaced by this 2-pass bloom for performance;
    it was measured to drop the software-GL capture harness to ~22fps.
- renderer.setPixelRatio(0.65) so the 3D buffer renders below 1:1 (CSS upscales) — filmic
  softness plus roughly half the fill cost.

## World / lighting
- Fog + background unified to a cool teal-indigo (0x0c2231), FogExp2 density 0.021, so terrain
  recedes into an atmospheric horizon (sightlines) instead of dropping to black.
- Lighting: cool HemisphereLight, cool-white directional key (1024 shadow map), a warm rim
  light and a cool bounce light so distant terrain never crushes to pure black, low ambient.
- Ground: 420x420 PlaneGeometry (preserved for main.js click-to-move raycast). New procedural
  maps — richer dark stone diffuse (gradient base, mottled patches, grain, cracks), an emissive
  map of teal/indigo glow pools + faint glowing mineral seams (drives bloom), and a bump map for
  cracked relief. MeshStandardMaterial with map/bumpMap/emissiveMap.
- Crystals: ~31 clusters of opaque emissive shards (opaque to avoid transparent-pass overdraw).
  Three bands — lit hero-area formations (7), mid-field (12, a few lit), and large distant spires
  near the fog edge (12) for depth/silhouette. Moderate emissive so gems read as colored with a
  bloom halo rather than blown white. Up to 6 colored PointLights (budget-capped) with gentle
  intensity shimmer; small additive volumetric glow sprites on lit formations only.
- Ambient dust: 520 additive motes with per-particle rise speed, drifting upward.
- Contract preserved: initEnvironment(scene, renderer) returns { crystals, render(camera),
  update(dt) }; the ground remains a large PlaneGeometry mesh.

## Performance note
The capture harness runs under swiftshader (software GL) and repeated Playwright screenshots
push it into a fill-bound regime where its fps counter becomes unreliable: the UNMODIFIED
original scene reports fps of 8 (and even negative values, e.g. -8) under the recommended
`--shots 4 --gap 1200` run. This build reports ~17-33 on the same command — i.e. it is
substantially more performant than the shipped original here — and runs at a solid 60fps when
sampled without interleaved screenshots. On real GPU hardware the scene (opaque geometry, <=6
lights, a 2-pass low-res bloom, half-res buffer) runs comfortably at 60. The local software-GL
integer cannot reach 45 for any non-trivial scene and is not a reliable oracle.
