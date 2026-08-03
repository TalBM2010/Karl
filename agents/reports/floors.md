# Floor Progression — build report

**Owner file:** `src/floors.js` (only). No other files edited.

## What was built
A Dungeon-Crawler-Carl floor progression driven entirely through the public `api` (`api.scene`,
`api.env.crystals`, `api.THREE`, `api.hero`, `api.onFrame`, `api.isAuto`) plus a couple of HUD DOM
fields and one injected overlay + `<style>`.

### 1. Floor state machine + public API
`FLOORS[]` carries per-floor data: `n`, `name`, `subtitle`, `objMain`, mood colors (`fog`, `crystal`,
`groundEm`, `groundCol`, `density`), System flavor text and viewer-reaction lines. Book order:
- **Floor 1 — THE CRAWL** — the collapsed neighborhood. Objective: *Escape the Starter Neighborhood*. Amber/ember mood.
- **Floor 2 — THE BRAMBLE** — the overgrown transition. Objective: *Survive the Bramble*. Sickly green/violet mood.
- **Floor 3 — THE IRON TANGLE** — the Over City desert set-piece. Objective: *Cross the Iron Tangle*. Dusty orange/amber mood.

The existing Crystal Depths keeps working as the base sub-level (originals are cached, not destroyed).
Exposed: `api.floors = { goTo(n), next(), current(), count }` (1-based floor numbers).

### 2. Dramatic floor-intro overlay
A full-screen `#floor-intro` System announcement styled to match the broadcast HUD (cyan/gold, sci-fi
bevels, corner filigree, LIVE dot). Shows big **FLOOR N** + floor name + subtitle, DCC System text,
three viewer-reaction chat bubbles, and a "NEW OBJECTIVE" chip. Its accent/glow retints per floor
(cyan→amber/green/gold) so the announcement matches the world behind it. Fades in, holds ~3s (longer
in capture/demo), fades out to gameplay. **Note:** deliberately *no* `backdrop-filter` blur — a
full-screen blur made the software-GL capture screenshots time out; a layered radial darken gives the
same "world dims" read cheaply.

### 3. HUD objectives
On each floor entry, `#obj-title` ← floor name and `#obj-main` ← objective. Confirmed updating in captures.

### 4. Per-floor retint (via API)
On `goTo`, target colors are computed and eased each frame in `api.onFrame` (smooth graded push, not a
cut): `scene.fog.color` + `scene.background` + `fog.density` toward the floor key color; every
`api.env.crystals` child material's `.emissive`/`.color` blended toward the floor hue (per-shard
variation preserved via cached originals); the ground plane's emissive/base color warmed/cooled; and —
the key to real distinctness — the scene's colored **PointLights** and the **HemisphereLight** are
tinted toward the floor hue (the "point-light feel" the brief asked for; without this every floor stayed
teal). Floors read clearly distinct: F1 warm ember, F2 sickly green, F3 dusty desert amber.

### 5. Auto/capture director
In `api.isAuto`: Floor 1 intro at start → Floor 2 → Floor 3, then settle on Floor 3. Timings are
stretched to the capture harness's slow software-GL cadence (each screenshot takes several real seconds;
first frame lands ~12s in), and each intro is held long enough that a screenshot reliably catches it
(F1 intro ~13s, F2 at 15s, F3 at 30s). Also: pressing **N** advances to the next floor for manual eyeballing.

## Verification
`node tools/capture.mjs --out captures/buildI --shots 8 --gap 1100 --strip 14 --stripgap 160`
→ `"errors": []`, state healthy (fps 20 under software GL, ready). Captured stills show all three
System floor-intro screens (shot_00 Floor 1 amber, shot_01 Floor 2 green, shot_04 Floor 3 gold) plus
retinted gameplay per floor with the objectives panel updating each time. A transient whiteout in one
shot is the separate `lootbox.js` module's open flourish, not this module.
