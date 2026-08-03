# Combat Abilities — build report

**File owned/created:** `src/abilities.js` (only this file; no other source edited).

**Loader edit needed?** No. `main.js` already auto-loads `'abilities'` (its list is
`['loot','boss','screens','abilities']`), so the module registered via `export function init(api)`
with no `main.js` change. Per the coordinator's clarification I did **not** touch the list (adding it
again would double-fire every ability).

## What was built
A Primal-Warrior ability system driven off `window.__KARL`. Abilities auto-fire in a staggered
rotation while combat is live (nearest live enemy < 9u or `hero.target` set), each on its own
cooldown, each with a big additive cyan/aether VFX centered on Carl or his target:

- **CLEAVE** (L-Click slot) — wide cyan crescent that sweeps in front of Carl, triggered on the
  rising edge of the real melee swing (`hero.swing`), so it syncs to the axe chop.
- **AETHER NOVA** (slot "3") — expanding purple ring shockwave; flashes + shows `damageNumber`
  (aether) + hit-sparks on every enemy within 5.6u, plus camera shake.
- **WHIRLWIND** (slot "4") — Carl wreathed for ~1s in a fast-spinning ring of 12 additive
  blue/cyan energy blades over a trailing ground ring.
- **AETHER BOLT** (R-Click slot) — glowing aether projectile that streaks from Carl to the current
  target with a trail, then bursts (spark + flash + damage number + shake).
- **WAR CRY** (Q slot) — radiant ground rune (canvas rune texture) that blooms outward + an upward
  cyan light pillar under Carl.
- **AETHER AURA** (persistent) — two faint counter-rotating cyan/aether rings + a soft glow disc
  that always follow Carl and pulse, so he reads as powered-up between casts (reference Frame B).

## Skill-bar cooldowns (Diablo-IV read)
Firing an ability puts its `.slot` into `cooling` and animates the shipped `.cd` conic-gradient's
`--a` (360°→0) over the cooldown, then pops a bright ready-flash. Via an injected `<style>` I
strengthened the sweep (darker wedge + glowing active border) and added a numeric countdown
(`.cdnum`) per slot for cooldowns ≥ 1.2s. Verified in-page: slots enter `cooling` with `--a`
sweeping and timers ticking (e.g. slot 4 → "4", slot 8 → "2").

## Performance / cleanliness
Textures and all effect geometries are created once and reused; per-effect materials are cloned and
disposed when the effect ends (objects removed from scene) — no leaks. Additive blending throughout,
`depthWrite:false`.

## Verification
`node tools/capture.mjs --out captures/buildG --shots 6 --gap 900 --strip 16 --stripgap 140` — every
run reported `"errors": []`. Frames show the cleave crescent, purple nova ring, whirlwind ribbons,
war-cry pillar/rune, the persistent aura ring around Carl, and live cooldown sweeps + timers on the
action bar. FPS in the headless swiftshader capture ranged 19–24 (same software-renderer band as the
pre-abilities baseline ~22); the VFX are lightweight and target 60fps on real hardware.
