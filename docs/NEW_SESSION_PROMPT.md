# Prompt for a fresh session

Copy everything between the rules into a new session on this repo.

---

Build **Dungeon Karl** — an action-RPG that takes Diablo IV's gameplay and look and sets it in the
world of *Dungeon Crawler Carl*: Carl in heart-print boxers, Princess Donut the crowned talking cat,
the whole thing broadcast live to billions of aliens as the "Galactic Observation Protocol". Follow
the books' order for levels, character building, loot boxes, reward mechanisms and boss battles.

**The bar is Diablo IV itself.** Compare against it constantly — and not only on stills. Ours has to
hold up in motion: dust, scale, sightlines, the weight of commanding a battle.

## Method (this is the part that matters)

Split the goal yourself into the smallest pieces that can be improved and judged independently, and
run them in parallel wherever it makes sense. For each piece, fan out a **builder** subagent and a
separate **critic** subagent with fresh context. The critic never sees the builder's reasoning or
history: it launches the real build, plays it, captures screenshots and clips, and sets those beside
the reference as two unlabeled candidates to pick the better one. Generated assets get judged **in
the scene**, never as isolated renders, and never as a written description of the work. When ours
loses, the critic names the single biggest remaining gap and sends it back.

Keep looping until ours wins or I stop you. No fixed number of rounds.

After each major wave, send **one fresh agent across the whole game** to smooth out inconsistencies
between separately improved parts — this is not optional, it's where the biggest regressions get
caught.

Keep a **live HTML page** updated as you work so I can watch progress from my phone without
interrupting you. Use subagents. Commit and push as you go.

## Where the project already is

The repo has **two working builds**. Read `docs/BUILD_STACK_RESEARCH.md` first, then:

- `godot/` — **the current build. Godot 4.3, Forward+.** World (Crystal Depths), rigged Carl,
  Princess Donut, crystal arachnids, the Juicer boss, full broadcast HUD, combat VFX. Scored ~9.3
  against the reference frames.
- `src/` + `index.html` — the earlier three.js build. **Keep it working as a reference to beat.**
  It still has systems Godot lacks: loot beams + the System loot-box opening ceremony, floor
  progression (The Crawl → The Bramble → The Iron Tangle) with System floor-intro screens, and the
  inventory + character-sheet screens. **Porting those into Godot is the top outstanding work.**
- `reference/rubric.md` — the measurable Diablo-IV targets, written out because subagents cannot see
  the reference images. Keep it updated.
- `agents/reports/*.md` — what every previous builder did and the traps they hit. Read before editing.
- `progress/state.json` + `tools/progress.mjs` — the live page. Regenerate and republish each wave.

## Toolchain that is already proven here

```bash
bash tools/setup_godot.sh      # Godot 4.3 + software Vulkan (lavapipe) + xvfb check
bash tools/gd_capture.sh --out captures/gd/foo --shots 4 --gap 14 --warm 16 --strip 6 --stripgap 5
node tools/shrink.mjs 1100 captures/web <pngs...>   # downscale for the phone page
```

Godot renders **Forward+ on software Vulkan under Xvfb** — SSAO, volumetric fog, glow, ACES, real
shadows — and a full capture cycle takes ~15–40s. The capture agent (`godot/scripts/capture.gd`)
waits on **rendered frames**, not wall-clock, so results stay deterministic at ~2–8fps.

## Hard-won gotchas — do not rediscover these

1. **GDScript:** `var x := load(...)` or any Variant-inferred `:=` is a **hard parse error**, and a
   parse error in the main scene means *nothing renders at all* (this once looked exactly like a
   9-minute performance hang). Always `var x: Type = ...`; use `minf/maxf/clampf/lerpf` on floats.
2. **Godot materials:** `emission_operator` defaults to **ADD**, which applies emission across the
   *entire* surface. This single default caused both a full-screen blue wash and "flat neon slab"
   crystals. Set it deliberately.
3. **Godot glow:** the wide glow levels (4–6) are a 1/16–1/64-res blur; left at full weight they
   smear every small emissive into a screen-wide colour cast. Weight the levels explicitly.
4. **Volumetric fog:** a directional light scattering into it renders as a uniform dome over the
   whole frame that swallows geometry. Zero out `light_volumetric_fog_energy` on directionals.
5. **Framerate-dependent lerp:** raw per-frame lerp weights are a ~2-second time constant at 8fps —
   the hero literally outran his own camera. Use exponential decay on `delta`.
6. **Mixamo rigs:** bones are in centimetres while the mesh AABB is in metres; a bone's world scale
   is ~0.01× what you'd expect. Author accessories in skeleton **rest space** and convert.
7. **Module isolation:** `game.gd` loads optional modules from `godot/scripts/modules/`; each one is
   fault-isolated so a broken script can't take the others down. Keep that property.
8. **Additive VFX over ACES + bloom** clip to white the instant two overlap. Budget one big effect at
   a time — abilities should punctuate a Diablo IV frame, never erase it.
9. **Parallel agents on one engine collide.** Give each builder its own file, and tell it to build a
   throwaway "lab" project (pinned known-good copies + a symlink to its live file) if it needs a fast
   or isolated iteration loop. Two previous builders did this and cut cycles from 40s to 11s.
10. **Judge composites, not pieces.** Every builder that tuned its piece in isolation produced
    something that fought the others. Always capture the full frame before declaring a win.

## Stack upgrades worth making (details and sources in `docs/BUILD_STACK_RESEARCH.md`)

- **Bespoke characters** — replace the Mixamo mannequin + hand-built muscle suit with a purpose-made
  Carl/Donut/Juicer from **Tripo** (quad topology, auto-rig) or **Rodin** (top fidelity), rigged via
  AccuRIG/Mixamo, with hero attack moves hand-crafted in **Cascadeur**. Biggest single visual win left.
- **Environment/materials** — **Poly Haven** and **ambientCG** are CC0 (no attribution, 4K/8K PBR +
  HDRIs). Only `raw.githubusercontent.com` is reachable from this container, so mirror what you need
  via `tools/fetch_assets.mjs` and commit it.
- **Audio** — none exists yet. **ElevenLabs SFX** for impacts/UI/magic, **ElevenLabs Music** or
  **Stable Audio** for the broadcast score (paid tier = commercial rights; free tier is not).
- **Real-framerate verification** — software Vulkan can't tell you whether the game actually runs
  well. If a GPU runner is available, use it for true fps and motion capture.

## One important constraint

*Dungeon Crawler Carl* is **actively licensed** — Renegade Games (tabletop), Peacock/Universal (TV),
Maximum Orbit (merch), plus an existing official game. Treat this as a **private prototype**. Don't
publish, distribute or promote it. If it should ever go public, keep the mechanics and reskin to
original IP; flag that to me before doing anything public-facing.

## How to report

Tell me what genuinely holds up against Diablo IV and what doesn't, with real captured frames — not
adjectives. If a piece loses, say so and say why. I'd rather have an honest 8 than a claimed 10.

---
