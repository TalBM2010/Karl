extends Node
## HUD — "GALACTIC OBSERVATION PROTOCOL" broadcast overlay.
##
## A full Diablo-IV-style ARPG HUD wrapped in a galaxy-wide livestream frame. Everything is
## built in code (Control / Panel / Label + custom `_draw` widgets) on a CanvasLayer that sits
## over the 3D scene. The centre of the screen is deliberately left empty so gameplay reads.
##
## Layout (design space is 1600x1000; every block is edge-anchored so it scales):
##   top     — broadcast bar (title / node id / clock) and the hidden boss bar
##   left    — audience feed (viewers + alien chat) and specimen vitals
##   right   — sector map, objectives, combat analysis
##   bottom  — D4 dock (HP orb, skill bar, resource orb) and the galactic chat ticker
##
## Public API for other modules:
##   show_boss(name, subtitle, level) / set_boss_hp(cur, maxv) / hide_boss()
##   set_objective(title, main_text) / set_vitals(hp, maxhp, energy, maxenergy)
##   push_chat(name, text) / set_stat(key, value) / notify(text)

const DW := 1600.0
const DH := 1000.0

const CYAN := Color(0.224, 0.843, 1.0)
const CYAN_M := Color(0.224, 0.843, 1.0, 0.62)
const CYAN_L := Color(0.224, 0.843, 1.0, 0.24)
const GOLD := Color(1.0, 0.812, 0.416)
const GOLD_D := Color(0.72, 0.56, 0.26)
const RED := Color(0.93, 0.24, 0.24)
const TXT := Color(0.80, 0.88, 0.94)
const TXT_D := Color(0.50, 0.62, 0.70)
const TXT_DD := Color(0.36, 0.47, 0.55)

var game = null
var layer: CanvasLayer
var root: Control

# fonts
var f_base: Font
var f_wide: FontVariation      # letter-spaced small-caps labels
var f_title: FontVariation     # very wide, bold — the broadcast title
var f_bold: FontVariation
var f_huge: FontVariation
var f_num: FontVariation

# state ------------------------------------------------------------------
var t := 0.0
var viewers := 17812356112.0
var _chat_t := 0.0
var _chat_rows: Array[ChatRow] = []
var _chat_i := 0
var _stamp_back := 0
var _last_n := -1
var _last_l := -1
var _fire_t := 0.6

var hp := 15932.0
var hp_max := 16800.0
var res := 1293.0
var res_max := 1600.0
var adrenaline := 0.62
var donut_hp := 0.88
var donut_focus := 0.71
var donut_mood := 0.94

var dps := 1_204_000.0
var crit_rate := 38.7
var kills := 247
var battle_t := 462.0

var lbl_clock: Label
var lbl_view_big: Label
var lbl_view_exact: Label
var live_chip: Deco
var lbl_dps: Label
var lbl_crit: Label
var lbl_kills: Label
var lbl_dur: Label
var lbl_obj_title: Label
var lbl_obj_main: Label
var obj_box: Control
var spark: Spark
var vspark: Spark
var minimap: Minimap
var orb_hp: Orb
var orb_res: Orb
var skillbar: SkillBar
var pips: BuffPips
var ticker: Ticker
var boss: BossBar
var vit_bars: Array[Bar] = []

var _auto_boss := true
var _boss_hp := 40_280_000.0
var _boss_max := 53_000_000.0

const NAMES := [
	"Xy'Rathul", "Vrakka-Zor", "Zolborg Prime", "Meel'Varg", "Qor'Thess",
	"Blorgok", "Lumae-9", "Nebulon Synth", "G'Harok", "Uur'Nok",
]
const NCOLS := [
	Color(0.68, 0.44, 1.0), Color(1.0, 0.45, 0.35), Color(0.35, 1.0, 0.72),
	Color(1.0, 0.72, 0.30), Color(0.30, 0.86, 1.0), Color(0.55, 1.0, 0.42),
	Color(0.42, 0.72, 1.0), Color(0.90, 0.42, 0.86), Color(1.0, 0.55, 0.55),
	Color(0.75, 0.82, 0.40),
]
const LINES := [
	"CARL IS UNRESTRICTED! ", "LOOK AT THAT FORM!", "Princess Donut reigns supreme. ",
	"Damage numbers are OFF THE CHARTS!", "DISGUSTINGLY STRONG!",
	"I have wagered my third moon on this human.", "BEST FIGHT EVER",
	"Those crystal arachnids won't know what hit them.",
	"Physical specimen = peak.", "This will be studied for millennia.",
	"BRO IS ON ANOTHER PLANET", "The showrunners are SWEATING.",
	"Somebody sedate the Juicer.", "Carl, my brood salutes you.",
	"THE CAT. THE CAT. THE CAT.", "Ratings just broke the sector cap.",
]

# =========================================================================
func setup(g) -> void:
	game = g
	_mk_fonts()

	layer = CanvasLayer.new()
	layer.name = "HUDLayer"
	layer.layer = 10
	add_child(layer)

	root = Control.new()
	root.name = "HUD"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_topbar()
	_build_audience()
	_build_vitals()
	_build_right()
	_build_dock()
	_build_boss()
	_build_ticker()

	var frame := Deco.new()
	frame.kind = "frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(frame)

	for i in range(8, 0, -1):
		_stamp_back = i * 9 + (randi() % 5)
		_push_chat_auto()
	_stamp_back = 0

	if game and game.has_signal("hero_attacked"):
		game.hero_attacked.connect(_on_attack)
	if game and game.has_signal("enemy_killed"):
		game.enemy_killed.connect(_on_kill)
	if game and game.has_signal("floor_changed"):
		game.floor_changed.connect(_on_floor)

# --- fonts ---------------------------------------------------------------
func _mk_fonts() -> void:
	f_base = ThemeDB.fallback_font
	f_wide = _fv(3, 0.0)
	f_title = _fv(9, 0.62)
	f_bold = _fv(0, 0.55)
	f_huge = _fv(0, 0.40)
	f_num = _fv(1, 0.35)

func _fv(spacing: int, embolden: float) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = f_base
	v.spacing_glyph = spacing
	v.variation_embolden = embolden
	return v

## Strip glyphs the bundled font cannot render (emoji etc.) so nothing shows as tofu.
func _san(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c == 32 or c == 10:
			out += s[i]
		elif f_base.has_char(c):
			out += s[i]
	return out.strip_edges(false, true)

# --- small builders ------------------------------------------------------
func _place(c: Control, r: Rect2, ax: String, ay: String) -> void:
	match ax:
		"l":
			c.anchor_left = 0.0; c.anchor_right = 0.0
			c.offset_left = r.position.x; c.offset_right = r.position.x + r.size.x
		"r":
			c.anchor_left = 1.0; c.anchor_right = 1.0
			c.offset_left = r.position.x - DW; c.offset_right = r.position.x + r.size.x - DW
		"c":
			c.anchor_left = 0.5; c.anchor_right = 0.5
			c.offset_left = r.position.x - DW * 0.5; c.offset_right = r.position.x + r.size.x - DW * 0.5
		"w":
			c.anchor_left = 0.0; c.anchor_right = 1.0
			c.offset_left = r.position.x; c.offset_right = -(DW - r.position.x - r.size.x)
	match ay:
		"t":
			c.anchor_top = 0.0; c.anchor_bottom = 0.0
			c.offset_top = r.position.y; c.offset_bottom = r.position.y + r.size.y
		"b":
			c.anchor_top = 1.0; c.anchor_bottom = 1.0
			c.offset_top = r.position.y - DH; c.offset_bottom = r.position.y + r.size.y - DH

func _panel_sb(border: Color = CYAN_L, bg: Color = Color(0.020, 0.047, 0.071, 0.88)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 10
	return s

func _panel(parent: Control, r: Rect2, ax: String, ay: String, fili: bool = true) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _panel_sb())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	parent.add_child(p)
	_place(p, r, ax, ay)
	# glass sheen
	var g := TextureRect.new()
	var tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.78, 1.0, 0.11))
	grad.set_color(1, Color(0.35, 0.78, 1.0, 0.0))
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 64
	g.texture = tex
	g.set_anchors_preset(Control.PRESET_TOP_WIDE)
	g.offset_bottom = 46
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(g)
	if fili:
		var f := Fili.new()
		f.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(f)
	return p

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

func _glow(l: Label, col: Color, sz: int) -> Label:
	l.add_theme_color_override("font_outline_color", col)
	l.add_theme_constant_override("outline_size", sz)
	return l

## Section heading: letter-spaced small-caps cyan label + a hairline rule under it.
func _head(parent: Control, txt: String, pos: Vector2, w: float) -> Label:
	var l := _lab(parent, txt.to_upper(), f_wide, 10, CYAN_M, pos)
	var rule := ColorRect.new()
	rule.color = Color(0.224, 0.843, 1.0, 0.20)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	rule.position = Vector2(pos.x, pos.y + 16)
	rule.size = Vector2(w, 1)
	return l

# =========================================================================
# 1. TOP BAR
# =========================================================================
func _build_topbar() -> void:
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.035, 0.055, 0.80)
	sb.border_color = Color(0.224, 0.843, 1.0, 0.30)
	sb.border_width_bottom = 1
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_place(bar, Rect2(0, 0, DW, 36), "w", "t")

	var glowline := Deco.new()
	glowline.kind = "topglow"
	glowline.set_anchors_preset(Control.PRESET_FULL_RECT)
	glowline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(glowline)

	# left — live broadcast
	var d := Deco.new()
	d.kind = "diamond"
	d.col = CYAN
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(d)
	d.position = Vector2(14, 13)
	d.size = Vector2(9, 9)
	_lab(bar, "LIVE BROADCAST · THE UNDERDEEP", f_wide, 11, Color(0.55, 0.80, 0.90), Vector2(30, 11))

	# centre — title
	var title := _lab(bar, "GALACTIC OBSERVATION PROTOCOL", f_title, 18,
		Color(0.66, 0.96, 1.0), Vector2(0, 7), DW, HORIZONTAL_ALIGNMENT_CENTER)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_left = 0.0
	title.offset_right = 0.0
	title.offset_top = 7.0
	title.offset_bottom = 31.0
	_glow(title, Color(0.10, 0.62, 0.86, 0.60), 8)
	for k in 2:
		var hair := ColorRect.new()
		hair.color = Color(0.224, 0.843, 1.0, 0.22)
		hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(hair)
		hair.anchor_left = 0.5; hair.anchor_right = 0.5
		hair.offset_top = 17; hair.offset_bottom = 18
		if k == 0:
			hair.offset_left = -370; hair.offset_right = -252
		else:
			hair.offset_left = 252; hair.offset_right = 370

	# right — node + clock
	var rl := _lab(bar, "OBSERVATION NODE: XK-77 / ALPHA", f_wide, 11, Color(0.48, 0.66, 0.76),
		Vector2(DW - 420, 11), 300, HORIZONTAL_ALIGNMENT_RIGHT)
	rl.clip_text = true
	rl.anchor_left = 1.0; rl.anchor_right = 1.0
	rl.offset_left = -420; rl.offset_right = -116
	rl.offset_top = 11; rl.offset_bottom = 29
	var div := ColorRect.new()
	div.color = Color(0.224, 0.843, 1.0, 0.30)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(div)
	div.anchor_left = 1.0; div.anchor_right = 1.0
	div.offset_left = -108; div.offset_right = -107
	div.offset_top = 10; div.offset_bottom = 26
	lbl_clock = _lab(bar, "00:00:00", f_num, 13, CYAN, Vector2(DW - 100, 9), 86, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_clock.clip_text = true
	lbl_clock.anchor_left = 1.0; lbl_clock.anchor_right = 1.0
	lbl_clock.offset_left = -100; lbl_clock.offset_right = -14
	lbl_clock.offset_top = 9; lbl_clock.offset_bottom = 29
	_glow(lbl_clock, Color(0.06, 0.40, 0.60, 0.5), 4)

# =========================================================================
# 2. LEFT — AUDIENCE FEED
# =========================================================================
func _build_audience() -> void:
	var p := _panel(root, Rect2(12, 46, 268, 546), "l", "t")
	_lab(p, "INTER-SECTOR", f_wide, 10, CYAN_M, Vector2(12, 10))
	_lab(p, "AUDIENCE FEED", f_wide, 10, CYAN_M, Vector2(12, 23))

	live_chip = Deco.new()
	live_chip.kind = "live"
	live_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(live_chip)
	live_chip.position = Vector2(268 - 66, 10)
	live_chip.size = Vector2(54, 16)

	_lab(p, "TOTAL VIEWERS", f_wide, 9, TXT_DD, Vector2(12, 44))
	lbl_view_big = _lab(p, "17.8B", f_huge, 42, Color(0.93, 0.98, 1.0), Vector2(10, 54))
	_glow(lbl_view_big, Color(0.10, 0.55, 0.80, 0.42), 6)
	lbl_view_exact = _lab(p, "17,812,356,112", f_num, 11, Color(0.40, 0.62, 0.74), Vector2(12, 104))

	vspark = Spark.new()
	vspark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vspark.col = Color(0.30, 0.78, 1.0, 0.80)
	vspark.fill = true
	vspark.size = Vector2(104, 40)
	vspark.position = Vector2(152, 58)
	p.add_child(vspark)

	var rule := ColorRect.new()
	rule.color = Color(0.224, 0.843, 1.0, 0.16)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(rule)
	rule.position = Vector2(12, 126)
	rule.size = Vector2(244, 1)

	var y := 133.0
	for i in 8:
		var r := ChatRow.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.f_name = f_bold
		r.f_body = f_base
		r.f_time = f_num
		r.size = Vector2(248, 50)
		r.position = Vector2(11, y)
		p.add_child(r)
		_chat_rows.append(r)
		y += 50

# =========================================================================
# 3. BOTTOM-LEFT — SPECIMEN VITALS
# =========================================================================
func _build_vitals() -> void:
	var p := _panel(root, Rect2(12, 778, 268, 186), "l", "b")
	_head(p, "SPECIMEN VITALS", Vector2(12, 9), 244)

	vit_bars = []
	_vit_block(p, 34, "CARL", "LVL 78", Color(0.62, 0.42, 0.30),
		[["HP", RED], ["ENERGY", Color(0.30, 0.72, 1.0)], ["ADRENALINE", Color(1.0, 0.62, 0.20)]])
	_vit_block(p, 112, "PRINCESS DONUT", "LVL 78", Color(0.40, 0.28, 0.22),
		[["HP", RED], ["FOCUS", Color(0.72, 0.45, 1.0)], ["MOOD", Color(1.0, 0.78, 0.30)]])

func _vit_block(p: Control, y: float, nm: String, lv: String, pc: Color, bars: Array) -> void:
	var port := Deco.new()
	port.kind = "portrait"
	port.col = pc
	port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(port)
	port.position = Vector2(12, y)
	port.size = Vector2(42, 54)

	_lab(p, nm, f_bold, 12, Color(0.92, 0.96, 1.0), Vector2(60, y - 3))
	_lab(p, lv, f_wide, 9, GOLD, Vector2(268 - 64, y - 1), 52, HORIZONTAL_ALIGNMENT_RIGHT)

	var by := y + 15.0
	for b in bars:
		var bar := Bar.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.col = b[1]
		bar.tag = b[0]
		bar.f = f_wide
		p.add_child(bar)
		bar.position = Vector2(60, by)
		bar.size = Vector2(196, 15)
		vit_bars.append(bar)
		by += 17

# =========================================================================
# 4. RIGHT COLUMN
# =========================================================================
func _build_right() -> void:
	# --- sector map ---
	var mp := _panel(root, Rect2(1318, 46, 270, 208), "r", "t")
	_head(mp, "SECTOR MAP", Vector2(12, 9), 246)
	_lab(mp, "GRID 7-DELTA", f_wide, 9, TXT_DD, Vector2(12, 9), 246, HORIZONTAL_ALIGNMENT_RIGHT)
	minimap = Minimap.new()
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp.add_child(minimap)
	minimap.position = Vector2(12, 32)
	minimap.size = Vector2(246, 164)

	# --- objectives ---
	var op := _panel(root, Rect2(1318, 262, 270, 132), "r", "t")
	_head(op, "OBJECTIVES", Vector2(12, 9), 246)
	lbl_obj_title = _lab(op, "THE CRYSTAL DEPTHS", f_wide, 11, GOLD, Vector2(12, 32))
	_glow(lbl_obj_title, Color(0.55, 0.38, 0.08, 0.40), 4)

	obj_box = Deco.new()
	obj_box.kind = "check"
	obj_box.col = CYAN_M
	obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	op.add_child(obj_box)
	obj_box.position = Vector2(13, 53)
	obj_box.size = Vector2(10, 10)
	lbl_obj_main = _lab(op, "Eliminate the Crystalline Arachnids", f_base, 11, TXT, Vector2(30, 50), 226)
	lbl_obj_main.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_obj_main.size = Vector2(226, 30)

	var b2 := Deco.new()
	b2.kind = "check"
	b2.col = GOLD_D
	b2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	op.add_child(b2)
	b2.position = Vector2(13, 87)
	b2.size = Vector2(10, 10)
	var lb := _lab(op, "Bonus: Keep Princess Donut unharmed", f_base, 11, GOLD, Vector2(30, 84), 226)
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size = Vector2(226, 30)

	# --- combat analysis ---
	var cp := _panel(root, Rect2(1318, 402, 270, 148), "r", "t")
	_head(cp, "COMBAT ANALYSIS", Vector2(12, 9), 246)
	lbl_dps = _stat_row(cp, 34, "DAMAGE PER SECOND", "1.2M")
	lbl_crit = _stat_row(cp, 54, "CRITICAL STRIKE RATE", "38.7%")
	lbl_kills = _stat_row(cp, 74, "ENEMIES ELIMINATED", "247")
	lbl_dur = _stat_row(cp, 94, "BATTLE DURATION", "00:07:42")
	spark = Spark.new()
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.col = Color(0.30, 0.85, 1.0, 0.70)
	spark.fill = true
	cp.add_child(spark)
	spark.position = Vector2(12, 114)
	spark.size = Vector2(246, 26)

func _stat_row(p: Control, y: float, k: String, v: String) -> Label:
	_lab(p, k, f_wide, 10, TXT_D, Vector2(12, y))
	var l := _lab(p, v, f_num, 12, CYAN, Vector2(12, y - 1), 246, HORIZONTAL_ALIGNMENT_RIGHT)
	l.position = Vector2(12, y - 1)
	return l

# =========================================================================
# 5. BOTTOM CENTRE — D4 DOCK
# =========================================================================
func _build_dock() -> void:
	var dock := Control.new()
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dock)
	_place(dock, Rect2(340, 830, 920, 170), "c", "b")

	orb_hp = Orb.new()
	orb_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb_hp.col = Color(0.86, 0.13, 0.14)
	orb_hp.top = Color(1.0, 0.42, 0.34)
	orb_hp.f = f_num
	dock.add_child(orb_hp)
	orb_hp.position = Vector2(58, 4)
	orb_hp.size = Vector2(128, 128)

	orb_res = Orb.new()
	orb_res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb_res.col = Color(0.10, 0.36, 0.92)
	orb_res.top = Color(0.42, 0.78, 1.0)
	orb_res.f = f_num
	dock.add_child(orb_res)
	orb_res.position = Vector2(920 - 58 - 128, 4)
	orb_res.size = Vector2(128, 128)

	pips = BuffPips.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.f = f_num
	dock.add_child(pips)
	pips.position = Vector2(920 * 0.5 - 190, 12)
	pips.size = Vector2(380, 20)

	skillbar = SkillBar.new()
	skillbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skillbar.f = f_wide
	skillbar.fnum = f_num
	dock.add_child(skillbar)
	skillbar.position = Vector2(920 * 0.5 - 259, 40)
	skillbar.size = Vector2(518, 78)

	# experience track + level diamond, sitting between the two orbs (D4 dock)
	var lp := Deco.new()
	lp.kind = "xpbar"
	lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lp.f = f_num
	lp.f2 = f_wide
	dock.add_child(lp)
	lp.position = Vector2(920 * 0.5 - 262, 106)
	lp.size = Vector2(524, 26)

# =========================================================================
# 6. TOP CENTRE — BOSS BAR
# =========================================================================
func _build_boss() -> void:
	boss = BossBar.new()
	boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss.f_name = _fv(6, 0.55)
	boss.f_sub = f_wide
	boss.f_num = f_num
	boss.f_small = f_wide
	root.add_child(boss)
	_place(boss, Rect2(DW * 0.5 - 340, 42, 680, 104), "c", "t")
	boss.visible = false

func show_boss(nm: String, subtitle: String, level: int) -> void:
	_auto_boss = false
	boss.bname = _san(nm.to_upper())
	boss.bsub = _san(subtitle.to_upper())
	boss.blevel = level
	boss.visible = true
	boss.intro = 0.0

func set_boss_hp(cur: float, maxv: float) -> void:
	_auto_boss = false
	_boss_hp = cur
	_boss_max = max(1.0, maxv)
	boss.cur = cur
	boss.maxv = _boss_max

func hide_boss() -> void:
	_auto_boss = false
	boss.visible = false

# =========================================================================
# 7. BOTTOM STRIP — TICKER
# =========================================================================
func _build_ticker() -> void:
	var strip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.035, 0.055, 0.90)
	sb.border_color = Color(0.224, 0.843, 1.0, 0.26)
	sb.border_width_top = 1
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.clip_contents = true
	root.add_child(strip)
	_place(strip, Rect2(0, 970, DW, 30), "w", "b")

	ticker = Ticker.new()
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker.f = f_base
	ticker.fb = f_bold
	ticker.set_anchors_preset(Control.PRESET_FULL_RECT)
	ticker.offset_left = 210
	strip.add_child(ticker)

	# soft fade so half-words entering the strip dissolve instead of being chopped
	var fade := TextureRect.new()
	var ftex := GradientTexture2D.new()
	var fgrad := Gradient.new()
	fgrad.set_color(0, Color(0.012, 0.035, 0.055, 0.92))
	fgrad.set_color(1, Color(0.012, 0.035, 0.055, 0.0))
	ftex.gradient = fgrad
	ftex.fill_from = Vector2(0, 0)
	ftex.fill_to = Vector2(1, 0)
	ftex.width = 64
	ftex.height = 8
	fade.texture = ftex
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(fade)
	fade.position = Vector2(206, 0)
	fade.size = Vector2(78, 30)

	var chip := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.05, 0.16, 0.22, 0.98)
	cs.border_color = Color(0.224, 0.843, 1.0, 0.35)
	cs.border_width_right = 1
	chip.add_theme_stylebox_override("panel", cs)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(chip)
	chip.position = Vector2(0, 0)
	chip.size = Vector2(206, 30)
	chip.anchor_bottom = 1.0
	chip.offset_bottom = 0
	chip.clip_contents = true
	_lab(chip, "GALACTIC CHAT TICKER", f_wide, 10, CYAN, Vector2(16, 9))

	var segs: Array = []
	for i in 10:
		var n: String = NAMES[i % NAMES.size()]
		var m: String = _san(LINES[(i * 3 + 1) % LINES.size()])
		segs.append([n, NCOLS[i % NCOLS.size()], m])
	ticker.segs = segs

# =========================================================================
# PUBLIC API
# =========================================================================
func set_objective(title: String, main_text: String) -> void:
	lbl_obj_title.text = _san(title.to_upper())
	lbl_obj_main.text = _san(main_text)

func set_vitals(h: float, mh: float, e: float, me: float) -> void:
	hp = h; hp_max = max(1.0, mh); res = e; res_max = max(1.0, me)

func set_stat(key: String, value: String) -> void:
	match key:
		"dps": lbl_dps.text = value
		"crit": lbl_crit.text = value
		"kills": lbl_kills.text = value
		"duration": lbl_dur.text = value

func push_chat(nm: String, txt: String) -> void:
	var idx := NAMES.find(nm)
	var col: Color = NCOLS[(idx if idx >= 0 else _chat_i) % NCOLS.size()]
	var stamp := _stamp(_stamp_back)
	for i in range(_chat_rows.size() - 1):
		var a: ChatRow = _chat_rows[i]
		var b: ChatRow = _chat_rows[i + 1]
		a.set_msg(b.nm, b.ncol, b.stamp, b.body)
	var last: ChatRow = _chat_rows[_chat_rows.size() - 1]
	last.set_msg(_san(nm), col, stamp, _san(txt))
	last.modulate.a = 0.0
	_chat_i += 1

func notify(txt: String) -> void:
	push_chat(NAMES[randi() % NAMES.size()], txt)

func _push_chat_auto() -> void:
	var ni := randi() % NAMES.size()
	while ni == _last_n:
		ni = randi() % NAMES.size()
	var li := randi() % LINES.size()
	while li == _last_l:
		li = randi() % LINES.size()
	_last_n = ni
	_last_l = li
	push_chat(NAMES[ni], LINES[li])

## Local-time HH:MM:SS, optionally back-dated by `back` seconds.
func _stamp(back: int) -> String:
	var tz: Dictionary = Time.get_time_zone_from_system()
	var bias := int(tz.get("bias", 0)) * 60
	return Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system()) + bias - back)

# =========================================================================
# SIGNALS
# =========================================================================
func _on_attack(_pos: Vector3, damage: int, crit: bool) -> void:
	res = clamp(res - 210.0, 0.0, res_max)
	adrenaline = clamp(adrenaline + 0.05, 0.0, 1.0)
	dps = lerp(dps, float(damage) * (2.6 if crit else 1.4) * 1000.0, 0.12)
	if boss.visible:
		_boss_hp = max(0.0, _boss_hp - float(damage) * 240.0)
		boss.cur = _boss_hp
		boss.maxv = _boss_max
		boss.hit = 1.0
	if skillbar:
		skillbar.fire(randi() % 9)

func _on_kill(_pos: Vector3) -> void:
	kills += 1
	adrenaline = clamp(adrenaline + 0.12, 0.0, 1.0)

func _on_floor(index: int) -> void:
	var names := ["THE RUINED BOROUGH", "THE BRAMBLE", "THE IRON TANGLE", "THE CRYSTAL DEPTHS"]
	set_objective(names[clamp(index, 0, names.size() - 1)], "Eliminate the hostile specimens")

# =========================================================================
# TICK
# =========================================================================
func _process(delta: float) -> void:
	t += delta

	lbl_clock.text = Time.get_time_string_from_system()

	# viewers keep climbing
	viewers += (3_100_000.0 + sin(t * 0.7) * 900_000.0) * delta
	lbl_view_big.text = "%.1fB" % (viewers / 1e9)
	lbl_view_exact.text = _commas(int(viewers))

	# chat feed
	_chat_t -= delta
	if _chat_t <= 0.0:
		_chat_t = randf_range(1.1, 2.3)
		_push_chat_auto()
	for r in _chat_rows:
		if r.modulate.a < 1.0:
			r.modulate.a = min(1.0, r.modulate.a + delta * 4.0)

	# vitals drift
	hp = clamp(hp_max * (0.70 + sin(t * 0.55) * 0.17 + sin(t * 1.9) * 0.03), hp_max * 0.20, hp_max)
	res = clamp(res + 165.0 * delta, 0.0, res_max)
	adrenaline = clamp(adrenaline - 0.05 * delta, 0.0, 1.0)
	donut_focus = 0.62 + sin(t * 0.6) * 0.16
	donut_mood = 0.90 + sin(t * 1.7) * 0.08
	if vit_bars.size() >= 6:
		vit_bars[0].set_v(hp / hp_max, "%s / %s" % [_commas(int(hp)), _commas(int(hp_max))])
		vit_bars[1].set_v(res / res_max, "%d%%" % int(res / res_max * 100.0))
		vit_bars[2].set_v(adrenaline, "%d%%" % int(adrenaline * 100.0))
		vit_bars[3].set_v(donut_hp, "%d%%" % int(donut_hp * 100.0))
		vit_bars[4].set_v(donut_focus, "%d%%" % int(donut_focus * 100.0))
		vit_bars[5].set_v(donut_mood, "%d%%" % int(donut_mood * 100.0))

	# orbs
	orb_hp.fill = hp / hp_max
	orb_hp.t = t
	orb_hp.txt = "%s / %s" % [_commas(int(hp)), _commas(int(hp_max))]
	orb_hp.queue_redraw()
	orb_res.fill = res / res_max
	orb_res.t = t
	orb_res.txt = "%s / %s" % [_commas(int(res)), _commas(int(res_max))]
	orb_res.queue_redraw()

	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = randf_range(0.7, 1.5)
		var slot := randi() % 9
		skillbar.fire(slot)
		res = clamp(res - randf_range(150.0, 320.0), 0.0, res_max)
		adrenaline = clamp(adrenaline + 0.07, 0.0, 1.0)
	skillbar.tick(delta)
	pips.tick(delta)
	ticker.tick(delta)
	live_chip.t = t
	live_chip.queue_redraw()

	# combat analysis
	battle_t += delta
	dps = lerp(dps, 1_204_000.0 + sin(t * 1.3) * 180_000.0, 0.03)
	crit_rate = 38.7 + sin(t * 0.45) * 1.4
	lbl_dps.text = "%.1fM" % (dps / 1e6)
	lbl_crit.text = "%.1f%%" % crit_rate
	lbl_kills.text = str(kills)
	lbl_dur.text = "%02d:%02d:%02d" % [int(battle_t) / 3600, (int(battle_t) / 60) % 60, int(battle_t) % 60]
	spark.push(dps / 1e6)
	spark.queue_redraw()
	vspark.push(viewers / 1e9 + sin(t * 2.3) * 0.004)
	vspark.queue_redraw()

	# minimap
	if game and "hero_pos" in game:
		minimap.hero = Vector2(game.hero_pos.x, game.hero_pos.z)
	minimap.t = t
	minimap.queue_redraw()

	# boss demo — hidden by default; auto-revealed for the broadcast if nothing drives it
	if _auto_boss:
		if not boss.visible and t > 1.8:
			boss.bname = "JUICER"
			boss.bsub = "ENHANCED BEYOND NATURAL LIMITS"
			boss.blevel = 78
			boss.visible = true
			boss.intro = 0.0
		if boss.visible:
			_boss_hp = max(_boss_max * 0.12, _boss_hp - _boss_max * 0.018 * delta)
			boss.cur = _boss_hp
			boss.maxv = _boss_max
	boss.tick(delta)

static func _commas(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# =========================================================================
# WIDGETS
# =========================================================================
class U:
	static func ccw(p: PackedVector2Array) -> PackedVector2Array:
		if Geometry2D.is_polygon_clockwise(p):
			var q := PackedVector2Array(p)
			q.reverse()
			return q
		return p

	static func circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
		var p := PackedVector2Array()
		for i in n:
			var a := TAU * float(i) / float(n)
			p.append(c + Vector2(cos(a), sin(a)) * r)
		return ccw(p)


## Thin corner brackets on panels.
class Fili extends Control:
	var col := Color(0.45, 0.92, 1.0, 0.80)
	var ln := 13.0
	func _draw() -> void:
		var w := 1.0
		var s := size
		var pts := [
			[Vector2(0, ln), Vector2(0, 0), Vector2(ln, 0)],
			[Vector2(s.x - ln, 0), Vector2(s.x, 0), Vector2(s.x, ln)],
			[Vector2(s.x, s.y - ln), Vector2(s.x, s.y), Vector2(s.x - ln, s.y)],
			[Vector2(ln, s.y), Vector2(0, s.y), Vector2(0, s.y - ln)],
		]
		for p in pts:
			draw_polyline(PackedVector2Array(p), col, 1.4, true)


## Small stateless decorations: diamond, live chip, portrait, checkbox, level pip, top glow.
class Deco extends Control:
	var kind := "diamond"
	var col := Color(0.224, 0.843, 1.0)
	var t := 0.0
	var f: Font
	var f2: Font

	func _draw() -> void:
		match kind:
			"diamond": _diamond()
			"live": _live()
			"portrait": _portrait()
			"check": _check()
			"xpbar": _xpbar()
			"topglow": _topglow()
			"frame": _frame()

	func _diamond() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		var p := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(p, col)

	func _frame() -> void:
		var m := 5.0
		var ln := 34.0
		var c1 := Color(0.224, 0.843, 1.0, 0.30)
		var w := size.x
		var h := size.y
		var corners := [
			[Vector2(m, m + ln), Vector2(m, m), Vector2(m + ln, m)],
			[Vector2(w - m - ln, m), Vector2(w - m, m), Vector2(w - m, m + ln)],
			[Vector2(w - m, h - m - ln), Vector2(w - m, h - m), Vector2(w - m - ln, h - m)],
			[Vector2(m + ln, h - m), Vector2(m, h - m), Vector2(m, h - m - ln)],
		]
		for p in corners:
			draw_polyline(PackedVector2Array(p), c1, 1.6, true)
		draw_rect(Rect2(m, m, w - m * 2.0, h - m * 2.0), Color(0.224, 0.843, 1.0, 0.07), false, 1.0)

	func _topglow() -> void:
		for i in 8:
			draw_line(Vector2(0, size.y - i), Vector2(size.x, size.y - i),
				Color(0.224, 0.843, 1.0, 0.055 - i * 0.006), 1.0)

	func _live() -> void:
		var pulse := 0.55 + 0.45 * sin(t * 5.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.35, 0.04, 0.06, 0.65)
		sb.border_color = Color(1.0, 0.25, 0.28, 0.35 + 0.35 * pulse)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var c := Vector2(11, size.y * 0.5)
		draw_circle(c, 5.0 + pulse * 2.0, Color(1.0, 0.22, 0.24, 0.22))
		draw_circle(c, 3.2, Color(1.0, 0.32 + 0.2 * pulse, 0.30))
		if f2 == null:
			f2 = ThemeDB.fallback_font
		draw_string(f2, Vector2(20, size.y - 4.5), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(1.0, 0.62, 0.62))

	func _portrait() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.09, 0.13, 0.95)
		sb.border_color = Color(0.224, 0.843, 1.0, 0.35)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# stylised head+shoulders silhouette
		var c := Vector2(size.x * 0.5, size.y * 0.40)
		draw_circle(c, size.x * 0.20, col)
		var w := size.x * 0.40
		var p := PackedVector2Array([
			Vector2(c.x - w, size.y - 4), Vector2(c.x - w * 0.72, c.y + size.y * 0.16),
			Vector2(c.x + w * 0.72, c.y + size.y * 0.16), Vector2(c.x + w, size.y - 4)])
		draw_colored_polygon(p, col.darkened(0.15))
		draw_line(Vector2(1, 1), Vector2(size.x - 1, 1), Color(0.6, 0.9, 1.0, 0.18), 1.0)

	func _check() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.08, 0.8), true)
		draw_rect(Rect2(Vector2.ZERO, size), col, false, 1.0)

	func _xpbar() -> void:
		if f == null:
			f = ThemeDB.fallback_font
		if f2 == null:
			f2 = f
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var frac := 0.62
		var tr := Rect2(0, c.y - 3.0, size.x, 6.0)
		draw_rect(tr, Color(0.02, 0.05, 0.075, 0.92), true)
		draw_rect(tr, Color(0.224, 0.843, 1.0, 0.20), false, 1.0)
		draw_rect(Rect2(1, c.y - 2.0, (size.x - 2.0) * frac, 4.0), Color(1.0, 0.78, 0.34), true)
		draw_rect(Rect2(1, c.y - 2.0, (size.x - 2.0) * frac, 2.0), Color(1.0, 0.92, 0.66), true)
		for i in range(1, 10):
			var x := size.x * float(i) / 10.0
			draw_line(Vector2(x, c.y - 3.0), Vector2(x, c.y + 3.0), Color(0, 0, 0, 0.45), 1.0)
		# level diamond
		var r := 12.0
		var p := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(p, Color(0.03, 0.08, 0.12, 0.98))
		draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]),
			Color(1.0, 0.812, 0.416, 0.85), 1.4, true)
		var s := f.get_string_size("78", HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		draw_string(f, c + Vector2(-s.x * 0.5, 4), "78", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.88, 0.58))
		draw_string(f2, Vector2(size.x + 6.0, c.y + 3.0), "XP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(0.62, 0.50, 0.28))


## Thin labelled vitals bar.
class Bar extends Control:
	var v := 1.0
	var shown := 1.0
	var col := Color(1, 0, 0)
	var tag := ""
	var txt := ""
	var f: Font

	func set_v(nv: float, s: String) -> void:
		v = clamp(nv, 0.0, 1.0)
		txt = s
		queue_redraw()

	func _draw() -> void:
		shown = lerpf(shown, v, 0.25)
		if f == null:
			f = ThemeDB.fallback_font
		# caption row
		draw_string(f, Vector2(0, 8), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.50, 0.63, 0.71))
		var vs := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		draw_string(f, Vector2(size.x - vs.x, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(0.86, 0.93, 0.98))
		# track
		var r := Rect2(0, 10, size.x, 5)
		draw_rect(r, Color(0.03, 0.06, 0.09, 0.95), true)
		draw_rect(r, Color(0.35, 0.55, 0.68, 0.20), false, 1.0)
		var w := (size.x - 2.0) * shown
		if w > 1.0:
			draw_rect(Rect2(1, 11, w, 3), col.darkened(0.20), true)
			draw_rect(Rect2(1, 11, w, 1.5), col.lightened(0.30), true)
			draw_rect(Rect2(1 + w - 1.5, 11, 1.5, 3), col.lightened(0.65), true)
		for i in range(1, 5):
			var x := 1.0 + (size.x - 2.0) * float(i) / 5.0
			draw_line(Vector2(x, 10), Vector2(x, 15), Color(0, 0, 0, 0.40), 1.0)


## One row of the alien chat feed.
class ChatRow extends Control:
	var nm := ""
	var body := ""
	var stamp := ""
	var ncol := Color(1, 1, 1)
	var f_name: Font
	var f_body: Font
	var f_time: Font
	var _l_name: Label
	var _l_time: Label
	var _l_body: Label
	var _av: ColorRect

	func _ready() -> void:
		clip_contents = true
		_av = ColorRect.new()
		_av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_av)
		_av.position = Vector2(2, 2)
		_av.size = Vector2(11, 11)
		_l_name = _mk(f_name, 12, Color(1, 1, 1), Vector2(19, 0), 150)
		_l_time = _mk(f_time, 9, Color(0.36, 0.46, 0.53), Vector2(size.x - 66, 2), 62)
		_l_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_l_body = _mk(f_body, 11, Color(0.74, 0.83, 0.89), Vector2(19, 15), size.x - 22)
		_l_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_l_body.size = Vector2(size.x - 22, 33)
		_apply()

	func _mk(f: Font, fs: int, c: Color, p: Vector2, w: float) -> Label:
		var l := Label.new()
		if f != null:
			l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", c)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		l.position = p
		l.size = Vector2(w, l.size.y)
		return l

	func set_msg(n: String, c: Color, s: String, b: String) -> void:
		nm = n; ncol = c; stamp = s; body = b
		if _l_name != null:
			_apply()

	func _apply() -> void:
		_av.color = ncol
		_l_name.text = nm
		_l_name.add_theme_color_override("font_color", ncol)
		_l_time.text = stamp
		_l_body.text = body


## Liquid-filled spherical orb with glass rim.
class Orb extends Control:
	var fill := 1.0
	var t := 0.0
	var col := Color(0.86, 0.13, 0.14)
	var top := Color(1.0, 0.4, 0.35)
	var txt := ""
	var f: Font

	func _draw() -> void:
		if f == null:
			f = ThemeDB.fallback_font
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0

		# outer bloom
		for i in range(7, 0, -1):
			draw_circle(c, r + float(i) * 2.4, Color(col.r, col.g, col.b, 0.035))
		# socket
		draw_circle(c, r + 3.0, Color(0.02, 0.045, 0.065, 0.95))
		draw_arc(c, r + 3.0, 0, TAU, 72, Color(0.224, 0.843, 1.0, 0.30), 1.5, true)
		# empty well
		draw_circle(c, r, Color(0.03, 0.035, 0.05, 0.98))
		draw_circle(c, r * 0.98, Color(col.r * 0.16, col.g * 0.16, col.b * 0.16, 0.85))

		# liquid
		var inner := r - 1.5
		var lvl: float = c.y + inner * (1.0 - 2.0 * clampf(fill, 0.0, 1.0))
		var water := PackedVector2Array()
		var steps := 34
		for i in range(steps + 1):
			var x := c.x - inner - 2.0 + (inner * 2.0 + 4.0) * float(i) / float(steps)
			var y := lvl + sin(t * 2.1 + float(i) * 0.42) * 2.8 + sin(t * 3.3 + float(i) * 0.17) * 1.7
			water.append(Vector2(x, y))
		water.append(Vector2(c.x + inner + 2.0, c.y + inner + 6.0))
		water.append(Vector2(c.x - inner - 2.0, c.y + inner + 6.0))
		var body := U.circle(c, inner, 64)
		var res := Geometry2D.intersect_polygons(body, U.ccw(water))
		for poly in res:
			var cols := PackedColorArray()
			for p in poly:
				var k: float = clampf((p.y - (c.y - inner)) / (inner * 2.0), 0.0, 1.0)
				cols.append(top.lerp(col.darkened(0.28), k))
			draw_polygon(poly, cols)
		# surface highlight
		var surf := PackedVector2Array()
		for p in water:
			if (p - c).length() < inner - 0.5:
				surf.append(p)
		if surf.size() > 2:
			draw_polyline(surf, Color(1, 1, 1, 0.45), 1.6, true)

		# inner shading + specular
		draw_arc(c, r * 0.86, PI * 1.12, PI * 1.82, 28, Color(1, 1, 1, 0.16), 5.0, true)
		draw_circle(c + Vector2(-r * 0.34, -r * 0.40), r * 0.14, Color(1, 1, 1, 0.20))
		draw_arc(c, r * 0.92, PI * 0.15, PI * 0.85, 28, Color(0, 0, 0, 0.28), 6.0, true)

		# glass rim
		draw_arc(c, r, 0, TAU, 72, Color(0.72, 0.90, 1.0, 0.55), 2.0, true)
		draw_arc(c, r - 2.0, PI * 1.05, PI * 1.95, 32, Color(1, 1, 1, 0.35), 1.4, true)

		# value
		var s := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var tp := Vector2(c.x - s.x * 0.5, c.y + 4.5)
		draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.85))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.97))


## Nine-slot action bar with distinct vector icons, key hints and cooldown sweeps.
class SkillBar extends Control:
	const KEYS := ["L-Click", "1", "2", "3", "4", "Q", "E", "R", "R-Click"]
	const COLS := [
		Color(1.0, 0.52, 0.22), Color(1.0, 0.80, 0.25), Color(1.0, 0.30, 0.30),
		Color(0.72, 0.40, 1.0), Color(0.30, 0.86, 1.0), Color(1.0, 0.70, 0.35),
		Color(0.45, 1.0, 0.62), Color(0.40, 0.70, 1.0), Color(0.95, 0.35, 0.55),
	]
	const CD_MAX := [0.0, 6.0, 9.0, 12.0, 18.0, 4.0, 14.0, 45.0, 0.0]
	var cd := [0.0, 2.4, 0.0, 7.1, 11.0, 0.0, 5.2, 28.4, 0.0]
	var glow := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var t := 0.0
	var f: Font
	var fnum: Font
	const N := 9
	const SW := 50.0
	const GAP := 8.5

	func fire(i: int) -> void:
		i = clamp(i, 0, N - 1)
		glow[i] = 1.0
		if CD_MAX[i] > 0.0 and cd[i] <= 0.0:
			cd[i] = CD_MAX[i]

	func tick(d: float) -> void:
		t += d
		for i in N:
			if cd[i] > 0.0:
				cd[i] = max(0.0, cd[i] - d)
			if glow[i] > 0.0:
				glow[i] = max(0.0, glow[i] - d * 2.2)
		queue_redraw()

	func _draw() -> void:
		if f == null:
			f = ThemeDB.fallback_font
		if fnum == null:
			fnum = f
		# backing rail
		var rail := StyleBoxFlat.new()
		rail.bg_color = Color(0.015, 0.04, 0.062, 0.72)
		rail.border_color = Color(0.224, 0.843, 1.0, 0.20)
		rail.set_border_width_all(1)
		rail.set_corner_radius_all(4)
		rail.shadow_color = Color(0, 0, 0, 0.5)
		rail.shadow_size = 10
		draw_style_box(rail, Rect2(-6, -6, size.x + 12, 62))

		for i in N:
			var x := float(i) * (SW + GAP)
			var r := Rect2(x, 0, SW, SW)
			var c: Color = COLS[i]
			var ready: bool = cd[i] <= 0.0

			# slot plate
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.045, 0.075, 0.10, 0.98)
			sb.border_color = Color(c.r, c.g, c.b, 0.55 if ready else 0.22)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(3)
			draw_style_box(sb, r)
			# inner radial wash
			var cc := r.position + r.size * 0.5
			for k in range(6, 0, -1):
				draw_circle(cc, float(k) * 4.0, Color(c.r, c.g, c.b, (0.10 if ready else 0.04)))

			_icon(i, cc, 13.0, Color(c.r, c.g, c.b, 1.0 if ready else 0.45))

			# cooldown radial sweep
			if not ready:
				var frac: float = cd[i] / CD_MAX[i]
				var poly := PackedVector2Array([cc])
				var a0 := -PI * 0.5
				var steps := 26
				for k in range(steps + 1):
					var a := a0 + TAU * frac * float(k) / float(steps)
					poly.append(cc + Vector2(cos(a), sin(a)) * 44.0)
				var clipped := Geometry2D.intersect_polygons(
					U.ccw(poly), U.ccw(PackedVector2Array([
						r.position, r.position + Vector2(r.size.x, 0), r.position + r.size,
						r.position + Vector2(0, r.size.y)])))
				for p in clipped:
					draw_colored_polygon(p, Color(0.01, 0.03, 0.055, 0.82))
				var ea := a0 + TAU * frac
				draw_line(cc, cc + Vector2(cos(ea), sin(ea)) * 20.0,
					Color(c.r, c.g, c.b, 0.75), 1.4, true)
				draw_rect(r, Color(c.r, c.g, c.b, 0.10), true)
				var s2 := fnum.get_string_size("%d" % ceil(cd[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
				draw_string_outline(fnum, cc + Vector2(-s2.x * 0.5, 5), "%d" % ceil(cd[i]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.85))
				draw_string(fnum, cc + Vector2(-s2.x * 0.5, 5), "%d" % ceil(cd[i]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.93, 1.0))

			# cast flash
			if glow[i] > 0.0:
				draw_rect(r, Color(1, 1, 1, 0.35 * glow[i]), true)
				draw_rect(r.grow(2.0 * glow[i]), Color(c.r, c.g, c.b, 0.7 * glow[i]), false, 2.0)

			# top bevel
			draw_line(r.position + Vector2(1, 1), r.position + Vector2(SW - 1, 1),
				Color(1, 1, 1, 0.12), 1.0)

			# key hint
			var kt: String = KEYS[i]
			var ks := f.get_string_size(kt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			var kp := Vector2(x + SW * 0.5 - ks.x * 0.5, SW + 12.0)
			draw_string(f, kp, kt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.52, 0.66, 0.75))

	func _icon(kind: int, c: Vector2, s: float, col: Color) -> void:
		var w := 2.0
		match kind:
			0:  # cleave — crescent slash
				draw_arc(c + Vector2(-s * 0.3, 0), s * 0.95, -PI * 0.55, PI * 0.55, 20, col, w + 1.0, true)
				draw_arc(c + Vector2(-s * 0.3, 0), s * 0.60, -PI * 0.45, PI * 0.45, 16, col, w * 0.7, true)
			1:  # whirlwind — three sweeping arcs
				for k in 3:
					var a := TAU * float(k) / 3.0
					draw_arc(c, s * 0.85, a, a + 1.5, 14, col, w, true)
			2:  # leap — chevrons + impact line
				for k in 2:
					var o := -s * 0.5 + float(k) * s * 0.6
					draw_polyline(PackedVector2Array([
						c + Vector2(-s * 0.7, o + s * 0.4), c + Vector2(0, o - s * 0.15),
						c + Vector2(s * 0.7, o + s * 0.4)]), col, w, true)
			3:  # shout — concentric arcs
				for k in 3:
					draw_arc(c + Vector2(-s * 0.4, 0), s * (0.35 + 0.28 * float(k)),
						-PI * 0.42, PI * 0.42, 14, col, w * 0.85, true)
				draw_circle(c + Vector2(-s * 0.55, 0), 2.4, col)
			4:  # frost nova — hex ring + spokes
				var hp := PackedVector2Array()
				for k in 7:
					var a := TAU * float(k) / 6.0 - PI * 0.5
					hp.append(c + Vector2(cos(a), sin(a)) * s * 0.85)
				draw_polyline(hp, col, w, true)
				for k in 6:
					var a2 := TAU * float(k) / 6.0
					draw_line(c, c + Vector2(cos(a2), sin(a2)) * s * 0.45, col, w * 0.7, true)
			5:  # dash — motion streaks
				for k in 3:
					var y := -s * 0.55 + float(k) * s * 0.55
					draw_line(c + Vector2(-s * 0.9, y), c + Vector2(s * 0.2 + float(k) * 4.0, y), col, w, true)
				draw_polyline(PackedVector2Array([
					c + Vector2(s * 0.25, -s * 0.55), c + Vector2(s * 0.9, 0),
					c + Vector2(s * 0.25, s * 0.55)]), col, w, true)
			6:  # heal — cross + pulse ring
				draw_line(c + Vector2(0, -s * 0.8), c + Vector2(0, s * 0.8), col, w + 1.2, true)
				draw_line(c + Vector2(-s * 0.8, 0), c + Vector2(s * 0.8, 0), col, w + 1.2, true)
				draw_arc(c, s * 1.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.4), w * 0.6, true)
			7:  # ultimate — starburst diamond
				var d := PackedVector2Array([
					c + Vector2(0, -s), c + Vector2(s * 0.42, 0), c + Vector2(0, s), c + Vector2(-s * 0.42, 0)])
				draw_colored_polygon(d, Color(col.r, col.g, col.b, 0.85))
				for k in 4:
					var a3 := TAU * float(k) / 4.0 + PI * 0.25
					draw_line(c + Vector2(cos(a3), sin(a3)) * s * 0.45,
						c + Vector2(cos(a3), sin(a3)) * s * 1.05, col, w * 0.8, true)
			8:  # block — shield
				var sp := PackedVector2Array([
					c + Vector2(-s * 0.75, -s * 0.7), c + Vector2(s * 0.75, -s * 0.7),
					c + Vector2(s * 0.75, s * 0.15), c + Vector2(0, s * 0.9),
					c + Vector2(-s * 0.75, s * 0.15)])
				sp.append(sp[0])
				draw_polyline(sp, col, w, true)
				draw_line(c + Vector2(0, -s * 0.45), c + Vector2(0, s * 0.5), col, w * 0.7, true)


## Row of small buff / timer pips above the skill bar.
class BuffPips extends Control:
	var t := 0.0
	var f: Font
	const DATA := [
		["Berserk", Color(1.0, 0.42, 0.25), 4.0],
		["Iron Skin", Color(0.55, 0.78, 1.0), 8.0],
		["Cat's Grace", Color(1.0, 0.80, 0.35), 6.0],
		["Overcharge", Color(0.72, 0.42, 1.0), 2.0],
		["Bloodlust", Color(1.0, 0.30, 0.42), 12.0],
		["Sponsor Buff", Color(0.35, 1.0, 0.72), 10.0],
	]
	var left := [4.0, 8.0, 6.0, 2.0, 12.0, 10.0]

	func tick(d: float) -> void:
		t += d
		for i in left.size():
			left[i] -= d
			if left[i] <= 0.0:
				left[i] = DATA[i][2] * randf_range(0.8, 1.6)
		queue_redraw()

	func _draw() -> void:
		if f == null:
			f = ThemeDB.fallback_font
		var n := DATA.size()
		var w := 44.0
		var g := 7.0
		var total := float(n) * w + float(n - 1) * g
		var x0 := (size.x - total) * 0.5
		for i in n:
			var c: Color = DATA[i][1]
			var r := Rect2(x0 + float(i) * (w + g), 0, w, size.y)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.04, 0.08, 0.11, 0.9)
			sb.border_color = Color(c.r, c.g, c.b, 0.55)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(2)
			draw_style_box(sb, r)
			# remaining-time underfill
			var frac: float = clamp(left[i] / float(DATA[i][2]), 0.0, 1.0)
			draw_rect(Rect2(r.position.x + 1, r.position.y + r.size.y - 3.0,
				(r.size.x - 2.0) * frac, 2.0), c, true)
			draw_circle(r.position + Vector2(8, r.size.y * 0.5), 3.0, c)
			var s := "%ds" % ceil(left[i])
			draw_string(f, r.position + Vector2(16, r.size.y * 0.5 + 4.0), s,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.80, 0.88, 0.94))


## Faint sparkline / area chart.
class Spark extends Control:
	var vals := PackedFloat32Array()
	var col := Color(0.3, 0.85, 1.0, 0.7)
	var fill := false
	var _acc := 0.0

	func push(v: float) -> void:
		_acc += 1.0
		if _acc < 2.0:
			return
		_acc = 0.0
		vals.append(v)
		while vals.size() > 48:
			vals.remove_at(0)

	func _draw() -> void:
		if vals.size() < 2:
			return
		var lo := vals[0]
		var hi := vals[0]
		for v in vals:
			lo = minf(lo, v); hi = maxf(hi, v)
		var rng: float = max(0.0001, hi - lo)
		var pts := PackedVector2Array()
		for i in vals.size():
			var x := size.x * float(i) / float(vals.size() - 1)
			var y := size.y - 2.0 - (size.y - 5.0) * ((vals[i] - lo) / rng)
			pts.append(Vector2(x, y))
		if fill:
			var poly := PackedVector2Array(pts)
			poly.append(Vector2(size.x, size.y))
			poly.append(Vector2(0, size.y))
			draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.13))
		draw_polyline(pts, col, 1.3, true)
		draw_circle(pts[pts.size() - 1], 2.0, Color(col.r, col.g, col.b, 1.0))


## Dark sector minimap with rooms, corridors and a glowing hero blip.
class Minimap extends Control:
	var hero := Vector2.ZERO
	var t := 0.0
	var rooms: Array = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20991
		for i in 9:
			rooms.append(Rect2(rng.randf_range(0.05, 0.72), rng.randf_range(0.05, 0.70),
				rng.randf_range(0.13, 0.24), rng.randf_range(0.13, 0.24)))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.035, 0.055, 0.95), true)
		# grid
		for i in range(1, 10):
			var x := size.x * float(i) / 10.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.20, 0.55, 0.70, 0.10), 1.0)
		for i in range(1, 7):
			var y := size.y * float(i) / 7.0
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.20, 0.55, 0.70, 0.10), 1.0)
		# rooms + corridors
		var prev := Vector2(-1, -1)
		for r in rooms:
			var rr := Rect2(r.position * size, r.size * size)
			draw_rect(rr, Color(0.09, 0.24, 0.32, 0.85), true)
			draw_rect(rr, Color(0.224, 0.843, 1.0, 0.28), false, 1.0)
			var ctr := rr.position + rr.size * 0.5
			if prev.x >= 0.0:
				draw_line(prev, Vector2(ctr.x, prev.y), Color(0.224, 0.843, 1.0, 0.16), 1.0)
				draw_line(Vector2(ctr.x, prev.y), ctr, Color(0.224, 0.843, 1.0, 0.16), 1.0)
			prev = ctr
		# radar sweep
		var c := size * 0.5
		var a := fmod(t * 0.9, TAU)
		for k in 16:
			var aa := a - float(k) * 0.035
			draw_line(c, c + Vector2(cos(aa), sin(aa)) * size.x * 0.75,
				Color(0.224, 0.843, 1.0, 0.09 - float(k) * 0.005), 1.0)
		# hero blip
		var hp := c + Vector2(clamp(hero.x, -14.0, 14.0), clamp(hero.y, -14.0, 14.0)) / 14.0 * (size * 0.42)
		var pulse := 0.5 + 0.5 * sin(t * 3.4)
		draw_circle(hp, 9.0 + pulse * 4.0, Color(0.224, 0.843, 1.0, 0.10))
		draw_circle(hp, 5.0 + pulse * 1.5, Color(0.224, 0.843, 1.0, 0.22))
		draw_circle(hp, 3.0, Color(0.80, 0.98, 1.0))
		# a couple of hostile marks
		for k in 4:
			var ha := t * 0.4 + float(k) * 1.7
			var hpos := c + Vector2(cos(ha), sin(ha)) * (size.x * (0.16 + 0.06 * float(k)))
			draw_circle(hpos, 2.2, Color(1.0, 0.32, 0.30, 0.85))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.224, 0.843, 1.0, 0.22), false, 1.0)


## Segmented boss health bar with affix pips.
class BossBar extends Control:
	var bname := "JUICER"
	var bsub := "ENHANCED BEYOND NATURAL LIMITS"
	var blevel := 78
	var cur := 53_000_000.0
	var maxv := 53_000_000.0
	var shown := 1.0
	var hit := 0.0
	var intro := 1.0
	var t := 0.0
	var f_name: Font
	var f_sub: Font
	var f_num: Font
	var f_small: Font
	const AFFIX := ["Massive Physique", "Steroid Overload", "Unstoppable", "Rage Pump"]

	func tick(d: float) -> void:
		if not visible:
			return
		t += d
		intro = min(1.0, intro + d * 2.2)
		hit = max(0.0, hit - d * 1.6)
		var target: float = clamp(cur / max(1.0, maxv), 0.0, 1.0)
		shown = lerp(shown, target, 0.10)
		queue_redraw()

	func _draw() -> void:
		if f_name == null:
			f_name = ThemeDB.fallback_font
			f_sub = f_name; f_num = f_name; f_small = f_name
		var e: float = intro * intro
		var w := size.x * e
		var cx := size.x * 0.5
		modulate.a = e
		# soft dark scrim so the bar reads over bright scenes
		for i in 22:
			var k := float(i) / 21.0
			draw_rect(Rect2(cx - w * 0.5 * (1.0 - k * 0.18), float(i) * 4.4,
				w * (1.0 - k * 0.18), 4.6), Color(0.02, 0.02, 0.04, 0.34 * (1.0 - k)), true)

		# name
		var ns := f_name.get_string_size(bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var np := Vector2(cx - ns.x * 0.5, 24)
		draw_string_outline(f_name, np, bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, Color(0.10, 0.0, 0.0, 0.85))
		draw_string(f_name, np, bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.94, 0.90))
		# subtitle
		var ss := f_sub.get_string_size(bsub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(f_sub, Vector2(cx - ss.x * 0.5, 40), bsub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.78, 0.62, 0.58))

		# bar geometry
		var bx := cx - w * 0.5 + 34.0
		var bw := w - 68.0
		if bw < 20.0:
			return
		var by := 50.0
		var bh := 18.0
		var r := Rect2(bx, by, bw, bh)

		# frame
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.02, 0.03, 0.92)
		sb.border_color = Color(0.55, 0.20, 0.20, 0.85)
		sb.set_border_width_all(1)
		draw_style_box(sb, r.grow(2.0))

		# fill
		var fw := (bw - 2.0) * shown
		if fw > 1.0:
			var fr := Rect2(bx + 1, by + 1, fw, bh - 2)
			draw_rect(fr, Color(0.62, 0.07, 0.08), true)
			draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.48)), Color(0.85, 0.16, 0.16), true)
			draw_rect(Rect2(fr.position + Vector2(0, fr.size.y * 0.48), Vector2(fr.size.x, 2)),
				Color(1.0, 0.45, 0.35, 0.45), true)
			draw_line(Vector2(bx + 1 + fw, by + 1), Vector2(bx + 1 + fw, by + bh - 1),
				Color(1.0, 0.75, 0.55, 0.9 * (0.6 + 0.4 * sin(t * 6.0))), 2.0)
		# segments
		for i in range(1, 16):
			var x := bx + (bw - 2.0) * float(i) / 16.0
			draw_line(Vector2(x, by + 1), Vector2(x, by + bh - 1), Color(0, 0, 0, 0.45), 1.0)
		if hit > 0.0:
			draw_rect(r, Color(1, 1, 1, 0.22 * hit), true)

		# numbers
		var pct: float = shown * 100.0
		var txt := "%s / %s (%.1f%%)" % [_cm(int(cur)), _cm(int(maxv)), pct]
		var ts := f_num.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var tp := Vector2(cx - ts.x * 0.5, by + 13)
		draw_string_outline(f_num, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.85))
		draw_string(f_num, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.94, 0.92))

		# level diamond
		var dc := Vector2(bx - 20.0, by + bh * 0.5)
		var dr := 15.0
		var dp := PackedVector2Array([dc + Vector2(0, -dr), dc + Vector2(dr, 0), dc + Vector2(0, dr), dc + Vector2(-dr, 0)])
		draw_colored_polygon(dp, Color(0.08, 0.02, 0.03, 0.96))
		draw_polyline(PackedVector2Array([dp[0], dp[1], dp[2], dp[3], dp[0]]), Color(0.90, 0.32, 0.28, 0.95), 1.5, true)
		var ls := str(blevel)
		var lsz := f_num.get_string_size(ls, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(f_num, dc + Vector2(-lsz.x * 0.5, 4.5), ls, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1.0, 0.86, 0.80))

		# affix pips
		var ax := 0.0
		var widths: Array[float] = []
		var total := 0.0
		for a in AFFIX:
			var aw: float = f_small.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 26.0
			widths.append(aw)
			total += aw
		ax = cx - total * 0.5
		for i in AFFIX.size():
			var pc: Color = Color(1.0, 0.42, 0.30) if i < 2 else Color(0.55, 0.80, 1.0)
			var y := by + bh + 15.0
			draw_circle(Vector2(ax + 7, y - 3.5), 3.4, pc)
			draw_circle(Vector2(ax + 7, y - 3.5), 6.0, Color(pc.r, pc.g, pc.b, 0.16))
			draw_string(f_small, Vector2(ax + 16, y), AFFIX[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.78, 0.84, 0.90))
			ax += widths[i]


	static func _cm(n: int) -> String:
		var s := str(n)
		var out := ""
		var c := 0
		for i in range(s.length() - 1, -1, -1):
			out = s[i] + out
			c += 1
			if c % 3 == 0 and i > 0:
				out = "," + out
		return out


## Horizontally scrolling galactic chat ticker.
class Ticker extends Control:
	var segs: Array = []
	var off := 0.0
	var f: Font
	var fb: Font
	var _w := 0.0

	func tick(d: float) -> void:
		off += d * 58.0
		if _w > 0.0 and off > _w:
			off -= _w
		queue_redraw()

	func _draw() -> void:
		if f == null:
			f = ThemeDB.fallback_font
		if fb == null:
			fb = f
		if segs.is_empty():
			return
		if _w <= 0.0:
			_w = 0.0
			for s in segs:
				_w += fb.get_string_size(s[0] + ": ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				_w += f.get_string_size(s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 44.0
		var y := size.y * 0.5 + 4.0
		var x := -off
		var pass_i := 0
		while x < size.x and pass_i < 3:
			for s in segs:
				var nt: String = s[0] + ": "
				var nw: float = fb.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				var bw: float = f.get_string_size(s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				if x + nw + bw > -20.0 and x < size.x + 20.0:
					draw_string(fb, Vector2(x, y), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, s[1])
					draw_string(f, Vector2(x + nw, y), s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
						Color(0.62, 0.74, 0.82))
					draw_circle(Vector2(x + nw + bw + 20.0, y - 4.0), 2.0, Color(0.224, 0.843, 1.0, 0.5))
				x += nw + bw + 44.0
			pass_i += 1
