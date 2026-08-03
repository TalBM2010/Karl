# System Loot-Box Opening Ceremony — build report

**File owned/edited:** `src/lootbox.js` only (was a stub). No other files touched. No git commit/push.

## What it is
A self-contained DOM/CSS/Canvas broadcast overlay (`#karl-lbx`, z-index 30 above the HUD) that stages
the Dungeon-Crawler-Carl reward-reveal ritual. Injects its own `<style>`, builds a persistent fullscreen
`<canvas>` for the particle burst, and constructs per-ceremony DOM that is fully removed on dismiss.

## Ceremony sequence
1. **Present** — dark radial veil fades in; banner `◈ THE SYSTEM IS PLEASED TO PRESENT ◈` + tier line
   (`BRONZE/SILVER/GOLD/PLATINUM LOOT BOX · SYSTEM REWARD CACHE · SEALED`); the metal box (CSS-beveled
   face, corner rivets, glowing cross seams, rotated lock gem) floats center with a tier-colored glow.
2. **Charge** (~1.6s) — box shakes with a quadratically-ramping jitter, seams brighten/thicken, a
   rarity-colored radial light-leak grows behind it, the lock pulses, and hype subtitles cycle
   ("The crowd holds its breath…", "Trillions of viewers lean in…", …).
3. **Burst** — quick white screen-flash punch (0.32s), a rarity-colored shard + ember explosion on the
   canvas, the box scales up and vanishes, and `api.vfx.addShake` kicks the camera (0.4 / 0.55 / 0.7 by tier).
4. **Reveal** — a reward CARD flies up and settles (ease-out-back): SVG item icon in a rarity ring,
   item NAME, rarity label (Common/Magic/Rare/Legendary/Mythic → #c8d2d8/#5a9cff/#ffd54a/#ff8a3d/#e5484d),
   item TYPE, and 2–4 staggered stat lines (e.g. `+745 Aether Damage`, `+106% Crit Damage`).
   Legendary/Mythic get a bigger burst, rotating gold/red light rays behind the card, ★ ribbon, a red/gold
   affix line, and a floating **"!!!"** flourish.
5. **Claim** — pulsing `CLAIM` button with `PRESS O OR CLICK TO CLAIM` (or `AUTO-CLAIM` in demo), then the
   whole overlay fades and every DOM node / particle is cleaned up (verified `errors:[]`, no accumulation).

## Content & flavor
Weighted tiers (Bronze 46 / Silver 30 / Gold 17 / Platinum 7); tier biases the reward rarity upward.
DCC-flavored items (Stinger of Xy'Rathul, The Screaming Meat Tenderizer, Splinter of X-77, Bloodhelm's
Regret…) across weapon/armor/trinket classes, with rarity-scaled stat magnitudes and legendary+ affixes.
Broadcast aesthetic throughout: cyan/gold sci-fi bevels, dark glassy panels, tabular-nums, System voice.

## Triggers & API
- Press **`o`** to open manually (a second `o`/click while open speed-claims the dismiss).
- In `?auto` (capture/demo): first open ~4s after load, then ~every 9s, cycling Bronze→Silver→Gold→Platinum
  so captures reliably catch the charge, burst and reveal.
- Exposes `api.lootbox = { open(tier?), active }`.

## Verification
`node tools/capture.mjs --out captures/buildJ --shots 8 --gap 800 --strip 20 --stripgap 120` →
`errors:[]`. Captured frames show the charging gold box with light-leak, the Rare "Bloodhelm's Regret"
reveal, and the full Mythic "Splinter of X-77" reveal with "!!!", red rays, four stat lines and the CLAIM
prompt. (Base game runs ~22fps under swiftshader software-GL in the harness; the overlay adds no errors.)

## Notes / one gotcha fixed
An early build referenced an undeclared `boxGone` inside the RAF frame, which threw at the burst and left
the ceremony stuck (`active=true`) — surfaced immediately by the capture's `errors` array. Removed; the
loop now completes and dismisses cleanly every cycle.
