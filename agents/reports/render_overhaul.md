# Render-pipeline + Environment Overhaul — Dungeon Karl

## Summary
I replaced Dungeon Karl's flat, custom fullscreen-grade look with a real AAA-style render
pipeline built around **image-based lighting** and a **standard three.js post stack**, exactly
mirroring the proven `test/assettest.html` approach. A new `src/render.js` bakes
`RoomEnvironment` into a PMREM cube for `scene.environment`, so every PBR MeshStandard/Physical
surface now receives true ambient reflections, then runs `RenderPass → UnrealBloomPass (0.6 /
0.5 / 0.8) → OutputPass (ACES tone-map + sRGB) → FXAA → Vignette` through an `EffectComposer`
(HalfFloat HDR buffer). `src/env.js` was upgraded under that IBL: the ground gained a real
normal map + spatially-varying roughness map (derived from its height canvas) with mild
metalness so wet crack seams catch the environment; crystals became `MeshPhysicalMaterial`
faceted gems (clearcoat + sheen + strong envMap reflections + ior 1.7); and 46 grounded,
shadow-casting boulders now populate the floor for real depth/contact-shadow cues. `src/main.js`
was rewired at exactly three points (import, `const rp=initRender(...)`, `rp.render()` in the
loop, and `rp.setSize` in the resize handler) — no gameplay/animation/input/camera logic
touched. The result is a markedly moodier, higher-contrast, grounded Crystal Depths that reads
as a real place, with tasteful bloom on emissives instead of a washed frame.

## What changed
- **`src/render.js` (new)** — `initRender(renderer, scene, camera) → { render, setSize, dispose }`.
  Owns tone-mapping (ACES via OutputPass only — no double grade), IBL (`PMREMGenerator` +
  `RoomEnvironment`), and the composer stack. Renders the 3D buffer at a 0.72 resolution scale
  to stay lean under the capture's software GL.
- **`src/env.js`** — removed the old EffectComposer/BloomPass/GradePass and all renderer
  tone-map/pixel-ratio setup (now render.js's job). Added ground normal + roughness maps,
  `MeshPhysicalMaterial` crystals, and grounded rock props. Dialed fill lights down slightly so
  IBL + bloom carry contrast.
- **`src/main.js`** — render wiring + resize only.

## Hard contracts preserved (verified)
- `initEnvironment` still returns `{ crystals, update(dt) }`; crystal child meshes keep
  `material.emissive` **and** `material.color` — floors.js retints them (confirmed: Floor 1
  orange, Floor 2 green, Floor 3 white all render).
- `scene.fog` stays a `FogExp2` (live `.density`) and `scene.background` a tintable `Color`.
- Ground remains one large `PlaneGeometry` mesh with `emissive`/`emissiveMap` intact — main.js
  click-to-move raycast and floors.js ground retint both still work.
- Additive VFX (damage numbers, sparks, loot beams, boss weapon glow) read and are enhanced,
  not washed, by the tuned bloom threshold (0.8).
- Camera logic untouched — boss pull-back framing still works.

## Verification (all captures `"errors": []`)
Ran the required `node tools/capture.mjs --out captures/overhaulA --shots 6 --gap 1100 --strip
12 --stripgap 160` — completed well within budget, `errors:[]`, ~25fps under software GL,
combat live (kills incrementing). A clean gameplay frame (`captures/overhaulB/strip_06.jpg`)
shows the Juicer boss properly lit by IBL, glossy crystals blooming tastefully, grounded
boulders adding depth, and the moody vignette framing the hero.
- **Floors** — intros + retints for The Crawl / The Bramble / The Iron Tangle all render.
- **Combat** — damage numbers (aether purple / physical), hit sparks, dust, kills.
- **Boss** — the Juicer body, top health bar, affix pips, camera pull-back.
- **Loot** — rarity beams, loot-box open flourish, RARE/LEGENDARY reveal ceremonies, auto-claim.
- **Screens** — `C` opens the full Character Dossier (OFFENSE/DEFENSE/UTILITY, equipment,
  Paragon, play-time); `errors:[]`.

## Performance note / tradeoff
Real `transmission`/refraction on crystals was deliberately **not** used: a single transmissive
material forces three's per-frame transmission scene pass, which is prohibitively slow under the
capture's software GL and risked the timeout contract. Instead the gems use clearcoat + sheen +
strong IBL reflections (ior 1.7) to read as refractive without that cost. SSAO/GTAO was likewise
left out for the same reason — grounding/contact depth is delivered by the directional shadow map
plus the new shadow-casting rock props, which is cheap and holds up in the captures.
