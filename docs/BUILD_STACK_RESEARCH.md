# Best-in-class stack for building Dungeon Karl — research (Aug 2026)

Researched for the agent-driven build loop we've been running: a fresh session must be able to
**build, launch, play, screenshot and critique** the game autonomously. That constraint rules some
"best" tools out — an engine that needs a live GPU desktop session can't be driven by an agent here.

---

## 0. Read this first — the IP situation

**Dungeon Crawler Carl is aggressively licensed as of 2026.** This is not a dormant property:

| Right | Holder |
|---|---|
| Tabletop RPG + board games | Renegade Game Studios (official, ~$6.6M crowdfunded, fulfilling late 2026) |
| Live-action TV series | Peacock / Universal + Seth MacFarlane's Fuzzy Door (straight-to-series) |
| Merchandise licensing | Maximum Orbit |
| Pinball | In production, late 2026 |
| Video game | An official free DCC game already exists |

**Implication.** A DCC-branded game is fine as a **private prototype / personal project / portfolio
piece you don't distribute**. It is *not* something to publish, sell, or promote — that would be
infringement against active licensees. If this is ever meant to go public, the correct move is to
keep the mechanics and the "galactic broadcast dungeon" genre and **reskin to original IP** (own
hero, own companion, own boss names). Worth deciding early, because it changes asset licensing too.

---

## 1. Engine — **Godot 4.5+ (Forward+)** ✅ recommended

Validated empirically in our container: Godot 4.3 Forward+ runs on **software Vulkan (lavapipe)**
under **Xvfb**, rendering SSAO, volumetric fog, glow, ACES + shadows, capturing frames in ~13s.

- **Forward+** = clustered forward rendering, thousands of dynamic lights, SDFGI/VoxelGI global
  illumination, SSR, volumetric fog, TAA, FSR. Desktop-only; **no WebGL path**.
- Since **4.4** there's automatic renderer fallback (Vulkan → D3D12 → Compatibility).
- MIT licensed, no royalties, small install, fast iteration — ideal for agent loops.
- Known caveat: `GPUParticles3D` can be *slower* on Forward+ than Compatibility in some cases —
  budget particles deliberately.

**Why not Unreal 5?** Higher ceiling (Nanite/Lumen) but it wants a **GPU + live desktop session**;
headless/displayless rendering is far more painful. That's hostile to an autonomous agent loop —
you'd lose the critic. Choose Unreal only if you move to a GPU workstation and drop the automation.

**Why not Unity?** Fine middle ground, but no advantage over Godot here and a worse licensing story.

---

## 2. 3D characters & creatures

| Service | Best for | Notes |
|---|---|---|
| **Tripo AI** | First choice for game-ready | Clean **quad topology**, v3.0 up to 2M polys, **auto-rigging**, stylized/cartoon modes |
| **Meshy** | Polished stylized game assets | Broadest, friendliest UI; strong for props/figurines |
| **Rodin** | Absolute top fidelity | 10B-param model, 4K textures, good UVs/topology/PBR; enterprise pricing |
| **TRELLIS** | Open-source option | Self-hostable, no per-asset cost |

**Practical pipeline:** generate base mesh (Tripo/Rodin) → auto-rig (Tripo or **Reallusion AccuRIG 2**)
→ locomotion clips from **Mixamo** (free) → hand-craft hero moves in **Cascadeur** (physics-assisted
keyframing with AI auto-posing — best-in-class for punchy attack animation) → custom motion from
video via **DeepMotion/SayMotion** or **Rokoko** if needed.

> We currently use Mixamo's `Xbot.glb` + a hand-built bone-attached muscle suit. That was the right
> call with no asset budget, but a Tripo/Rodin-generated *bespoke* Carl would be a large step up.

---

## 3. Environments, props, materials

- **Poly Haven** — CC0, no attribution, 4K/8K PBR textures + **HDRIs**. Best free source, period.
- **ambientCG** — CC0, 1000+ PBR materials. Complements Poly Haven.
- **Fab** (Epic's unified marketplace, absorbed Quixel Megascans) — Megascans now largely paid, but
  **Megaplants vegetation is free** under the Fab Standard License. The old "free Megascans" era ended.
- **AI texture generation** — text→seamless tileable PBR sets in 10–60s, up to 8K/32-bit. Good enough
  for environment surfaces and props; use for the Crystal Depths/Over City floors.
- **Substance 3D** — still the professional authoring standard if you want hand-control.

---

## 4. Audio

| Need | Pick | Licensing |
|---|---|---|
| SFX (impacts, UI, magic, footsteps) | **ElevenLabs SFX** | Paid plans: you own outputs, commercial OK. **Free tier is NOT commercial-safe** |
| Ambient beds / textured layers | **Stable Audio** | Finer length/structure control |
| Music | **ElevenLabs Music** | Trained on licensed catalogs (Merlin, Kobalt deals) — cleanest terms |
| Music (highest quality) | Suno / Udio | Best output; license terms were unsettled through 2026 litigation (major-label settlements reached) — fine for private/prototype, riskier commercially |

Given §0, for a private prototype any of these work; if you ever go public, prefer the
license-clean options.

---

## 5. Automation / CI — the piece that makes agent-building work

- **Keep the in-container loop** (Godot + Xvfb + lavapipe + an engine-side capture agent) for fast
  iteration. Our capture agent waits on *rendered frames*, not wall-clock, so results stay
  deterministic at ~2–8fps software rendering.
- **Add an ephemeral cloud GPU runner** for final verification: real 60fps performance numbers,
  motion/video capture, and visual-regression diffing. Software Vulkan can't tell you if the game
  actually runs well.
- **GdUnit4** or **GUT** for logic tests; standard pattern is headless import warm-up → headless test run.

---

## 6. Recommended stack (verdict)

```
Engine        Godot 4.5 LTS, Forward+                    [proven headless here]
Characters    Tripo/Rodin base mesh → AccuRIG/Mixamo rig → Mixamo clips + Cascadeur hero moves
Environment   Poly Haven + ambientCG (CC0) + AI texture gen; Fab for set-piece props
Audio         ElevenLabs SFX + ElevenLabs Music (paid tier for commercial rights)
Iteration     in-container Xvfb + lavapipe capture loop (fast, deterministic)
Verification  ephemeral cloud GPU runner (true fps, motion capture, visual regression)
Legal         private prototype only, or reskin to original IP before anything public
```

**Biggest single upgrade over what we have now:** bespoke AI-generated + rigged characters
(Tripo/Rodin) replacing the Mixamo-mannequin-plus-muscle-suit approach, and a GPU runner so the
critic can judge *motion* at real framerate rather than inferring it from stills.

## Sources

- [Best AI 3D Model Generators in 2026: Tripo vs Meshy vs Rodin vs Kaedim](https://medium.com/ideas-with-wings/best-ai-3d-model-generators-in-2026-tripo-ai-vs-meshy-rodin-kaedim-and-more-7eea7b05eb11)
- [Best AI 3D Model Generators: TRELLIS vs Meshy vs Tripo vs Hitem3D](https://trellis2.app/blog/best-ai-3d-model-generator)
- [Godot 4.5 — Overview of renderers](https://docs.godotengine.org/en/4.5/tutorials/rendering/renderers.html)
- [Godot: Compatibility renderer outperforms Forward+ (GPUParticles3D)](https://github.com/godotengine/godot/issues/97903)
- [Godot: displayless / headless rendering discussion](https://github.com/godotengine/godot-proposals/discussions/4134)
- [Best Auto-Rig / Mixamo alternatives 2026 (Tripo guide)](https://www.tripo3d.ai/content/en/guide/the-best-auto-rig-mixamo-alternative-tools)
- [Best AI Tools for 3D Animation in 2026 (3DAI Studio)](https://www.3daistudio.com/blog/best-ai-tools-for-3d-animation-2026)
- [Quixel on Fab: Megascans and free Megaplants](https://quixel.com/news/quixel-on-fab-new-megascans-and-megaplants)
- [Quixel → Fab migration: indie survival guide](https://www.strayspark.studio/blog/quixel-to-fab-migration-indie-developer-survival-guide-2026)
- [Poly Haven (CC0 textures + HDRIs)](https://polyhaven.com/)
- [AI Texture Generator: game-ready PBR from prompts (2026)](https://www.aimagicx.com/blog/ai-texture-generator-game-development-2026)
- [AI Sound Effect Generators for Games: what actually works (2026)](https://www.summerengine.com/blog/ai-sound-effect-generator-for-games)
- [ElevenLabs commercial rights & output ownership (2026)](https://terms.law/ai-output-rights/elevenlabs/)
- [AI music licensing 2026: Suno / ElevenLabs](https://www.licenseorg.com/blog/ai-music-licensing-suno-elevenlabs)
- [Peacock orders Dungeon Crawler Carl TV series (Deadline)](https://deadline.com/2026/06/dungeon-crawler-carl-tv-series-peacock-seth-macfarlane-matt-dinniman-1236962525/)
- [Renegade Games secures DCC tabletop rights (Rascal)](https://www.rascal.news/renegade-games-secures-tabletop-game-rights-to-dungeon-crawler-carl-promising-an-rpg-and-board-games/)
- [Maximum Orbit to represent DCC for merchandise licensing](https://licensinginternational.org/news/maximum-orbit-to-represent-matt-dinnimans-dungeon-crawler-carl-for-merchandise-licensing/)
