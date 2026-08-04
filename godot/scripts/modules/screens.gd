extends Node
## SCREENS — INVENTORY + CHARACTER-SHEET full-screen overlays for Dungeon Karl.
##
## A code-built pair of Diablo-IV menu screens rendered in the same "Galactic Observation
## Protocol" broadcast language as hud.gd — dark glass panels, thin cyan bevels, corner
## filigree, letter-spaced small-caps, rarity-coloured item cells and star ranks. Everything
## is drawn on its OWN CanvasLayer (layer 20) that sits ABOVE the HUD (layer 10); the middle
## of the game is covered only while a screen is open.
##
## Two screens, mirroring the reference frames:
##   INVENTORY (Frame C) — tab bar (CHARACTER/ABILITIES/PARAGON/CODEX), Carl on a lit rotating
##     crystal pedestal, armour + weapon equipment columns, a rarity-bordered item grid with
##     star ranks, a compact stat list, and a currency row.
##   CHARACTER SHEET (Frame D) — name / level / paragon header with an XP bar, a 5-attribute
##     core strip, three full stat columns (OFFENSE / DEFENSE / UTILITY), an equipment row and
##     a play-time metrics row.
##
## Self-drives for capture (no player input): a ~16s demo cycle opens INVENTORY ~6–10.8s and
## the CHARACTER SHEET ~11.2–15.8s, gameplay visible otherwise — deliberately kept OUT of the
## early 0–6s window so it never fights floors.gd's floor-intro.

const DW := 1600.0
const DH := 1000.0

const CYAN := Color(0.224, 0.843, 1.0)
const CYAN_M := Color(0.224, 0.843, 1.0, 0.62)
const CYAN_L := Color(0.224, 0.843, 1.0, 0.22)
const GOLD := Color(1.0, 0.812, 0.416)
const GOLD_D := Color(0.72, 0.56, 0.26)
const AETHER := Color(0.70, 0.45, 1.0)
const RED := Color(0.93, 0.24, 0.24)
const TXT := Color(0.82, 0.90, 0.95)
const TXT_D := Color(0.58, 0.72, 0.80)
const TXT_DD := Color(0.37, 0.55, 0.63)
const PANEL_LINE := Color(0.224, 0.843, 1.0, 0.20)

# rarity: common / magic / rare / legendary / mythic  (matches hud + screens.js)
const RAR := [
	Color(0.60, 0.66, 0.70), Color(0.29, 0.63, 1.0), Color(1.0, 0.81, 0.42),
	Color(1.0, 0.54, 0.24), Color(1.0, 0.29, 0.29),
]
const RTAG := ["C", "M", "R", "L", "MY"]

var game = null
var layer: CanvasLayer
var root: Control
var inv: Screen
var chr: Screen

var t := 0.0
var _occluded := false      # true while a screen is fully open and the HUD/loot are blanked

# fonts
var f_base: Font
var f_wide: FontVariation
var f_title: FontVariation
var f_bold: FontVariation
var f_num: FontVariation
var f_huge: FontVariation

# =========================================================================
func setup(g) -> void:
	game = g
	_mk_fonts()

	layer = CanvasLayer.new()
	layer.name = "ScreensLayer"
	layer.layer = 20
	add_child(layer)

	root = Control.new()
	root.name = "Screens"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	inv = Screen.new()
	inv.mode = "inv"
	_wire(inv)
	root.add_child(inv)

	chr = Screen.new()
	chr.mode = "char"
	_wire(chr)
	root.add_child(chr)

func _wire(s: Screen) -> void:
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.f_base = f_base
	s.f_wide = f_wide
	s.f_title = f_title
	s.f_bold = f_bold
	s.f_num = f_num
	s.f_huge = f_huge
	s.visible = false

func _mk_fonts() -> void:
	f_base = ThemeDB.fallback_font
	f_wide = _fv(3, 0.0)
	f_title = _fv(6, 0.55)
	f_bold = _fv(0, 0.42)
	f_num = _fv(1, 0.30)
	f_huge = _fv(2, 0.55)

func _fv(spacing: int, embolden: float) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = f_base
	v.spacing_glyph = spacing
	v.variation_embolden = embolden
	return v

# =========================================================================
# DEMO CYCLE — open inventory, then character sheet, then hide, on a loop.
# Kept out of 0–6s so it never overlaps floors.gd's floor-intro window.
# =========================================================================
func _process(delta: float) -> void:
	t += delta
	if inv == null or chr == null:
		return

	# Screens stay closed for the first ~5s so floors.gd's floor-intro owns that window;
	# after that an 8s cycle shows INVENTORY, a gameplay beat, then the CHARACTER SHEET,
	# another gameplay beat, and repeats. Kept short so a single capture (whose accumulated
	# render-time only reaches ~12-13s) reliably lands shots on BOTH screens.
	var want_inv := false
	var want_char := false
	if t >= 5.0:
		var ph: float = fmod(t - 5.0, 9.5)
		want_inv = ph < 3.5
		# 1.5s gameplay gap (3.5–5.0) lets the inventory fully fade before the sheet opens,
		# so a shot can never catch both panels crossfading at once.
		want_char = ph >= 5.0 and ph < 8.5

	inv.open = want_inv
	chr.open = want_char
	inv.t = t
	chr.t = t

	# exponential-decay open/close — framerate independent (captures run 2–8fps)
	var k: float = 1.0 - pow(0.0008, delta)
	inv.anim = lerpf(inv.anim, 1.0 if inv.open else 0.0, k)
	chr.anim = lerpf(chr.anim, 1.0 if chr.open else 0.0, k)

	_upd(inv)
	_upd(chr)
	_occlude()

# While a screen is FULLY OPEN, blank the live HUD CanvasLayer and the loot module's world FX
# (beams / boxes / ground labels / gold / motes) so the menu reads as a clean, near-opaque
# full-screen page instead of letting broadcast HUD + 3D loot labels bleed through. Everything
# is restored the instant the panel starts closing. Threshold is symmetric on `anim` so open
# and close behave identically. Every cross-module reach is guarded with null / `in` / Dictionary
# checks — a missing or malformed sibling never crashes this module (fault isolation preserved).
# NOTE: floors.gd's intro owns the 0–5s window and never overlaps this (screens open only t>=5),
# so the HUD is only ever hidden for the menus, never under the floor-intro broadcast interrupt.
func _occlude() -> void:
	# Occlude the moment a panel is even slightly present, not only when fully open: a
	# partially-faded panel is translucent, so if the bright HUD / loot labels were still
	# behind it they would bleed through the crossfade (they did — char-sheet mid-fade).
	# With them hidden from the first frame of the open, a fading panel only ever sits over
	# the dark 3D world (which reads clean, exactly as it did in the isolated lab). The
	# threshold is well below the fully-open state and well above resting 0, so the HUD
	# restores cleanly the instant the panel has all but vanished on close.
	var fully_open: bool = maxf(inv.anim, chr.anim) > 0.04
	if fully_open == _occluded:
		return
	_occluded = fully_open
	var vis: bool = not fully_open
	if game == null or not ("modules" in game):
		return
	var mods = game.modules
	if not (mods is Dictionary):
		return
	# HUD — hide its whole CanvasLayer (boss bar, audience feed, orbs, skill bar, sector map)
	if mods.has("hud"):
		var h = mods["hud"]
		if h != null and "layer" in h and h.layer != null:
			h.layer.visible = vis
	# LOOT — hide the world-space FX root (3D ground labels, beams, boxes, gold piles, motes)
	if mods.has("loot"):
		var l = mods["loot"]
		if l != null and "root" in l and l.root != null:
			l.root.visible = vis
	# COMBAT — hide the world-space VFX root (floating damage / BLOCKED numbers, impact FX)
	if mods.has("combat"):
		var cb = mods["combat"]
		if cb != null and "root" in cb and cb.root != null:
			cb.root.visible = vis

func _upd(s: Screen) -> void:
	if s.anim < 0.004 and not s.open:
		if s.visible:
			s.visible = false
		return
	if not s.visible:
		s.visible = true
	s.queue_redraw()


# =========================================================================
# SCREEN — one full-screen overlay; `mode` selects inventory vs character sheet.
# =========================================================================
class Screen extends Control:
	var mode := "inv"
	var open := false
	var anim := 0.0
	var t := 0.0

	var f_base: Font
	var f_wide: Font
	var f_title: Font
	var f_bold: Font
	var f_num: Font
	var f_huge: Font

	var _grid: Array = []          # inventory cells
	var _seeded := false

	# ---- palette (mirror of the module constants) ----
	const CYAN := Color(0.224, 0.843, 1.0)
	const CYAN_M := Color(0.224, 0.843, 1.0, 0.62)
	const CYAN_L := Color(0.224, 0.843, 1.0, 0.22)
	const GOLD := Color(1.0, 0.812, 0.416)
	const AETHER := Color(0.70, 0.45, 1.0)
	const RED := Color(0.93, 0.24, 0.24)
	const TXT := Color(0.82, 0.90, 0.95)
	const TXT_D := Color(0.58, 0.72, 0.80)
	const TXT_DD := Color(0.37, 0.55, 0.63)
	const PLINE := Color(0.224, 0.843, 1.0, 0.20)
	const RAR := [
		Color(0.60, 0.66, 0.70), Color(0.29, 0.63, 1.0), Color(1.0, 0.81, 0.42),
		Color(1.0, 0.54, 0.24), Color(1.0, 0.29, 0.29),
	]
	const RTAG := ["C", "M", "R", "L", "MY"]

	# ---- data ----
	const CORE := [
		["STRENGTH", "1,482", 0.86], ["DEXTERITY", "487", 0.44], ["INTELLIGENCE", "392", 0.40],
		["WILLPOWER", "612", 0.55], ["VITALITY", "1,118", 0.74],
	]
	const OFFENSE := [
		["Physical Damage", "4,892", ""], ["Aether Damage", "3,112", "ae"],
		["Critical Strike Chance", "38.7%", "hl"], ["Critical Damage", "217.4%", ""],
		["Vulnerable Damage", "46.2%", ""], ["All Damage", "32.6%", ""],
		["Attack Speed", "1.18", ""], ["Overpower Damage", "72.1%", ""],
	]
	const DEFENSE := [
		["Max Health", "16,800", "gold"], ["Armor", "11,732", ""],
		["Damage Reduction", "63.2%", "hl"], ["Resist All", "58.4%", ""],
		["Physical Resist", "56.1%", ""], ["Aether Resist", "59.7%", ""],
		["Dodge", "12.3%", ""], ["Barrier Gen", "18.6%", ""],
	]
	const UTILITY := [
		["Max Energy", "1,600", ""], ["Energy Regen", "24.5/s", ""],
		["Cooldown Reduction", "24.6%", "hl"], ["Experience Bonus", "25.0%", "gold"],
		["Gold Find", "48.7%", "gold"], ["Magic Find", "62.3%", "gold"],
		["Movement Speed", "115.0%", ""], ["Mount Speed", "120.0%", ""],
	]
	const INV_STATS := [
		["Damage Per Second", "1.2M", "hl"], ["Attack Power", "4,892", ""],
		["Max Health", "16,800", "gold"], ["Armor", "11,732", ""],
		["Crit Chance", "38.7%", "hl"], ["Crit Damage", "217.4%", ""],
		["Resist All", "58.4%", ""], ["Cooldown Reduction", "24.6%", ""],
		["Movement Speed", "115.0%", ""], ["Magic Find", "62.3%", "gold"],
	]
	const METRICS := [
		["124h 37m", "Time Played"], ["68,742", "Monsters Killed"],
		["247", "Bosses Defeated"], ["89 / 128", "Areas Discovered"],
	]
	# equipment: [label, rarity idx, icon kind]
	const ARMOR := [["HEAD", 2, 3], ["CHEST", 3, 4], ["GLOVES", 1, 5], ["LEGS", 2, 6], ["BOOTS", 1, 7]]
	const WEAPONS := [["WEAPON", 3, 1], ["OFFHAND", 2, 12], ["AMULET", 4, 9], ["RING I", 1, 8], ["RING II", 2, 8]]
	const CH_EQUIP := [
		["HEAD", 2, 3], ["CHEST", 3, 4], ["GLOVES", 1, 5], ["WEAPON", 3, 1],
		["LEGS", 2, 6], ["BOOTS", 1, 7], ["AMULET", 4, 9],
	]
	const TABS := ["CHARACTER", "ABILITIES", "PARAGON", "CODEX"]
	const CURRENCY := [
		[Color(1.0, 0.81, 0.42), "GOLD", "52,348,772"],
		[Color(0.82, 0.89, 0.94), "PLATINUM", "8,722"],
		[Color(0.48, 0.84, 1.0), "CRYSTALS", "123"],
	]

	func _seed_grid() -> void:
		# deterministic pseudo-fill: 30 cells, a few empty
		var pool := [1, 0, 10, 2, 11, 3, 4, 5, 8, 9]  # icon kinds spread across categories
		var rw := [0, 0, 1, 1, 1, 2, 2, 3, 3, 4]
		for i in 30:
			var seed: int = (i * 7 + 13) % 17
			if seed > 13:
				_grid.append(null)
				continue
			var r: int = rw[(i * 3 + seed) % 10]
			var star: int = 1 + ((i + seed) % 5)
			var kind: int = pool[(i * 2 + seed) % pool.size()]
			_grid.append({"r": r, "star": star, "kind": kind})
		_seeded = true

	# ---------------------------------------------------------------- fonts guard
	func _ff() -> void:
		if f_base == null:
			f_base = ThemeDB.fallback_font
		if f_wide == null: f_wide = f_base
		if f_title == null: f_title = f_base
		if f_bold == null: f_bold = f_base
		if f_num == null: f_num = f_base
		if f_huge == null: f_huge = f_base

	# ---------------------------------------------------------------- draw entry
	func _draw() -> void:
		_ff()
		if not _seeded:
			_seed_grid()
		var a: float = clampf(anim, 0.0, 1.0)
		# The panel content draws at full alpha/size the moment it draws at all (the pop is a
		# sub-pixel scale, alpha is fixed), so there is no such thing as a "faintly-open" panel —
		# it is either absent or fully present. Gate the draw a hair higher than 0 and pair it
		# with a scrim that is already fully opaque at this same threshold (below): that way crisp
		# content is NEVER laid over a see-through backdrop, which is what let the world/HUD bleed
		# through the crossfade regardless of the (capture-timing-sensitive) HUD occlusion toggle.
		if a <= 0.02:
			return
		# ease the reveal (pop) — soft
		var e: float = a * a * (3.0 - 2.0 * a)

		# uniform scale into 1600x1000 design space
		var sc: float = minf(size.x / DW, size.y / DH)
		var origin: Vector2 = (size - Vector2(DW, DH) * sc) * 0.5

		# full-screen scrim (drawn in screen space, before transform) — near-opaque so no
		# gameplay / HUD / 3D loot label bleeds through when the menu is open. The module also
		# hides the HUD CanvasLayer + loot FX root while fully open (_occlude), but the scrim
		# alone must already read clean during the crossfade. A faint cool centre-lift keeps it
		# from looking like a flat black slab (subtle vignette for depth).
		# The scrim opacity RAMPS FAST — decoupled from the panel's soft pop-ease (`e`) — so it
		# reaches near-opaque by ~a=0.25 and stays there. This is what kills crossfade bleed from
		# sources the module can't reach (enemy nameplates, the 3D boss/crystals): a mid-fade
		# panel is translucent, but the full-screen scrim behind it is already opaque, so nothing
		# from the world layer shows through during the open/close transition, not just when open.
		# The panel CONTENT (cells, text, hero) draws at full alpha the instant the panel exists,
		# so the scrim behind it must reach FULL opacity just as fast — otherwise crisp content
		# floats over a half-opaque backing and the world bleeds through the gaps (that was the
		# char-sheet mid-fade). Ramp is steep (opaque by a≈0.08) and independent of the soft panel
		# pop, and alpha is a solid 1.0 — zero transmission from anything behind (HUD, enemy
		# nameplates, boss, crystals) in any open/close frame, regardless of module ownership.
		var sa: float = clampf(a * 50.0, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.020, 0.034, sa), true)
		# subtle cool centre-lift over the opaque base so it reads with depth, not as a flat slab
		var cen: Vector2 = size * 0.5
		for i in range(6, 0, -1):
			var rad: float = size.x * (0.16 + 0.085 * float(i))
			draw_circle(cen, rad, Color(0.05, 0.11, 0.16, 0.022 * sa))

		draw_set_transform(origin, 0.0, Vector2(sc, sc))

		# panel geometry + subtle pop scale
		var pop: float = 0.985 + 0.015 * e
		var pr := Rect2(48, 30, DW - 96, DH - 60)
		var pc := pr.position + pr.size * 0.5
		draw_set_transform(origin, 0.0, Vector2(sc * pop, sc * pop))
		# recompute origin so the panel stays centred while it pops
		var scaled := Vector2(DW, DH) * sc * pop
		var o2: Vector2 = (size - scaled) * 0.5
		draw_set_transform(o2, 0.0, Vector2(sc * pop, sc * pop))

		_frame(pr, pc, e)
		if mode == "inv":
			_draw_inventory(pr)
		else:
			_draw_character(pr)

	# ---------------------------------------------------------------- shared frame
	func _frame(pr: Rect2, _pc: Vector2, e: float) -> void:
		# panel body
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.031, 0.071, 0.104, 0.965 * e + 0.02)
		sb.border_color = Color(0.224, 0.843, 1.0, 0.30)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(12)
		sb.shadow_color = Color(0, 0, 0, 0.7)
		sb.shadow_size = 30
		draw_style_box(sb, pr)

		# inner cyan glow (a few inset translucent frames)
		for i in 4:
			var g := Rect2(pr.position + Vector2(2 + i, 2 + i), pr.size - Vector2(4 + i * 2, 4 + i * 2))
			draw_rect(g, Color(0.224, 0.843, 1.0, 0.020 * (1.0 - float(i) / 4.0)), false, 1.0)

		# top sheen
		draw_rect(Rect2(pr.position + Vector2(2, 2), Vector2(pr.size.x - 4, 40)),
			Color(0.35, 0.78, 1.0, 0.05), true)

		# corner filigree (all four)
		_corners(pr, 26.0, Color(0.30, 0.86, 1.0, 0.55))

		# eyebrow
		var eb: String = "GALACTIC OBSERVATION PROTOCOL"
		eb += "  ·  SPECIMEN LOADOUT" if mode == "inv" else "  ·  SPECIMEN DOSSIER"
		draw_string(f_wide, pr.position + Vector2(26, 34), eb, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.42, 0.63, 0.72))

		# close button (top-right)
		var cb := Rect2(pr.position + Vector2(pr.size.x - 46, 12), Vector2(34, 34))
		var cbs := StyleBoxFlat.new()
		cbs.bg_color = Color(0.03, 0.07, 0.10, 0.85)
		cbs.border_color = PLINE
		cbs.set_border_width_all(1)
		cbs.set_corner_radius_all(8)
		draw_style_box(cbs, cb)
		var cc := cb.position + cb.size * 0.5
		draw_line(cc + Vector2(-6, -6), cc + Vector2(6, 6), Color(0.66, 0.84, 0.90), 1.6, true)
		draw_line(cc + Vector2(6, -6), cc + Vector2(-6, 6), Color(0.66, 0.84, 0.90), 1.6, true)

		# hint bottom-left (inventory only — the char sheet fills this strip with metrics)
		if mode == "inv":
			draw_string(f_wide, pr.position + Vector2(26, pr.size.y - 14),
				"C · CHARACTER    I · INVENTORY    ESC · CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.33, 0.45, 0.52))

	func _corners(pr: Rect2, ln: float, col: Color) -> void:
		var m := 9.0
		var x0 := pr.position.x + m
		var y0 := pr.position.y + m
		var x1 := pr.position.x + pr.size.x - m
		var y1 := pr.position.y + pr.size.y - m
		var w := 2.0
		draw_polyline(PackedVector2Array([Vector2(x0, y0 + ln), Vector2(x0, y0), Vector2(x0 + ln, y0)]), col, w, true)
		draw_polyline(PackedVector2Array([Vector2(x1 - ln, y0), Vector2(x1, y0), Vector2(x1, y0 + ln)]), col, w, true)
		draw_polyline(PackedVector2Array([Vector2(x1, y1 - ln), Vector2(x1, y1), Vector2(x1 - ln, y1)]), col, w, true)
		draw_polyline(PackedVector2Array([Vector2(x0 + ln, y1), Vector2(x0, y1), Vector2(x0, y1 - ln)]), col, w, true)

	# ================================================================= INVENTORY
	func _draw_inventory(pr: Rect2) -> void:
		var x0 := pr.position.x + 26.0
		var y0 := pr.position.y + 50.0
		var right := pr.position.x + pr.size.x - 26.0

		# title
		draw_string(f_title, Vector2(x0, y0 + 22), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(0.92, 0.96, 0.99))
		# tab bar (right-aligned)
		_tabs(Vector2(right, y0 - 4), 0)

		# header rule
		draw_rect(Rect2(x0, y0 + 40, right - x0, 1), PLINE, true)

		var by := y0 + 58.0
		var bh := pr.position.y + pr.size.y - 30.0 - by   # body height (currency drawn inside)

		# ----- column x-bands -----
		var armor_x := x0
		var armor_w := 92.0
		var ped_x := armor_x + armor_w + 14.0
		var ped_w := 372.0
		var wpn_x := ped_x + ped_w + 14.0
		var wpn_w := 92.0
		var grid_x := wpn_x + wpn_w + 18.0
		var stat_x := right - 300.0
		var grid_w := stat_x - 18.0 - grid_x

		var body_bottom := by + bh - 96.0   # leave room for currency row

		# equipment columns
		_equip_col(Vector2(armor_x, by), armor_w, body_bottom - by, "ARMOR", ARMOR)
		_equip_col(Vector2(wpn_x, by), wpn_w, body_bottom - by, "WEAPONS", WEAPONS)

		# pedestal (Carl)
		_pedestal(Rect2(ped_x, by, ped_w, body_bottom - by))

		# item grid
		_label_caps(Vector2(grid_x, by + 10), "BACKPACK  ·  30 SLOTS", TXT_DD, 9)
		_item_grid(Rect2(grid_x, by + 20, grid_w, body_bottom - by - 20), 6, 5)

		# stat card
		_card(Rect2(stat_x, by, 300.0, body_bottom - by))
		_card_title(Vector2(stat_x + 14, by + 22), "EQUIPPED STATS", CYAN)
		var sy := by + 40.0
		var srh: float = (body_bottom - by - 52.0) / float(INV_STATS.size())
		for row in INV_STATS:
			_stat_row(stat_x + 14, sy, 272.0, row[0], row[1], _valcol(row[2]))
			sy += srh

		# currency row
		_currency(Vector2(x0, body_bottom + 20.0), right - x0)

	func _equip_col(pos: Vector2, w: float, h: float, title: String, slots: Array) -> void:
		_label_caps(Vector2(pos.x + w * 0.5, pos.y + 8), title, TXT_D, 9, HORIZONTAL_ALIGNMENT_CENTER)
		var n := slots.size()
		var gap := 12.0
		var top := pos.y + 20.0
		var cell: float = minf(w, (h - 20.0 - float(n - 1) * gap) / float(n))
		var cx := pos.x + (w - cell) * 0.5
		var y := top
		for s in slots:
			var r := Rect2(cx, y, cell, cell)
			_slot(r, int(s[1]), int(s[2]), 0, "", str(s[0]))
			y += cell + gap

	func _pedestal(rect: Rect2) -> void:
		# dark well
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.027, 0.063, 0.094, 0.85)
		sb.border_color = PLINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		draw_style_box(sb, rect)

		var cx := rect.position.x + rect.size.x * 0.5
		var floor_y := rect.position.y + rect.size.y - 74.0

		# top ambient glow
		for i in range(9, 0, -1):
			draw_circle(Vector2(cx, rect.position.y + 30.0), float(i) * 12.0,
				Color(0.224, 0.843, 1.0, 0.012))
		# floor pool glow
		for i in range(10, 0, -1):
			var rr := Vector2(float(i) * 15.0, float(i) * 5.0)
			_draw_ellipse(Vector2(cx, floor_y + 30.0), rr, Color(0.224, 0.843, 1.0, 0.016))

		# rotating crystals (behind + around the feet)
		var cn := 5
		for i in cn:
			var a: float = t * 0.6 + TAU * float(i) / float(cn)
			var depth: float = sin(a)                    # -1..1 : back..front
			var px: float = cx + cos(a) * (rect.size.x * 0.32)
			var py: float = floor_y + 6.0 + depth * 16.0
			var scale: float = 0.72 + 0.28 * (depth * 0.5 + 0.5)
			var behind: bool = depth < -0.15
			var col: Color = AETHER if (i % 2 == 0) else CYAN
			if behind:
				_crystal(Vector2(px, py), 26.0 * scale, col, 0.5)
		# hero
		_carl(Vector2(cx, floor_y), rect.size.y * 0.62)
		# front crystals
		for i in cn:
			var a2: float = t * 0.6 + TAU * float(i) / float(cn)
			var depth2: float = sin(a2)
			if depth2 >= -0.15:
				var px2: float = cx + cos(a2) * (rect.size.x * 0.32)
				var py2: float = floor_y + 6.0 + depth2 * 16.0
				var scale2: float = 0.72 + 0.28 * (depth2 * 0.5 + 0.5)
				var col2: Color = AETHER if (i % 2 == 0) else CYAN
				_crystal(Vector2(px2, py2), 26.0 * scale2, col2, 0.9)

		# pedestal discs
		_draw_ellipse(Vector2(cx, floor_y + 30.0), Vector2(96, 20), Color(0.05, 0.11, 0.16, 0.95))
		draw_arc(Vector2(cx, floor_y + 30.0), 96.0, 0.0, TAU, 48, Color(0.224, 0.843, 1.0, 0.35), 1.4, true)
		_draw_ellipse(Vector2(cx, floor_y + 24.0), Vector2(74, 14), Color(0.04, 0.10, 0.15, 0.95))
		draw_arc(Vector2(cx, floor_y + 24.0), 74.0, 0.0, TAU, 40, Color(0.30, 0.86, 1.0, 0.5), 1.2, true)
		_draw_ellipse(Vector2(cx, floor_y + 19.0), Vector2(56, 10), Color(0.06, 0.15, 0.21, 0.95))
		draw_arc(Vector2(cx, floor_y + 19.0), 56.0, 0.0, TAU, 36, Color(0.40, 0.90, 1.0, 0.6), 1.0, true)

		# class label
		var lab := "PRIMAL WARRIOR  ·  ASCENDED"
		var ls: Vector2 = f_wide.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var lx := cx - ls.x * 0.5
		var lyy := rect.position.y + rect.size.y - 16.0
		_diamond(Vector2(lx - 12, lyy - 4), 3.5, GOLD)
		_diamond(Vector2(lx + ls.x + 12, lyy - 4), 3.5, GOLD)
		draw_string(f_wide, Vector2(lx, lyy), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.56, 0.78, 0.87))

	func _crystal(c: Vector2, h: float, col: Color, alpha: float) -> void:
		var w := h * 0.34
		var p := PackedVector2Array([
			c + Vector2(0, -h * 0.7), c + Vector2(w, -h * 0.15),
			c + Vector2(w * 0.55, h * 0.3), c + Vector2(-w * 0.55, h * 0.3),
			c + Vector2(-w, -h * 0.15),
		])
		# glow
		draw_circle(c + Vector2(0, -h * 0.2), h * 0.55, Color(col.r, col.g, col.b, 0.10 * alpha))
		draw_colored_polygon(p, Color(col.r * 0.5, col.g * 0.5, col.b * 0.6, 0.85 * alpha))
		# facet highlight
		draw_polyline(PackedVector2Array([c + Vector2(0, -h * 0.7), c + Vector2(0, h * 0.3)]),
			Color(col.r, col.g, col.b, 0.7 * alpha), 1.0, true)
		var p2 := PackedVector2Array(p)
		p2.append(p[0])
		draw_polyline(p2, Color(col.r, col.g, col.b, 0.9 * alpha), 1.2, true)

	## Stylised heroic Carl: a solid blue-steel statue with cyan rim + warm key, heart boxers,
	## bare feet, and a big glowing blue axe. Lit like the pedestal in Frame C.
	func _carl(feet: Vector2, h: float) -> void:
		var s := h / 260.0            # unit scale
		var body := Color(0.13, 0.18, 0.235)     # solid statue fill (reads over the dark well)
		var body_hi := Color(0.20, 0.27, 0.33)
		var body_lo := Color(0.07, 0.10, 0.14)
		var rim := Color(0.34, 0.88, 1.0, 0.9)
		var warm := Color(1.0, 0.66, 0.44, 0.7)
		var skin := Color(0.62, 0.52, 0.46)
		var skin_lo := Color(0.34, 0.28, 0.26)
		var hip := feet + Vector2(0, -116 * s)
		var chest := feet + Vector2(0, -182 * s)
		var head := feet + Vector2(0, -226 * s)

		# backlight halo behind hero
		for i in range(9, 0, -1):
			draw_circle(feet + Vector2(0, -150 * s), float(i) * 15.0 * s,
				Color(0.224, 0.843, 1.0, 0.013))

		# ---- glowing blue axe, planted at Carl's left, head up ----
		var haft_bot := feet + Vector2(-64 * s, 4 * s)
		var haft_top := feet + Vector2(-52 * s, -244 * s)
		for gi in range(4, 0, -1):
			draw_line(haft_top, haft_bot, Color(0.30, 0.70, 1.0, 0.05), (4.0 + gi * 2.5) * s, true)
		draw_line(haft_top, haft_bot, Color(0.20, 0.24, 0.30), 3.6 * s, true)
		draw_line(haft_top, haft_bot, Color(0.55, 0.82, 1.0, 0.5), 1.2 * s, true)
		# single-bit crescent axe head near the top of the haft
		var hd := haft_top + Vector2(-2 * s, 26 * s)
		var blade := PackedVector2Array([
			hd + Vector2(2 * s, -30 * s), hd + Vector2(-34 * s, -20 * s),
			hd + Vector2(-40 * s, 8 * s), hd + Vector2(-30 * s, 30 * s),
			hd + Vector2(2 * s, 24 * s),
		])
		for gi in range(5, 0, -1):
			_poly_glow(blade, hd, Color(0.35, 0.75, 1.0, 0.05), float(gi) * 2.0 * s)
		draw_colored_polygon(blade, Color(0.20, 0.50, 0.78, 0.97))
		# inner edge sheen
		draw_colored_polygon(PackedVector2Array([
			hd + Vector2(2 * s, -30 * s), hd + Vector2(-16 * s, -25 * s),
			hd + Vector2(-14 * s, 26 * s), hd + Vector2(2 * s, 24 * s)]),
			Color(0.42, 0.72, 1.0, 0.6))
		var b2 := PackedVector2Array(blade)
		b2.append(blade[0])
		draw_polyline(b2, Color(0.65, 0.92, 1.0, 0.95), 1.6 * s, true)

		# ---- legs ----
		var lhip := hip + Vector2(-15 * s, 2 * s)
		var rhip := hip + Vector2(15 * s, 2 * s)
		_limb2(lhip, feet + Vector2(-19 * s, 0), 16 * s, 11 * s, body, body_hi, rim)
		_limb2(rhip, feet + Vector2(19 * s, 0), 16 * s, 11 * s, body, body_hi, warm)
		# bare feet
		draw_colored_polygon(_foot(feet + Vector2(-19 * s, 0), s), skin)
		draw_colored_polygon(_foot(feet + Vector2(19 * s, 0), s), skin_lo)

		# ---- heart-pattern boxers ----
		var box := PackedVector2Array([
			hip + Vector2(-27 * s, -10 * s), hip + Vector2(27 * s, -10 * s),
			hip + Vector2(25 * s, 22 * s), hip + Vector2(-25 * s, 22 * s),
		])
		draw_colored_polygon(box, Color(0.84, 0.19, 0.27))
		draw_rect(Rect2((hip + Vector2(-27 * s, -12 * s)).x, (hip + Vector2(0, -12 * s)).y,
			54 * s, 4 * s), Color(0.95, 0.92, 0.94, 0.9), true)  # waistband
		for hx in [-13.0, 13.0]:
			_heart(hip + Vector2(hx * s, 8 * s), 6.5 * s, Color(1.0, 0.86, 0.90))

		# ---- torso (muscle) : solid, shaded ----
		var torso := PackedVector2Array([
			chest + Vector2(-34 * s, -6 * s), chest + Vector2(34 * s, -6 * s),
			hip + Vector2(28 * s, -6 * s), hip + Vector2(-28 * s, -6 * s),
		])
		draw_colored_polygon(torso, body)
		# lit upper chest
		draw_colored_polygon(PackedVector2Array([
			chest + Vector2(-34 * s, -6 * s), chest + Vector2(34 * s, -6 * s),
			chest + Vector2(28 * s, 20 * s), chest + Vector2(-28 * s, 20 * s)]),
			body_hi)
		# lower-ab shadow
		draw_colored_polygon(PackedVector2Array([
			chest + Vector2(-26 * s, 30 * s), chest + Vector2(26 * s, 30 * s),
			hip + Vector2(24 * s, -6 * s), hip + Vector2(-24 * s, -6 * s)]),
			body_lo)
		# pec split + ab lines
		draw_line(chest + Vector2(0, -2 * s), hip + Vector2(0, -8 * s), Color(0, 0, 0, 0.35), 1.6 * s, true)
		draw_arc(chest + Vector2(-15 * s, 8 * s), 13 * s, PI * 0.05, PI * 0.85, 10, Color(0, 0, 0, 0.28), 1.6 * s, true)
		draw_arc(chest + Vector2(15 * s, 8 * s), 13 * s, PI * 0.15, PI * 0.95, 10, Color(0, 0, 0, 0.28), 1.6 * s, true)
		for ai in 2:
			draw_line(chest + Vector2(-11 * s, (24 + ai * 12) * s), chest + Vector2(11 * s, (24 + ai * 12) * s),
				Color(0, 0, 0, 0.22), 1.2 * s, true)
		# rim + key edges
		draw_polyline(PackedVector2Array([torso[0], torso[3]]), rim, 1.8 * s, true)
		draw_polyline(PackedVector2Array([torso[1], torso[2]]), warm, 1.5 * s, true)

		# ---- arms ----
		var lsh := chest + Vector2(-32 * s, 0)
		var rsh := chest + Vector2(32 * s, 0)
		# left arm reaches down to grip the axe haft
		_limb2(lsh, haft_bot + Vector2(10 * s, -74 * s), 13 * s, 9 * s, body, body_hi, rim)
		# right arm rests at side
		_limb2(rsh, hip + Vector2(32 * s, 4 * s), 13 * s, 9 * s, body, body_hi, warm)
		# deltoid caps blend the arms into the torso
		draw_circle(lsh, 13 * s, body_hi)
		draw_circle(rsh, 13 * s, body)

		# ---- neck + head ----
		draw_line(chest + Vector2(0, -6 * s), head + Vector2(0, 15 * s), skin_lo, 13 * s, true)
		draw_circle(head, 18 * s, skin_lo)
		draw_circle(head + Vector2(-2 * s, -3 * s), 16 * s, skin)   # lit face
		# beard
		draw_colored_polygon(PackedVector2Array([
			head + Vector2(-13 * s, 2 * s), head + Vector2(13 * s, 2 * s),
			head + Vector2(8 * s, 20 * s), head + Vector2(-8 * s, 20 * s)]),
			Color(0.16, 0.12, 0.11))
		# eyes
		draw_circle(head + Vector2(-6 * s, -2 * s), 1.7 * s, Color(0.05, 0.06, 0.08))
		draw_circle(head + Vector2(6 * s, -2 * s), 1.7 * s, Color(0.05, 0.06, 0.08))
		# brow shadow + hair
		draw_arc(head, 18 * s, PI * 1.05, PI * 1.95, 14, Color(0.12, 0.10, 0.10), 3.0 * s, true)
		# rim + key on head
		draw_arc(head, 18 * s, PI * 0.55, PI * 1.5, 18, rim, 1.6 * s, true)
		draw_arc(head, 18 * s, -PI * 0.42, PI * 0.42, 14, warm, 1.4 * s, true)

	## Tapered limb with a lit inner strip and a rim edge.
	func _limb2(a: Vector2, b: Vector2, w0: float, w1: float, col: Color, hi: Color, rim: Color) -> void:
		var d := (b - a)
		var ln := d.length()
		if ln < 0.001:
			return
		var n := Vector2(-d.y, d.x) / ln
		var p := PackedVector2Array([a + n * w0, b + n * w1, b - n * w1, a - n * w0])
		draw_colored_polygon(p, col)
		draw_colored_polygon(PackedVector2Array([a + n * w0, b + n * w1, b + n * w1 * 0.1, a + n * w0 * 0.1]), hi)
		draw_polyline(PackedVector2Array([a + n * w0, b + n * w1]), rim, 1.3, true)

	func _limb(a: Vector2, b: Vector2, w0: float, w1: float, col: Color, rim: Color) -> void:
		var d := (b - a)
		var ln := d.length()
		if ln < 0.001:
			return
		var n := Vector2(-d.y, d.x) / ln
		var p := PackedVector2Array([a + n * w0, b + n * w1, b - n * w1, a - n * w0])
		draw_colored_polygon(p, col)
		draw_polyline(PackedVector2Array([a + n * w0, b + n * w1]), rim, 1.3, true)

	func _foot(a: Vector2, s: float) -> PackedVector2Array:
		return PackedVector2Array([
			a + Vector2(-9 * s, -6 * s), a + Vector2(16 * s, -2 * s),
			a + Vector2(16 * s, 4 * s), a + Vector2(-9 * s, 4 * s),
		])

	func _heart(c: Vector2, r: float, col: Color) -> void:
		var p := PackedVector2Array()
		var steps := 18
		for i in range(steps + 1):
			var a: float = TAU * float(i) / float(steps)
			var x: float = 16.0 * pow(sin(a), 3.0)
			var y: float = 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
			p.append(c + Vector2(x / 16.0 * r, -y / 16.0 * r))
		draw_colored_polygon(p, col)

	func _poly_glow(poly: PackedVector2Array, c: Vector2, col: Color, grow: float) -> void:
		var p := PackedVector2Array()
		for v in poly:
			var d := v - c
			var ln := d.length()
			if ln < 0.001:
				p.append(v)
			else:
				p.append(v + d / ln * grow)
		draw_colored_polygon(p, col)

	# ---------------------------------------------------------------- item grid
	func _item_grid(rect: Rect2, cols: int, rows: int) -> void:
		var gap := 11.0
		var cw: float = (rect.size.x - float(cols - 1) * gap) / float(cols)
		var ch: float = (rect.size.y - float(rows - 1) * gap) / float(rows)
		var cell: float = minf(cw, ch)
		var gw := float(cols) * cell + float(cols - 1) * gap
		var gh := float(rows) * cell + float(rows - 1) * gap
		var ox := rect.position.x + (rect.size.x - gw) * 0.5
		var oy := rect.position.y + (rect.size.y - gh) * 0.5
		var idx := 0
		for r in rows:
			for c in cols:
				var x := ox + float(c) * (cell + gap)
				var y := oy + float(r) * (cell + gap)
				var item = _grid[idx] if idx < _grid.size() else null
				if item == null:
					_empty_slot(Rect2(x, y, cell, cell))
				else:
					_slot(Rect2(x, y, cell, cell), int(item["r"]), int(item["kind"]),
						int(item["star"]), RTAG[int(item["r"])], "")
				idx += 1

	func _empty_slot(r: Rect2) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.035, 0.075, 0.10, 0.55)
		sb.border_color = Color(0.224, 0.843, 1.0, 0.10)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		draw_style_box(sb, r)

	## Rarity-bordered item cell: coloured border + glow, top rarity bar, vector icon,
	## quality tag, star pips.
	func _slot(r: Rect2, rarity: int, kind: int, star: int, tag: String, slotlabel: String) -> void:
		var rc: Color = RAR[clampi(rarity, 0, RAR.size() - 1)]
		# outer glow
		for i in range(4, 0, -1):
			var gr := r.grow(float(i) * 1.6)
			draw_rect(gr, Color(rc.r, rc.g, rc.b, 0.04), false, 1.5)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.055, 0.11, 0.15, 0.94)
		sb.border_color = Color(rc.r, rc.g, rc.b, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		draw_style_box(sb, r)
		# inner radial wash
		var cc := r.position + r.size * 0.5
		for k in range(5, 0, -1):
			draw_circle(cc, float(k) * r.size.x * 0.06, Color(rc.r, rc.g, rc.b, 0.05))
		# top rarity bar
		draw_rect(Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 3.0),
			Color(rc.r, rc.g, rc.b, 0.9), true)
		# icon
		_icon(kind, cc + Vector2(0, -2), r.size.x * 0.26, rc)
		# quality tag
		if tag != "":
			var ts: Vector2 = f_num.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			draw_string(f_num, Vector2(r.position.x + r.size.x - ts.x - 5, r.position.y + 15),
				tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(rc.r, rc.g, rc.b, 0.95))
		# stars
		if star > 0:
			_stars(Vector2(cc.x, r.position.y + r.size.y - 8.0), star, rc)
		# slot label (equipment)
		if slotlabel != "":
			var sl: Vector2 = f_wide.get_string_size(slotlabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
			draw_string(f_wide, Vector2(cc.x - sl.x * 0.5, r.position.y + r.size.y - 5.0),
				slotlabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.55, 0.68, 0.76))

	func _stars(center: Vector2, n: int, col: Color) -> void:
		var sp := 7.0
		var x0 := center.x - float(n - 1) * sp * 0.5
		for i in n:
			_diamond(Vector2(x0 + float(i) * sp, center.y), 2.6, col)

	func _diamond(c: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

	# ---------------------------------------------------------------- icons (vector)
	func _icon(kind: int, c: Vector2, s: float, col: Color) -> void:
		var w := 1.8
		var lit := Color(col.r, col.g, col.b, 1.0)
		var fill := Color(col.r * 0.5, col.g * 0.5, col.b * 0.55, 0.55)
		match kind:
			0:  # sword
				draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.55), lit, w + 1.0, true)
				draw_line(c + Vector2(-s * 0.5, s * 0.4), c + Vector2(s * 0.5, s * 0.4), lit, w, true)
				draw_line(c + Vector2(0, s * 0.55), c + Vector2(0, s * 0.9), lit, w + 1.5, true)
			1:  # axe — haft + crescent bit
				draw_line(c + Vector2(s * 0.25, -s), c + Vector2(-s * 0.1, s), lit, w + 0.6, true)
				var hd1 := c + Vector2(s * 0.2, -s * 0.62)
				var bl := PackedVector2Array([
					hd1 + Vector2(0, -s * 0.32), hd1 + Vector2(-s * 0.62, -s * 0.18),
					hd1 + Vector2(-s * 0.72, s * 0.16), hd1 + Vector2(-s * 0.5, s * 0.34),
					hd1 + Vector2(0, s * 0.26)])
				draw_colored_polygon(bl, fill)
				var bl2 := PackedVector2Array(bl)
				bl2.append(bl[0])
				draw_polyline(bl2, lit, w, true)
			2:  # bow
				draw_arc(c, s, -PI * 0.55, PI * 0.55, 20, lit, w, true)
				draw_line(c + Vector2(cos(-PI * 0.55) * s, sin(-PI * 0.55) * s),
					c + Vector2(cos(PI * 0.55) * s, sin(PI * 0.55) * s), Color(col.r, col.g, col.b, 0.6), 1.0, true)
			3:  # helm
				var hm := PackedVector2Array([
					c + Vector2(-s * 0.8, s * 0.2), c + Vector2(-s * 0.8, -s * 0.3),
					c + Vector2(0, -s * 0.85), c + Vector2(s * 0.8, -s * 0.3),
					c + Vector2(s * 0.8, s * 0.2)])
				draw_colored_polygon(hm, fill)
				draw_polyline(hm, lit, w, true)
				draw_line(c + Vector2(-s * 0.8, s * 0.2), c + Vector2(s * 0.8, s * 0.2), lit, w, true)
				draw_line(c + Vector2(0, -s * 0.2), c + Vector2(0, s * 0.2), Color(0, 0, 0, 0.4), w, true)
			4:  # chest / breastplate
				var bp := PackedVector2Array([
					c + Vector2(-s * 0.75, -s * 0.7), c + Vector2(s * 0.75, -s * 0.7),
					c + Vector2(s * 0.6, s * 0.5), c + Vector2(0, s * 0.9),
					c + Vector2(-s * 0.6, s * 0.5)])
				draw_colored_polygon(bp, fill)
				draw_polyline(bp, lit, w, true)
				draw_arc(c + Vector2(0, -s * 0.7), s * 0.35, 0, PI, 12, lit, w * 0.8, true)
			5:  # gloves
				var gl := PackedVector2Array([
					c + Vector2(-s * 0.5, s * 0.8), c + Vector2(-s * 0.5, -s * 0.3),
					c + Vector2(-s * 0.2, -s * 0.9), c + Vector2(0.0, -s * 0.4),
					c + Vector2(s * 0.2, -s * 0.9), c + Vector2(s * 0.5, -s * 0.3),
					c + Vector2(s * 0.5, s * 0.8)])
				draw_colored_polygon(gl, fill)
				draw_polyline(gl, lit, w, true)
			6:  # legs
				draw_line(c + Vector2(-s * 0.35, -s * 0.8), c + Vector2(-s * 0.4, s * 0.9), lit, w + 1.5, true)
				draw_line(c + Vector2(s * 0.35, -s * 0.8), c + Vector2(s * 0.4, s * 0.9), lit, w + 1.5, true)
				draw_line(c + Vector2(-s * 0.5, -s * 0.8), c + Vector2(s * 0.5, -s * 0.8), lit, w, true)
			7:  # boots
				var bt := PackedVector2Array([
					c + Vector2(-s * 0.2, -s * 0.8), c + Vector2(s * 0.2, -s * 0.8),
					c + Vector2(s * 0.2, s * 0.3), c + Vector2(s * 0.85, s * 0.5),
					c + Vector2(s * 0.85, s * 0.8), c + Vector2(-s * 0.2, s * 0.8)])
				draw_colored_polygon(bt, fill)
				draw_polyline(bt, lit, w, true)
			8:  # ring
				draw_arc(c + Vector2(0, s * 0.2), s * 0.6, 0, TAU, 24, lit, w, true)
				_diamond(c + Vector2(0, -s * 0.55), s * 0.35, lit)
			9:  # amulet
				draw_arc(c + Vector2(0, -s * 0.3), s * 0.7, PI * 0.15, PI * 0.85, 16, lit, w, true)
				_diamond(c + Vector2(0, s * 0.45), s * 0.4, Color(col.r, col.g, col.b, 0.9))
			10:  # staff / wand
				draw_line(c + Vector2(-s * 0.5, s), c + Vector2(s * 0.4, -s * 0.7), lit, w, true)
				draw_circle(c + Vector2(s * 0.4, -s * 0.7), s * 0.28, Color(col.r, col.g, col.b, 0.6))
				draw_arc(c + Vector2(s * 0.4, -s * 0.7), s * 0.28, 0, TAU, 16, lit, w, true)
			11:  # gem
				var gm := PackedVector2Array([
					c + Vector2(0, -s * 0.9), c + Vector2(s * 0.7, -s * 0.2),
					c + Vector2(s * 0.4, s * 0.8), c + Vector2(-s * 0.4, s * 0.8),
					c + Vector2(-s * 0.7, -s * 0.2)])
				draw_colored_polygon(gm, fill)
				draw_polyline(gm, lit, w, true)
				draw_line(c + Vector2(0, -s * 0.9), c + Vector2(0, s * 0.8), Color(col.r, col.g, col.b, 0.7), 1.0, true)
			12:  # shield / offhand
				var sh := PackedVector2Array([
					c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, -s * 0.7),
					c + Vector2(s * 0.7, s * 0.2), c + Vector2(0, s * 0.95),
					c + Vector2(-s * 0.7, s * 0.2)])
				draw_colored_polygon(sh, fill)
				draw_polyline(sh, lit, w, true)
				draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.5), lit, w * 0.7, true)
				draw_line(c + Vector2(-s * 0.45, 0), c + Vector2(s * 0.45, 0), lit, w * 0.7, true)
			_:
				draw_circle(c, s * 0.5, fill)

	# ---------------------------------------------------------------- currency
	func _currency(pos: Vector2, w: float) -> void:
		draw_rect(Rect2(pos.x, pos.y - 12.0, w, 1.0), PLINE, true)
		var n := CURRENCY.size()
		var seg := w / float(n)
		for i in n:
			var e = CURRENCY[i]
			var col: Color = e[0]
			var cx := pos.x + seg * float(i) + seg * 0.5
			var dot := Vector2(cx - 70.0, pos.y + 22.0)
			for gi in range(4, 0, -1):
				draw_circle(dot, 10.0 + float(gi) * 2.0, Color(col.r, col.g, col.b, 0.05))
			draw_circle(dot, 9.0, col)
			draw_circle(dot + Vector2(-2.5, -2.5), 3.0, Color(1, 1, 1, 0.5))
			draw_string(f_wide, Vector2(dot.x + 18, pos.y + 14), str(e[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, TXT_D)
			draw_string(f_num, Vector2(dot.x + 18, pos.y + 32), str(e[2]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.92, 0.96, 0.99))

	# ================================================================= CHARACTER SHEET
	func _draw_character(pr: Rect2) -> void:
		var x0 := pr.position.x + 30.0
		var right := pr.position.x + pr.size.x - 30.0
		var y0 := pr.position.y + 46.0

		# --- header ---
		draw_string(f_huge, Vector2(x0, y0 + 34), "CARL", HORIZONTAL_ALIGNMENT_LEFT, -1, 44,
			Color(0.95, 0.94, 0.90))
		draw_string(f_wide, Vector2(x0 + 2, y0 + 58), "LEVEL 78  ·  PRIMAL WARRIOR",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)
		_diamond(Vector2(x0 + 5, y0 + 74), 4.0, CYAN)
		draw_string(f_wide, Vector2(x0 + 16, y0 + 78), "PARAGON TIER 4",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CYAN)

		# xp bar (right half)
		var xpx := pr.position.x + pr.size.x * 0.46
		var xpw := right - xpx
		draw_string(f_wide, Vector2(xpx, y0 + 14), "EXPERIENCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TXT_D)
		var xpr := "23,314,112 / 28,750,000 XP"
		var xrs: Vector2 = f_num.get_string_size(xpr, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		draw_string(f_num, Vector2(right - xrs.x, y0 + 14), xpr, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.86, 0.92, 0.97))
		var bar := Rect2(xpx, y0 + 22, xpw, 12.0)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.04, 0.10, 0.14, 0.95)
		bsb.border_color = Color(0.224, 0.843, 1.0, 0.30)
		bsb.set_border_width_all(1)
		bsb.set_corner_radius_all(6)
		draw_style_box(bsb, bar)
		var frac := 0.811
		var fr := Rect2(bar.position.x + 1, bar.position.y + 1, (bar.size.x - 2) * frac, bar.size.y - 2)
		draw_rect(fr, Color(0.18, 0.50, 0.70), true)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.5)), Color(0.30, 0.78, 1.0), true)
		# shine
		var shx: float = fmod(t * 0.35, 1.0) * fr.size.x
		draw_rect(Rect2(fr.position.x + shx - 12, fr.position.y, 24, fr.size.y),
			Color(1, 1, 1, 0.12), true)
		draw_string(f_wide, Vector2(xpx, y0 + 50), "NEXT LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, TXT_DD)
		var ng := "5,435,888 TO GO"
		var ngs: Vector2 = f_wide.get_string_size(ng, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		draw_string(f_wide, Vector2(right - ngs.x, y0 + 50), ng, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.42, 0.60, 0.68))

		# tabs top-right corner (small) — CHARACTER active
		# (title area already used; put a slim tab strip under header)

		# --- core attribute strip ---
		var cy := y0 + 92.0
		var ch := 74.0
		var cgap := 12.0
		var cn := CORE.size()
		var cw: float = (right - x0 - float(cn - 1) * cgap) / float(cn)
		for i in cn:
			var e = CORE[i]
			_attr_box(Rect2(x0 + float(i) * (cw + cgap), cy, cw, ch), str(e[0]), str(e[1]), float(e[2]))

		# --- three stat columns ---
		var coly := cy + ch + 16.0
		var eq_h := 92.0
		var met_h := 74.0
		var colh := (pr.position.y + pr.size.y - 26.0) - met_h - 12.0 - eq_h - 14.0 - coly
		var col_gap := 16.0
		var col_w: float = (right - x0 - 2.0 * col_gap) / 3.0
		_stat_column(Rect2(x0, coly, col_w, colh), "OFFENSE", 0, OFFENSE, GOLD)
		_stat_column(Rect2(x0 + col_w + col_gap, coly, col_w, colh), "DEFENSE", 12, DEFENSE, CYAN)
		_stat_column(Rect2(x0 + 2.0 * (col_w + col_gap), coly, col_w, colh), "UTILITY", 11, UTILITY,
			Color(0.56, 0.82, 1.0))

		# --- equipment row ---
		var eqy := coly + colh + 14.0
		_label_caps(Vector2(x0, eqy - 4), "EQUIPPED", TXT_D, 9)
		var en := CH_EQUIP.size()
		var egap := 12.0
		var ecell: float = minf(eq_h, (right - x0 - float(en - 1) * egap) / float(en))
		var etotal := float(en) * ecell + float(en - 1) * egap
		var ex := x0 + (right - x0 - etotal) * 0.5
		for i in en:
			var s = CH_EQUIP[i]
			_slot(Rect2(ex + float(i) * (ecell + egap), eqy + 6.0, ecell, ecell),
				int(s[1]), int(s[2]), 0, RTAG[int(s[1])], str(s[0]))

		# --- metrics row ---
		var my := eqy + 6.0 + eq_h + 14.0
		var mn := METRICS.size()
		var mgap := 12.0
		var mw: float = (right - x0 - float(mn - 1) * mgap) / float(mn)
		for i in mn:
			var e2 = METRICS[i]
			_metric(Rect2(x0 + float(i) * (mw + mgap), my, mw, met_h), str(e2[0]), str(e2[1]))

	func _attr_box(r: Rect2, name: String, val: String, frac: float) -> void:
		_card(r)
		var cx := r.position.x + r.size.x * 0.5
		var vs: Vector2 = f_bold.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		draw_string(f_bold, Vector2(cx - vs.x * 0.5, r.position.y + 34), val,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.92, 0.96, 0.99))
		var ns: Vector2 = f_wide.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		draw_string(f_wide, Vector2(cx - ns.x * 0.5, r.position.y + 50), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.58, 0.72, 0.80))
		# mini bar
		var bar := Rect2(r.position.x + 12, r.position.y + r.size.y - 14, r.size.x - 24, 4.0)
		draw_rect(bar, Color(0.04, 0.10, 0.14, 0.9), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0.0, 1.0), bar.size.y)),
			CYAN, true)

	func _stat_column(r: Rect2, title: String, iconkind: int, rows: Array, accent: Color) -> void:
		_card(r)
		# title + accent glyph
		_stat_glyph(iconkind, Vector2(r.position.x + 18, r.position.y + 20), accent)
		draw_string(f_wide, Vector2(r.position.x + 34, r.position.y + 24), title.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
		draw_rect(Rect2(r.position.x + 34 + f_wide.get_string_size(title, 0, -1, 12).x + 10,
			r.position.y + 19, r.position.x + r.size.x - 14 - (r.position.x + 34 + f_wide.get_string_size(title, 0, -1, 12).x + 10), 1),
			Color(accent.r, accent.g, accent.b, 0.3), true)
		var sy := r.position.y + 40.0
		var rh: float = (r.size.y - 50.0) / float(rows.size())
		for row in rows:
			_stat_row(r.position.x + 16, sy, r.size.x - 32, str(row[0]), str(row[1]), _valcol(str(row[2])))
			sy += rh

	func _stat_glyph(kind: int, c: Vector2, col: Color) -> void:
		match kind:
			0:  # offense — crossed sword (up)
				draw_line(c + Vector2(0, -6), c + Vector2(0, 5), col, 2.0, true)
				draw_line(c + Vector2(-4, 3), c + Vector2(4, 3), col, 1.6, true)
			12:  # defense — shield
				var sh := PackedVector2Array([
					c + Vector2(-5, -5), c + Vector2(5, -5), c + Vector2(5, 1),
					c + Vector2(0, 6), c + Vector2(-5, 1)])
				draw_polyline(sh, col, 1.6, true)
			_:  # utility — star
				_diamond(c, 5.0, col)

	func _metric(r: Rect2, val: String, name: String) -> void:
		_card(r)
		draw_string(f_bold, Vector2(r.position.x + 14, r.position.y + 32), val,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.96, 0.99))
		draw_string(f_wide, Vector2(r.position.x + 14, r.position.y + 52), name.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.50, 0.66, 0.74))

	# ---------------------------------------------------------------- shared bits
	func _card(r: Rect2) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.039, 0.086, 0.122, 0.72)
		sb.border_color = PLINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		draw_style_box(sb, r)
		# faint top sheen
		draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1)),
			Color(0.47, 0.86, 1.0, 0.06), true)

	func _card_title(pos: Vector2, title: String, accent: Color) -> void:
		draw_string(f_wide, pos, title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)

	func _stat_row(x: float, y: float, w: float, name: String, val: String, valcol: Color) -> void:
		draw_string(f_wide, Vector2(x, y + 11), name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.62, 0.75, 0.83))
		var vs: Vector2 = f_num.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(f_num, Vector2(x + w - vs.x, y + 11), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, valcol)
		draw_rect(Rect2(x, y + 17, w, 1), Color(0.224, 0.843, 1.0, 0.07), true)

	func _valcol(style: String) -> Color:
		match style:
			"hl": return CYAN
			"gold": return GOLD
			"ae": return AETHER
			_: return Color(0.92, 0.96, 0.99)

	func _label_caps(pos: Vector2, txt: String, col: Color, sz: int, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			var s: Vector2 = f_wide.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
			draw_string(f_wide, Vector2(pos.x - s.x * 0.5, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		else:
			draw_string(f_wide, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

	func _tabs(right_pos: Vector2, active: int) -> void:
		# draw right-aligned tab strip; compute widths first
		var pad := 20.0
		var gap := 6.0
		var widths: Array[float] = []
		var total := 0.0
		for i in TABS.size():
			var tw: float = f_wide.get_string_size(TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + pad * 2.0
			widths.append(tw)
			total += tw + gap
		var x := right_pos.x - total + gap
		var h := 30.0
		var y := right_pos.y
		for i in TABS.size():
			var w: float = widths[i]
			var r := Rect2(x, y, w, h)
			var on: bool = i == active
			var sb := StyleBoxFlat.new()
			if on:
				sb.bg_color = Color(0.20, 0.70, 0.90, 0.95)
				sb.border_color = Color(0.5, 0.92, 1.0, 0.8)
			else:
				sb.bg_color = Color(0.04, 0.09, 0.13, 0.6)
				sb.border_color = PLINE
			sb.set_border_width_all(1)
			sb.corner_radius_top_left = 8
			sb.corner_radius_top_right = 8
			draw_style_box(sb, r)
			var tcol: Color = Color(0.02, 0.08, 0.11) if on else Color(0.55, 0.72, 0.80)
			var ts: Vector2 = f_wide.get_string_size(TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string(f_wide, Vector2(x + (w - ts.x) * 0.5, y + 20), TABS[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tcol)
			x += w + gap

	func _draw_ellipse(c: Vector2, r: Vector2, col: Color) -> void:
		var p := PackedVector2Array()
		var n := 40
		for i in n:
			var a: float = TAU * float(i) / float(n)
			p.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		draw_colored_polygon(p, col)
