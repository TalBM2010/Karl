# Reference Rubric — "the bar is Diablo IV"

This file is the shared source of truth for every critic subagent. Critics **cannot see** the
four reference frames the user attached (they live in the chat, not on disk), so the exact,
measurable targets extracted from those frames are written out here. Judge our build's
screenshots/clips against these. The main agent additionally eyeballs our captures against the
real frames each wave.

The four reference frames (Dungeon Crawler Carl world, rendered in a Diablo-IV visual language):

- **Frame A — Boss fight (the Juicer):** underground "Pumping Pit" gym-hive. A grotesque
  steroid-swollen boss center-frame; Carl (heart boxers, glowing blue axe) small at left.
  Huge floating damage numbers ("253,884 Critical!" orange, "71,102 Physical" white, "18,650
  Blocked"). Red boss telegraph ring on the floor. Full broadcast HUD.
- **Frame B — Crystal Depths combat:** open cavern of glowing blue/purple crystals, crystalline
  arachnid enemies, Carl mid-swing, floating aether/physical damage numbers, gold pile + legendary
  weapon drop with beam, minimap top-right, objectives panel.
- **Frame C — Inventory screen:** dark UI, Carl on a rotating pedestal with crystals, grid inventory
  with rarity-bordered items, stat list, tabbed panels (CHARACTER/ABILITIES/PARAGON/CODEX).
- **Frame D — Character sheet:** full stat breakdown (OFFENSE/DEFENSE/UTILITY columns), equipment
  row, paragon tier, play-time metrics.

## Scoring — each piece scored 0-10 vs the Diablo IV bar. "Win" = our capture is judged >= the
## reference on a blind A/B, OR scores >= 8 with no single glaring gap named.

### 1. Camera & framing
- Fixed pitched top-down/isometric angle, ~30-35° above horizon, locked rotation (D4 signature).
- Character sits ~40% up from bottom, generous ground ahead for sightlines.
- Subtle follow lag + slight breathing zoom. NOT a free orbit cam in gameplay.

### 2. Ground & environment depth
- Readable material (cracked stone / sand dunes / crystal cavern per floor), normal-mapped relief.
- Real distance fog fading to the floor's key color; you can see terrain recede — "sightlines over dunes."
- Scattered props (debris, weights, crystals, bones) grounded with contact shadows. No flat empty plane.

### 3. Lighting & color grade
- Moody, high-contrast. Cool teal/indigo ambient + warm key rim on the hero. Localized colored point lights
  (crystal glow blue/purple, boss hazard red).
- Filmic tone mapping + bloom on emissives. Vignette. Deep blacks, not washed grey.

### 4. Hero (Carl)
- Clear heroic silhouette, correct scale vs enemies (boss dwarfs him ~3-4x). Heart-pattern boxers,
  bare feet, big glowing blue axe. Idle breathing + weighty run + committed attack swing with follow-through.

### 5. Companion (Princess Donut)
- Small cat, glowing crown, pads alongside Carl, name plate "Princess Donut" + level. Reads as a companion,
  not set dressing.

### 6. Enemies
- Distinct silhouettes per floor (crystalline arachnids; the swollen Juicer boss). Telegraphed wind-ups,
  hit reactions (flinch/knockback), death dissolves. Nameplate + tiny health bar + level above each.

### 7. Combat feel (the thing that must "hold up in motion")
- Impactful hits: hit-stop/screen-shake on heavy blows, flash on the struck enemy.
- Floating combat text exactly like the frames: big bold numbers, orange "Critical!" with sub-label,
  white normal, grey "Blocked", damage-type color (Aether purple, Physical white/orange). Numbers rise+fade.
- Dust kicked up on run and impact. Attack VFX arcs. Ground hazard decals.

### 8. VFX / particles
- Persistent ambient motes, dust in motion, ability particles, rarity beams on drops, crystal sparkle,
  boss rage particles. Additive glow, not muddy alpha.

### 9. HUD — orbs
- Two large spherical liquid orbs bottom corners: red HP left, blue resource right. Animated fluid surface,
  glassy specular rim, numeric "cur / max" centered, level pip between them.

### 10. HUD — skill bar
- Center action bar, 6-10 slots with distinct glowing skill icons, key hints (L-Click,1,2,3,4,Q,E,R,R-Click),
  cooldown sweep + numeric timers, a row of buff/timer pips above.

### 11. HUD — broadcast frame ("Galactic Observation Protocol")
- Top: centered title bar + node id + clock. Left: LIVE audience feed with billions viewer count (animated)
  and scrolling alien chat lines with avatars/timestamps. Right: minimap + objectives + boss/combat analysis
  panels with sparklines. Bottom: scrolling "GALACTIC CHAT TICKER". Thin sci-fi bevels, cyan glow, corner filigree.

### 12. Loot & drops
- Item beams color-coded by rarity (white/blue/purple/orange/red). Ground label with item name + type.
- Loot-box open flourish. Pickup pops to inventory.

### 13. Inventory & character sheet
- Dark tabbed panels matching frames C/D: grid inventory with rarity borders + star ranks, equipment slots,
  full stat columns (OFFENSE/DEFENSE/UTILITY), hero on a lit pedestal, currency row.

### 14. Boss battle (the Juicer)
- Top boss health bar: name, subtitle, level diamond, segmented HP with % , affix pips
  (Massive Physique / Steroid Overload / Unstoppable / Rage Pump). Phase changes, rage meter, telegraphs.

### 15. Motion & performance
- Holds ~60fps. No hitches during combat. Smooth camera, no popping. Clips (not just stills) must read as fluid.

## Content order (must follow the books)
Dungeon Crawler Carl floor order drives level progression:
- **Floor 1** — the ruined-neighborhood starter (collapsed suburbia / basements), first mobs, first loot box,
  the tutorial borough boss.
- **Floor 2** — the bramble/forest transition.
- **Floor 3** — the "Over City" / Iron Tangle desert-city, trains, bigger set-pieces.
- Boss archetypes and the broadcast-showrunner framing escalate each floor.
The vertical slice starts on Floor 1, then a Crystal Depths sub-level (Frame B), building toward the
Juicer boss set-piece (Frame A).
