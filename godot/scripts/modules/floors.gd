extends Node
## FLOOR PROGRESSION + "THE SYSTEM" floor-intro broadcast.
##
## Owns the Dungeon-Crawler-Carl floor order (Floor 1 ruined neighborhood -> Floor 2 the Bramble
## -> Floor 3 the Iron Tangle / Over City) and a full-screen "System" announcement overlay that
## the sardonic in-world AI showrunner drops between floors: blue system-text, dry/menacing
## showbiz tone, a live audience react feed, and a NEW OBJECTIVE chip.
##
## Built entirely in code (Control + custom `_draw`) on its OWN CanvasLayer sitting ABOVE the HUD,
## styled to match hud.gd (thin sci-fi bevels, cyan-family glow, corner filigree). It takes over
## the frame during the FIRST window of a ~16s demo cycle, holds readable, animates out to reveal
## gameplay, then cycles Floor 1 -> 2 -> 3. The out-animation is a function of ABSOLUTE cycle time
## (not per-frame weights) so it never pops at the ~2-8fps the software-Vulkan capture renders.
##
## Contract: `setup(g)`; `g` exposes world/carl/cam/hero_pos/hero_face/modules and the
## `floor_changed(index)` signal the HUD listens to. On every floor change we emit that signal.

const DW := 1600.0
const DH := 1000.0

# Panel geometry in design space.
const FW := 760.0
const FH := 470.0

# Timeline is in PROCESS-seconds. Under software Vulkan the engine clamps frame delta to
# ~0.14s, so process-time advances at ~0.14s per RENDERED frame (not wall time): a short capture
# (warm 6 + a few gaps of 10) spans only ~6-7 process-seconds — i.e. exactly Floor 1's window.
# The intro is tuned to be fully readable across the first ~3 shots and cleanly gone by ~4.5s so
# later shots reveal gameplay. A LONGER capture (t>=16) rolls into Floor 2, then Floor 3.
const CYCLE := 16.0          # process-seconds per floor in the demo loop
const T_IN := 0.7            # animate-in ends
const T_HOLD := 3.8          # hold ends
const T_OUT := 4.5           # animate-out ends; dismissed afterwards

const GOLD := Color(1.0, 0.812, 0.416)
const WHITE := Color(0.95, 0.98, 1.0)
const TXT := Color(0.84, 0.90, 0.94)
const TXT_D := Color(0.55, 0.68, 0.76)

var game = null
var layer: CanvasLayer
var root: Control
var scrim: TextureRect
var box: SysFrame

# fonts
var f_base: Font
var f_wide: FontVariation
var f_num: FontVariation
var f_huge: FontVariation

# updated labels / decorations
var lbl_num: Label
var lbl_name: Label
var lbl_sub: Label
var lbl_sys: Label
var lbl_obj: Label
var rule: ColorRect
var react_sw: Array[ColorRect] = []
var react_nm: Array[Label] = []
var react_tx: Array[Label] = []

var t := 0.0
var _cur_cycle := -1

# --- floor data ----------------------------------------------------------
# Dungeon Crawler Carl book order. `sys` is ORIGINAL copy in the System's flavour (dry, menacing,
# showbiz). `react` = audience feed lines. `accent` tints the whole announcement toward the floor.
var FLOORS := [
	{
		"n": 1, "name": "THE CRAWL", "sub": "THE COLLAPSED NEIGHBORHOOD",
		"obj": "Escape the Starter Neighborhood",
		"accent": Color(1.0, 0.58, 0.26),
		"sys": "The System welcomes you to Floor One. Your borough is now licensed content and "
			+ "property values are, frankly, catastrophic. Clear the collapsing neighborhood "
			+ "before the ceiling files the eviction on your behalf.",
		"react": [
			["Xy'Rathul", Color(1.0, 0.62, 0.30), "FRESH MEAT ON THE GROUND FLOOR"],
			["Vrakka-Zor", Color(1.0, 0.72, 0.36), "the suburbs never stood a chance"],
			["Zolborg Prime", Color(1.0, 0.45, 0.42), "subscribe for more controlled demolition"],
		],
	},
	{
		"n": 2, "name": "THE BRAMBLE", "sub": "THE OVERGROWN TRANSITION",
		"obj": "Survive the Bramble",
		"accent": Color(0.55, 1.0, 0.42),
		"sys": "Floor Two: The Bramble. Congratulations, meat — you outlasted your neighbors. "
			+ "The flora down here is considerably less sentimental, and something violet has "
			+ "already reserved your internal organs.",
		"react": [
			["Meel'Varg", Color(0.60, 1.0, 0.36), "the FLORA remains undefeated"],
			["Qor'Thess", Color(0.72, 0.50, 1.0), "wagering four thousand credits he trips"],
			["Blorgok", Color(0.55, 1.0, 0.50), "greenest gore of the whole season"],
		],
	},
	{
		"n": 3, "name": "THE IRON TANGLE", "sub": "THE OVER CITY / DESERT SET-PIECE",
		"obj": "Cross the Iron Tangle",
		"accent": Color(1.0, 0.78, 0.36),
		"sys": "Floor Three: The Over City. Mind the Iron Tangle — rust, rails and a skyline of "
			+ "dead trains. Ratings are astronomical. Cross the desert, and do try to die "
			+ "photogenically. The sponsors are watching.",
		"react": [
			["Lumae-9", Color(1.0, 0.78, 0.36), "the Over City arc is absolute peak"],
			["Nebulon Synth", Color(1.0, 0.72, 0.36), "desert set-piece equals cinema"],
			["G'Harok", Color(1.0, 0.55, 0.36), "all aboard the hype train"],
		],
	},
]

# =========================================================================
func setup(g) -> void:
	game = g
	_mk_fonts()

	layer = CanvasLayer.new()
	layer.name = "FloorIntroLayer"
	layer.layer = 20                          # above the HUD (layer 10) so it takes the frame
	add_child(layer)

	root = Control.new()
	root.name = "FloorIntro"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# radial darken — cheap "world dims for the announcement" (no backdrop blur).
	scrim = TextureRect.new()
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var stex := GradientTexture2D.new()
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(0.015, 0.04, 0.06, 0.36))
	sgrad.set_color(1, Color(0.01, 0.025, 0.045, 0.92))
	stex.gradient = sgrad
	stex.fill = GradientTexture2D.FILL_RADIAL
	stex.fill_from = Vector2(0.5, 0.44)
	stex.fill_to = Vector2(1.0, 1.0)
	stex.width = 256
	stex.height = 256
	scrim.texture = stex
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(scrim)

	box = SysFrame.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.pivot_offset = Vector2(FW * 0.5, FH * 0.5)
	root.add_child(box)
	_place_box(0.0)
	box.size = Vector2(FW, FH)

	_build_frame()

	# boot on Floor 1 immediately (its intro plays in the first window of the capture).
	_apply_floor(0)
	_cur_cycle = 0
	if game and game.has_signal("floor_changed"):
		game.floor_changed.emit(0)

# --- fonts ---------------------------------------------------------------
func _mk_fonts() -> void:
	f_base = ThemeDB.fallback_font
	f_wide = _fv(3, 0.0)
	f_num = _fv(4, 0.45)
	f_huge = _fv(1, 0.55)

func _fv(spacing: int, embolden: float) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = f_base
	v.spacing_glyph = spacing
	v.variation_embolden = embolden
	return v

## Strip glyphs the bundled font can't render (emoji etc.) so nothing shows as tofu.
func _san(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c == 32 or c == 10:
			out += s[i]
		elif f_base.has_char(c):
			out += s[i]
	return out.strip_edges(false, true)

func _lab(parent: Control, txt: String, font: Font, fs: int, col: Color, pos: Vector2,
		w: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.text = _san(txt)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	parent.add_child(l)
	l.position = pos
	if w > 0.0:
		l.size = Vector2(w, l.size.y)
	return l

func _glow(l: Label, col: Color, sz: int) -> void:
	l.add_theme_color_override("font_outline_color", col)
	l.add_theme_constant_override("outline_size", sz)

# --- build the announcement frame ---------------------------------------
func _build_frame() -> void:
	# header row — pulsing rec dot is drawn inside SysFrame at (40,34)
	_lab(box, "THE SYSTEM  //  DUNGEON BROADCAST", f_wide, 11, Color(0.62, 0.82, 0.92), Vector2(54, 26))
	var rl := _lab(box, "LIVE / GALACTIC FEED", f_wide, 10, TXT_D, Vector2(FW - 340, 28), 300,
		HORIZONTAL_ALIGNMENT_RIGHT)
	rl.clip_text = true

	var hair := ColorRect.new()
	hair.color = Color(0.35, 0.72, 0.86, 0.22)
	hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hair)
	hair.position = Vector2(40, 56)
	hair.size = Vector2(FW - 80, 1)

	lbl_num = _lab(box, "FLOOR 1", f_num, 16, GOLD, Vector2(0, 74), FW, HORIZONTAL_ALIGNMENT_CENTER)
	_glow(lbl_num, Color(0.55, 0.38, 0.08, 0.45), 4)

	lbl_name = _lab(box, "THE CRAWL", f_huge, 58, WHITE, Vector2(0, 96), FW, HORIZONTAL_ALIGNMENT_CENTER)
	_glow(lbl_name, Color(0.10, 0.30, 0.42, 0.55), 7)

	lbl_sub = _lab(box, "", f_wide, 12, Color(0.66, 0.82, 0.90), Vector2(0, 172), FW,
		HORIZONTAL_ALIGNMENT_CENTER)

	rule = ColorRect.new()
	rule.color = Color(0.35, 0.78, 0.92, 0.5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	rule.position = Vector2(FW * 0.5 - 250.0, 200)
	rule.size = Vector2(500, 1)

	lbl_sys = _lab(box, "", f_base, 15, TXT, Vector2(100, 216), 560, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_sys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_sys.size = Vector2(560, 66)

	# audience react feed — three chat chips
	var cx := 130.0
	var cw := FW - 260.0
	var y := 300.0
	for i in 3:
		var sw := ColorRect.new()
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(sw)
		sw.position = Vector2(cx, y + 3)
		sw.size = Vector2(12, 12)
		react_sw.append(sw)
		var nm := _lab(box, "", f_num, 12, WHITE, Vector2(cx + 22, y), 168)
		nm.clip_text = true
		react_nm.append(nm)
		var tx := _lab(box, "", f_base, 12, Color(0.72, 0.80, 0.86), Vector2(cx + 190, y), cw - 190)
		tx.clip_text = true
		react_tx.append(tx)
		y += 30.0

	# NEW OBJECTIVE chip
	var chip := ObjChip.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(chip)
	chip.position = Vector2(FW * 0.5 - 210.0, 402)
	chip.size = Vector2(420, 34)
	_lab(chip, "NEW OBJECTIVE", f_wide, 10, GOLD, Vector2(18, 11))
	lbl_obj = _lab(chip, "", f_base, 13, Color(1.0, 0.90, 0.70), Vector2(150, 9), 256)
	lbl_obj.clip_text = true

# --- apply a floor's content --------------------------------------------
func _apply_floor(fi: int) -> void:
	var f: Dictionary = FLOORS[fi]
	var acc: Color = f["accent"]
	box.accent = acc
	box.queue_redraw()
	lbl_num.text = "FLOOR %d" % int(f["n"])
	lbl_name.text = _san(f["name"])
	lbl_sub.text = _san(f["sub"])
	lbl_sub.add_theme_color_override("font_color", acc.lerp(Color(0.8, 0.9, 0.95), 0.45))
	lbl_sys.text = _san(f["sys"])
	rule.color = Color(acc.r, acc.g, acc.b, 0.5)
	lbl_obj.text = _san(f["obj"])
	var react: Array = f["react"]
	for i in 3:
		var r: Array = react[i]
		react_sw[i].color = r[1]
		react_nm[i].text = _san(r[0])
		react_nm[i].add_theme_color_override("font_color", r[1])
		react_tx[i].text = _san(r[2])

# --- animation timeline (absolute-time, framerate independent) -----------
## Visibility 0..1 as a pure function of time-into-cycle. Never per-frame weighted, so a 2s
## capture frame steps to the exact eased value instead of popping.
func _vis(ct: float) -> float:
	if ct < T_IN:
		return _smooth(ct / T_IN)
	elif ct < T_HOLD:
		return 1.0
	elif ct < T_OUT:
		return 1.0 - _smooth((ct - T_HOLD) / (T_OUT - T_HOLD))
	return 0.0

static func _smooth(x: float) -> float:
	var u: float = clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

func _place_box(slide: float) -> void:
	# slide: 0 = resting, 1 = fully offset (down + shrunk) when hidden
	var x := (DW - FW) * 0.5
	var y := (DH - FH) * 0.5 + 22.0 * slide
	box.position = Vector2(x, y)
	var s: float = lerpf(1.0, 0.965, slide)
	box.scale = Vector2(s, s)

func _process(delta: float) -> void:
	t += delta

	var cyc := int(t / CYCLE)
	if cyc != _cur_cycle:
		_cur_cycle = cyc
		var fi := cyc % FLOORS.size()
		_apply_floor(fi)
		if game and game.has_signal("floor_changed"):
			game.floor_changed.emit(fi)

	var ct: float = fmod(t, CYCLE)
	var v: float = _vis(ct)

	var on: bool = v > 0.003
	root.visible = on
	if not on:
		return

	root.modulate.a = v
	_place_box(1.0 - v)
	box.t = t
	box.queue_redraw()

# =========================================================================
# WIDGETS
# =========================================================================
## The announcement panel: dark rounded body, accent border + soft rounded halo, corner
## filigree, and a pulsing red "recording" dot in the header.
class SysFrame extends Control:
	var accent := Color(0.30, 0.86, 1.0)
	var t := 0.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# soft rounded halo (kept tasteful so bloom doesn't smear the bright border)
		for i in range(5, 0, -1):
			var h := StyleBoxFlat.new()
			h.draw_center = false
			h.border_color = Color(accent.r, accent.g, accent.b, 0.05)
			h.set_border_width_all(2)
			h.set_corner_radius_all(8 + i * 2)
			draw_style_box(h, r.grow(float(i * 2)))
		# body
		var p := StyleBoxFlat.new()
		p.bg_color = Color(0.02, 0.05, 0.08, 0.92)
		p.border_color = accent
		p.set_border_width_all(1)
		p.set_corner_radius_all(8)
		p.shadow_color = Color(0, 0, 0, 0.6)
		p.shadow_size = 14
		draw_style_box(p, r)
		# inner top sheen
		draw_rect(Rect2(1, 1, size.x - 2, 40), Color(accent.r, accent.g, accent.b, 0.05), true)
		# corner filigree
		var ln := 30.0
		var w := size.x
		var hh := size.y
		var fc := Color(accent.r, accent.g, accent.b, 0.9)
		var corners := [
			[Vector2(2, 2 + ln), Vector2(2, 2), Vector2(2 + ln, 2)],
			[Vector2(w - 2 - ln, 2), Vector2(w - 2, 2), Vector2(w - 2, 2 + ln)],
			[Vector2(w - 2, hh - 2 - ln), Vector2(w - 2, hh - 2), Vector2(w - 2 - ln, hh - 2)],
			[Vector2(2 + ln, hh - 2), Vector2(2, hh - 2), Vector2(2, hh - 2 - ln)],
		]
		for c in corners:
			draw_polyline(PackedVector2Array(c), fc, 2.0, true)
		# pulsing rec dot (header left)
		var pulse: float = 0.5 + 0.5 * sin(t * 4.0)
		draw_circle(Vector2(40, 32), 6.0, Color(1.0, 0.22, 0.24, 0.16 + 0.20 * pulse))
		draw_circle(Vector2(40, 32), 3.4, Color(1.0, 0.30 + 0.15 * pulse, 0.30))


## The gold-bevelled NEW OBJECTIVE chip.
class ObjChip extends Control:
	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.08, 0.03, 0.55)
		sb.border_color = Color(1.0, 0.812, 0.416, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# little target box before the label
		draw_rect(Rect2(Vector2(132, size.y * 0.5 - 6.0), Vector2(12, 12)),
			Color(0.02, 0.05, 0.08, 0.8), true)
		draw_rect(Rect2(Vector2(132, size.y * 0.5 - 6.0), Vector2(12, 12)),
			Color(1.0, 0.812, 0.416, 0.85), false, 1.0)
