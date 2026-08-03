# Build E — Inventory & Character Sheet (src/screens.js)

## Scope
Owned and edited **only** `src/screens.js` (was a stub). No other files touched. No commits.
Plugs in via the existing `init(api)` auto-loader in `main.js`; injects a scoped `<style>`
and DOM overlay appended to `document.body`. Reuses the HUD `:root` custom props
(`--cyan`, `--gold`, `--panel`, `--panel-line`, `--aether`, `--cyan-dim`, `--font`).

## Controls
- `c` → toggle CHARACTER SHEET, `i` → toggle INVENTORY, `Escape` (or same key again) → close.
- Only one panel open at a time; own `keydown` listener, ignores INPUT/TEXTAREA targets.
- Semi-transparent blurred backdrop (`#ks-back`) dims the game; clicking it closes.
- Panel has `pointer-events` and a visible `×` close control (top-right).
- `?auto=1` combat keeps running behind (overlay is a sibling of the pointer-events:none HUD,
  z-index 60). Exposed `api.screens = {open, close, toggle}` for debugging.

## Character sheet (Frame D)
Title **CARL**, `LEVEL 78 · PRIMAL WARRIOR`, `◆ PARAGON TIER 4`, animated XP bar
(23,314,112 / 28,750,000 XP + "to go"). Core attributes strip: STR 1,482 · DEX 487 ·
INT 392 · WIL 612 · VIT 1,118 (each with mini fill bar). Three stat cards
OFFENSE / DEFENSE / UTILITY with all listed stats and exact values (Aether Damage tinted
`--aether`, crit/DR/CDR highlighted cyan, find/XP/health tinted gold). Central lit pedestal:
inline-SVG warrior silhouette on a glowing three-ring plinth with cyan radial light.
Row of 7 rarity-bordered equipment slots. Bottom metrics row: 124h 37m · 68,742 ·
247 · 89 / 128.

## Inventory (Frame C)
Tabbed header WEAPONS / ARMOR / JEWELRY / CONSUMABLES (active tab styled, tabs actually
swap the grid contents). 6×4 item grid: rarity borders (common grey / magic blue /
rare gold / legendary orange / mythic red) via `--rc` per-slot var, rarity top-bar,
letter rank tag, star-rank diamond pips, faux emoji icons, a few empty slots, hover lift.
Paperdoll equipment slots down both sides (armor left, weapons/jewelry right). Currency
row: Gold 52,348,772 · Platinum 8,722 · Crystals 123.

## Aesthetic
Dark glassy sci-fi bevels (corner brackets, inset cyan glow, layered gradients), cyan
accents, letter-spaced small-caps labels, right-aligned `tabular-nums` figures throughout.
Sized to fill 1600×1000 (`min(1500px,95vw) × min(940px,94vh)`), responsive grid/flex.

## Verification
- `node tools/capture.mjs --out captures/buildE_char --key c --shots 2 --gap 800` → `errors: []`
- `node tools/capture.mjs --out captures/buildE_inv  --key i --shots 2 --gap 800` → `errors: []`
- Both PNGs reviewed: panels open, complete, legible, match spec, read at the Diablo-IV bar.
