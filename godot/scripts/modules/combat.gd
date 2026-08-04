extends Node
## COMBAT FEEL — floating damage numbers, impact VFX, ability VFX, camera shake.
##
## Owned by the combat/VFX engineer. Talks to the rest of the game ONLY through the module
## contract (`setup(game)`) and game.gd's signals, so nothing here depends on the enemies or
## HUD modules existing yet.
##
## What lives here:
##   1. FLOATING COMBAT TEXT — Label3D pop-ups (huge orange crits + "Critical!" sub-label,
##      white Physical, purple Aether, grey Blocked). Heavy black outline, scale-punch on
##      spawn, ballistic arcing rise, fade out.
##   2. IMPACT VFX — additive spark bursts (GPUParticles3D), a billboard impact flash with a
##      light pop, an expanding ground shock ring on crits, crystal-shard death bursts.
##   3. ABILITY VFX — Cleave (cyan crescent), Aether Nova (violet ring shockwave), Whirlwind
##      (spinning blade wreath), War Cry (ground rune + light pillar), plus a persistent
##      aether aura so Carl always reads as powered-up.
##   4. CAMERA SHAKE — decaying offset applied through Camera3D.h_offset/v_offset so it never
##      fights game.gd's camera follow and always settles back to exactly zero.
##
## Everything is POOLED and reused: software Vulkan is slow, and allocating meshes/particles
## per hit would both hitch and leak. Nothing is ever left running.

# ---------------------------------------------------------------------------- damage types
enum DmgType { PHYSICAL, CRIT, AETHER, BLOCKED }

# HDR values sit just past the glow threshold so they bloom without tonemapping to white —
# crits in particular must keep their HUE (green well under red, or orange turns yellow).
const COL_CRIT := Color(1.75, 0.58, 0.05)     # molten orange
const COL_PHYS := Color(1.25, 1.22, 1.14)     # bone white
const COL_AETHER := Color(0.72, 0.20, 1.85)   # aether violet
const COL_BLOCK := Color(0.52, 0.57, 0.63)    # dull grey

# Ability energy is drawn ADDITIVELY. It has to out-run the floor, but it must NOT out-run
# Carl: these sit only just past the white point. Two overlapping additive surfaces at 1.7 were
# summing to ~3.4 and clipping to a flat white blob once ACES + bloom got hold of them, which
# buried both the hero and the cavern. Kept near 1.0-1.4 they bloom and still hold their hue
# when they overlap.
const COL_CYAN := Color(0.24, 0.82, 1.32)
const COL_VIOLET := Color(0.38, 0.13, 1.18)
const COL_GOLD := Color(1.02, 0.60, 0.21)
const CLEAVE_COL := Color(0.34, 0.92, 1.42)   # the swing arc is the brightest transient

const TEXT_LIFE := 1.15
const MAX_TEXT := 3

var game: Node = null
var cam: Camera3D = null
var root: Node3D = null            # all VFX hang off this (a child of Main)

# --- pooling -----------------------------------------------------------------------------
var _pools: Dictionary = {}        # kind -> Array[Node] of idle nodes
var _live: Array = []              # active effects: {n, t, d, k, ...}
var _texts: Array = []             # active floating text entries

# --- shared resources --------------------------------------------------------------------
var _font: Font = null
var _tex_glow: Texture2D = null
var _tex_streak: Texture2D = null
var _tex_rune: Texture2D = null
var _tex_pillar: Texture2D = null
var _mesh_ring: ArrayMesh = null       # full 360 thin annulus (shock ring / aura)
var _mesh_ring_wide: ArrayMesh = null  # fat annulus (nova)
var _mesh_crescent: ArrayMesh = null   # 140-degree arc (cleave)
var _mesh_aura: ArrayMesh = null       # slightly fatter band for the persistent aura
var _mesh_quad: QuadMesh = null
var _mesh_blade: QuadMesh = null

# --- persistent aura ---------------------------------------------------------------------
var _aura: Node3D = null
var _aura_rings: Array = []
var _aura_motes: GPUParticles3D = null

# --- whirlwind (single instance, re-armed) ------------------------------------------------
var _whirl: Node3D = null
var _whirl_t := 0.0
var _whirl_d := 0.0

# --- camera shake ------------------------------------------------------------------------
var _shake := 0.0
var _shake_t := 0.0

# --- demo director -----------------------------------------------------------------------
# --- big-effect arbiter -------------------------------------------------------------------
## Abilities PUNCTUATE the scene; they never erase it. Only one screen-filling effect may be
## alive at a time, so the frame always falls back to "moody cavern + readable Carl" between
## beats instead of compounding four additive light shows on top of each other.
var _big_lock := 0.0

var _demo := false
var _t := 0.0
var _next_hit := 0.35
var _next_ability := 1.4
var _ability_i := 0
var _hit_i := 0
var _text_seq := 0
var _rng := RandomNumberGenerator.new()

# ==========================================================================================
#  SETUP
# ==========================================================================================
func setup(g) -> void:
	game = g
	cam = g.cam if "cam" in g else null
	_rng.seed = 20250804

	root = Node3D.new()
	root.name = "CombatFX"
	g.add_child(root)

	_build_resources()
	_build_aura()
	_build_whirlwind()

	# React to the rest of the game if/when it starts talking to us.
	if g.has_signal("hero_attacked"):
		g.hero_attacked.connect(_on_hero_attacked)
	if g.has_signal("enemy_killed"):
		g.enemy_killed.connect(_on_enemy_killed)

	_demo = bool(g.is_capture) if "is_capture" in g else false


func _hero() -> Vector3:
	if game and "hero_pos" in game:
		return game.hero_pos
	return Vector3.ZERO


func _face() -> float:
	if game and "hero_face" in game:
		return game.hero_face
	return 0.0

# ==========================================================================================
#  SIGNAL HOOKS
# ==========================================================================================
func _on_hero_attacked(target_pos: Vector3, damage: int, crit: bool) -> void:
	if crit:
		spawn_damage(target_pos, damage, DmgType.CRIT)
		heavy_impact(target_pos)
	else:
		spawn_damage(target_pos, damage, DmgType.PHYSICAL)
		hit_impact(target_pos, COL_CYAN)


func _on_enemy_killed(pos: Vector3) -> void:
	death_burst(pos)

# ==========================================================================================
#  MAIN LOOP
# ==========================================================================================
func _process(delta: float) -> void:
	# lavapipe gives huge, jittery deltas — clamp so nothing teleports through its animation
	var dt: float = clamp(delta, 0.0, 0.12)
	_t += dt
	_big_lock = maxf(0.0, _big_lock - dt)
	_update_texts(dt)
	_update_effects(dt)
	_update_aura(dt)
	_update_whirlwind(dt)
	_update_shake(dt)
	if _demo:
		_demo_director(dt)

# ------------------------------------------------------------------ auto-demo for captures
## The enemies module may not exist yet, so drive our own combat so every capture shows the
## damage text and the full ability rotation.
func _demo_director(dt: float) -> void:
	var hp := _hero()
	var f := _face()

	_next_hit -= dt
	if _next_hit <= 0.0:
		_next_hit = 0.85
		_hit_i += 1
		# phantom targets arranged in front of Carl, so numbers spread across the frame
		var ang: float = f + _rng.randf_range(-1.5, 1.5)
		var rad: float = _rng.randf_range(1.3, 2.6)
		var tp := hp + Vector3(sin(ang) * rad, 0.0, cos(ang) * rad)

		match _hit_i % 8:
			0:
				spawn_damage(tp, _rng.randi_range(180000, 340000), DmgType.CRIT)
				heavy_impact(tp)
			1, 3, 6:
				spawn_damage(tp, _rng.randi_range(52000, 94000), DmgType.PHYSICAL)
				hit_impact(tp, COL_CYAN)
			2, 7:
				spawn_damage(tp, _rng.randi_range(28000, 61000), DmgType.AETHER)
				hit_impact(tp, COL_VIOLET)
			5:
				spawn_damage(tp, _rng.randi_range(9000, 22000), DmgType.BLOCKED)
				hit_impact(tp, Color(0.7, 0.75, 0.85))
			4:
				spawn_damage(tp, _rng.randi_range(120000, 260000), DmgType.CRIT)
				heavy_impact(tp)
				death_burst(tp)

	# Abilities are seasoning: one every ~3s, and the arbiter drops any that would land while
	# another big effect is still on screen. Between beats the frame is just Carl and the cavern.
	_next_ability -= dt
	if _next_ability <= 0.0 and _big_lock <= 0.0:
		_next_ability = 3.1
		_ability_i += 1
		match _ability_i % 4:
			0: cleave(hp, f)
			1: aether_nova(hp)
			2: whirlwind(hp)
			3: war_cry(hp)

# ==========================================================================================
#  1. FLOATING DAMAGE NUMBERS
# ==========================================================================================
## Spawn a floating combat-text pop at `pos` (world). Style is driven by `type`.
func spawn_damage(pos: Vector3, amount: int, type: int) -> void:
	if _texts.size() >= MAX_TEXT:
		_retire_text(0)

	var holder: Node3D = _acquire("text", Callable(self, "_make_text"))
	var main: Label3D = holder.get_child(0)
	var sub: Label3D = holder.get_child(1)

	var col := COL_PHYS
	var label := ""
	# Screen-space size per font pixel (labels are fixed_size). A fixed_size Label3D at
	# font_size 128 covers roughly (128 * ps * 1450) pixels of a 1000px-tall 38-degree frame, so
	# a crit at 0.00062 was ~115px tall and a third of the frame wide — it covered the boss.
	# Retuned so a crit still lands the punch (~72px) while the enemy it belongs to stays visible.
	var ps := 0.00026
	var sub_text := ""
	var sub_col := COL_PHYS
	var outline := 12

	match type:
		DmgType.CRIT:
			col = COL_CRIT
			ps = 0.00039
			outline = 14
			sub_text = "CRITICAL!"
			sub_col = Color(1.45, 0.85, 0.22)
		DmgType.AETHER:
			col = COL_AETHER
			ps = 0.00027
			sub_text = "AETHER"
			sub_col = Color(0.80, 0.38, 1.55)
		DmgType.BLOCKED:
			col = COL_BLOCK
			ps = 0.00021
			outline = 10
			sub_text = "BLOCKED"
			sub_col = Color(0.48, 0.53, 0.60)
		_:
			col = COL_PHYS
			ps = 0.00026
			sub_text = "PHYSICAL"
			sub_col = Color(0.86, 0.83, 0.76)

	label = _commas(amount)
	main.text = label
	main.pixel_size = ps
	main.modulate = col
	main.outline_modulate = Color(0, 0, 0, 1)
	main.outline_size = outline

	sub.text = sub_text
	sub.pixel_size = ps * (0.40 if type == DmgType.CRIT else 0.44)
	sub.modulate = sub_col
	sub.outline_modulate = Color(0, 0, 0, 1)
	sub.visible = true

	# De-clutter: successive pops are pushed along the CAMERA-RIGHT axis in rotating slots,
	# so consecutive numbers separate on screen instead of stacking on each other.
	# A fixed_size Label3D behaves as if it sat one unit from the camera, so its apparent
	# WORLD size is (pixel_size * font_size * distance). Every layout offset below is
	# therefore scaled by that same distance — screen spacing then stays constant no matter
	# how tight or wide the camera happens to be framed.
	var dist := 12.0
	if cam:
		dist = maxf(2.0, cam.global_position.distance_to(pos))
	var unit: float = 128.0 * ps * dist          # one line-height of the main label, in world units

	_text_seq += 1
	var slot: int = _text_seq % 4
	var right := Vector3.RIGHT
	if cam:
		right = cam.global_transform.basis.x
	holder.visible = true
	holder.position = pos + right * ((float(slot) - 1.5) * unit * 1.75 + _rng.randf_range(-0.2, 0.2)) \
		+ Vector3(0, 2.1 + unit * 1.15 * float(slot % 2) + _rng.randf_range(-0.15, 0.3), 0)
	holder.scale = Vector3(0.25, 0.25, 0.25)

	var vx := _rng.randf_range(-0.7, 0.7)
	var vz := _rng.randf_range(-0.5, 0.5)
	_texts.append({
		"n": holder, "m": main, "s": sub, "t": 0.0,
		"d": TEXT_LIFE * (1.18 if type == DmgType.CRIT else 1.0),
		"p0": holder.position,
		"v": Vector3(vx, 2.30 if type == DmgType.CRIT else 2.00, vz),
		"col": col, "scol": sub_col,
		"gap": 128.0 * ps * 0.95,   # sub-label drop, per unit of camera distance
	})


func _make_text() -> Node3D:
	var holder := Node3D.new()
	var main := _make_label(128, 20)
	holder.add_child(main)
	var sub := _make_label(128, 16)
	holder.add_child(sub)
	root.add_child(holder)
	return holder


func _make_label(fsize: int, outline: int) -> Label3D:
	var l := Label3D.new()
	l.font = _font
	l.font_size = fsize
	l.outline_size = outline
	l.outline_modulate = Color(0, 0, 0, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.double_sided = true
	l.shaded = false
	l.fixed_size = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.render_priority = 12
	l.outline_render_priority = 11
	return l


func _update_texts(dt: float) -> void:
	var i := _texts.size() - 1
	while i >= 0:
		var e: Dictionary = _texts[i]
		e["t"] = float(e["t"]) + dt
		var t: float = e["t"]
		var d: float = e["d"]
		if t >= d:
			_retire_text(i)
			i -= 1
			continue
		var k: float = t / d
		var n: Node3D = e["n"]

		# ballistic arc: quick pop upward, gravity pulls the tail of the arc back down
		var v: Vector3 = e["v"]
		n.position = (e["p0"] as Vector3) + v * t + Vector3(0, -0.62, 0) * t * t

		# Scale punch: overshoot then settle. It used to start at 0.25, which looks great at
		# 60fps but under software Vulkan the frame that gets captured often lands inside that
		# first 0.1 of the life — so a crit would render at a quarter size next to a full-size
		# normal hit and just read as a bug. Starting at 0.62 keeps the pop while making every
		# sampled frame a legible number.
		var s := 1.0
		if k < 0.10:
			s = lerp(0.82, 1.16, k / 0.10)
		elif k < 0.26:
			s = lerp(1.16, 1.0, (k - 0.10) / 0.16)
		elif k > 0.80:
			s = lerp(1.0, 0.86, (k - 0.80) / 0.20)
		n.scale = Vector3(s, s, s)

		# hold full opacity most of the life, then fade
		var a := 1.0
		if k > 0.62:
			a = 1.0 - (k - 0.62) / 0.38
		a = clamp(a, 0.0, 1.0)
		var m: Label3D = e["m"]
		var sb: Label3D = e["s"]
		if cam:
			sb.position.y = -float(e["gap"]) * maxf(2.0, cam.global_position.distance_to(n.global_position))
		var c: Color = e["col"]
		var sc: Color = e["scol"]
		m.modulate = Color(c.r, c.g, c.b, a)
		m.outline_modulate = Color(0, 0, 0, a)
		sb.modulate = Color(sc.r, sc.g, sc.b, a * 0.92)
		sb.outline_modulate = Color(0, 0, 0, a)
		i -= 1


func _retire_text(i: int) -> void:
	var e: Dictionary = _texts[i]
	var n: Node3D = e["n"]
	n.visible = false
	_release("text", n)
	_texts.remove_at(i)


func _commas(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

# ==========================================================================================
#  2. IMPACT VFX
# ==========================================================================================
## Normal hit: sparks + a quick billboard flash.
func hit_impact(pos: Vector3, tint: Color) -> void:
	_sparks(pos + Vector3(0, 1.1, 0), tint, 1.0)
	_flash(pos + Vector3(0, 1.1, 0), tint, 0.9, 0.26)


## Crit / heavy hit: bigger sparks, a hot flash, an expanding ground shock ring, camera shake.
func heavy_impact(pos: Vector3) -> void:
	_sparks(pos + Vector3(0, 1.2, 0), Color(1.85, 0.95, 0.26), 1.45)
	_flash(pos + Vector3(0, 1.2, 0), Color(1.10, 0.58, 0.17), 0.95, 0.26)
	shock_ring(pos, Color(1.20, 0.54, 0.13), 0.7, 4.0, 0.50)
	shake(0.30, 0.40)


## Crystal-shard death burst — solid emissive shards flung outward, plus a violet flash.
func death_burst(pos: Vector3) -> void:
	var p: GPUParticles3D = _acquire("shards", Callable(self, "_make_shards"))
	p.position = pos + Vector3(0, 0.9, 0)
	p.visible = true
	p.emitting = true
	p.restart()
	_live.append({"n": p, "t": 0.0, "d": 1.5, "k": "shards", "kind": "particles"})
	_flash(pos + Vector3(0, 1.0, 0), COL_VIOLET, 0.95, 0.30)
	shock_ring(pos, COL_VIOLET, 0.5, 3.2, 0.55)
	shake(0.20, 0.32)


func _sparks(pos: Vector3, tint: Color, scale: float) -> void:
	var p: GPUParticles3D = _acquire("sparks", Callable(self, "_make_sparks"))
	p.position = pos
	p.visible = true
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = Color(tint.r, tint.g, tint.b, 1.0)
	pm.initial_velocity_min = 4.0 * scale
	pm.initial_velocity_max = 11.0 * scale
	p.emitting = true
	p.restart()
	_live.append({"n": p, "t": 0.0, "d": 1.1, "k": "sparks", "kind": "particles"})


func _flash(pos: Vector3, tint: Color, size: float, dur: float) -> void:
	var n: Node3D = _acquire("flash", Callable(self, "_make_flash"))
	n.position = pos
	n.visible = true
	var mi: MeshInstance3D = n.get_child(0)
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	var lt: OmniLight3D = n.get_child(1)
	lt.light_color = Color(clamp(tint.r, 0, 1), clamp(tint.g, 0, 1), clamp(tint.b, 0, 1))
	_live.append({"n": n, "t": 0.0, "d": dur, "k": "flash", "kind": "flash", "size": size})


## An expanding, fading radial ring lying on the ground.
func shock_ring(pos: Vector3, tint: Color, r0: float, r1: float, dur: float) -> void:
	var mi: MeshInstance3D = _acquire("ring", Callable(self, "_make_ring"))
	mi.position = pos + Vector3(0, 0.09, 0)
	mi.rotation = Vector3.ZERO
	mi.visible = true
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	_live.append({"n": mi, "t": 0.0, "d": dur, "k": "ring", "kind": "ring",
		"r0": r0, "r1": r1, "tint": tint})

# ==========================================================================================
#  3. ABILITY VFX
# ==========================================================================================
## Reserve the "one big effect on screen" slot. Returns false if another ability is still
## playing, in which case the caller silently drops its effect — a skipped flourish is always
## cheaper than an unreadable frame.
func _claim_big(lock: float) -> bool:
	if _big_lock > 0.0:
		return false
	_big_lock = lock
	return true


## CLEAVE — a wide cyan energy crescent sweeping through the arc in front of Carl.
func cleave(pos: Vector3, facing: float) -> void:
	if not _claim_big(0.6):
		return
	var mi: MeshInstance3D = _acquire("crescent", Callable(self, "_make_crescent"))
	mi.position = pos + Vector3(0, 1.05, 0)
	mi.visible = true
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(CLEAVE_COL.r, CLEAVE_COL.g, CLEAVE_COL.b, 1.0)
	_live.append({"n": mi, "t": 0.0, "d": 0.55, "k": "crescent", "kind": "cleave", "face": facing})
	# a couple of sparks riding the leading edge
	_sparks(pos + Vector3(sin(facing) * 2.6, 1.3, cos(facing) * 2.6), COL_CYAN, 0.8)
	shake(0.12, 0.22)


## AETHER NOVA — a violet shockwave ring plus an upward burst of aether motes.
func aether_nova(pos: Vector3) -> void:
	if not _claim_big(1.3):
		return
	var mi: MeshInstance3D = _acquire("ringwide", Callable(self, "_make_ring_wide"))
	mi.position = pos + Vector3(0, 0.12, 0)
	mi.visible = true
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(COL_VIOLET.r, COL_VIOLET.g, COL_VIOLET.b, 1.0)
	_live.append({"n": mi, "t": 0.0, "d": 0.85, "k": "ringwide", "kind": "ring",
		"r0": 0.4, "r1": 5.4, "tint": COL_VIOLET})
	shock_ring(pos, Color(0.55, 0.20, 1.35), 0.3, 3.6, 0.7)
	_flash(pos + Vector3(0, 1.2, 0), COL_VIOLET, 0.85, 0.26)

	var p: GPUParticles3D = _acquire("nova", Callable(self, "_make_nova"))
	p.position = pos + Vector3(0, 0.4, 0)
	p.visible = true
	p.emitting = true
	p.restart()
	_live.append({"n": p, "t": 0.0, "d": 1.6, "k": "nova", "kind": "particles"})
	shake(0.22, 0.35)


## WHIRLWIND — Carl wreathed in spinning blue energy blades.
func whirlwind(_pos: Vector3 = Vector3.ZERO, dur: float = 1.35) -> void:
	if not _claim_big(dur + 0.15):
		return
	_whirl_t = 0.0
	_whirl_d = dur
	_whirl.visible = true
	# Dimmer and tighter than the impact rings: at full COL_CYAN this was a hard-edged torus
	# that read as a UI element sitting on top of the scene rather than energy inside it.
	shock_ring(_hero(), Color(0.18, 0.55, 0.90), 0.8, 2.5, 0.55)
	shake(0.10, 0.45)


## WAR CRY — a radiant ground rune and a short upward light shaft under Carl.
## The shaft used to be an 11m, 55%-alpha column that swallowed the hero it was buffing; it is
## now a brief waist-to-shoulder flare that reads as an upward surge without hiding Carl.
func war_cry(pos: Vector3) -> void:
	if not _claim_big(1.25):
		return
	var rune: MeshInstance3D = _acquire("rune", Callable(self, "_make_rune"))
	rune.position = pos + Vector3(0, 0.07, 0)
	rune.visible = true
	_live.append({"n": rune, "t": 0.0, "d": 1.0, "k": "rune", "kind": "rune"})

	var pillar: Node3D = _acquire("pillar", Callable(self, "_make_pillar"))
	pillar.position = pos
	pillar.visible = true
	_live.append({"n": pillar, "t": 0.0, "d": 0.70, "k": "pillar", "kind": "pillar"})

	shock_ring(pos, COL_GOLD, 0.6, 4.6, 0.75)
	_sparks(pos + Vector3(0, 1.0, 0), COL_GOLD, 0.9)
	shake(0.24, 0.40)

# ==========================================================================================
#  EFFECT UPDATE
# ==========================================================================================
func _update_effects(dt: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var e: Dictionary = _live[i]
		e["t"] = float(e["t"]) + dt
		var t: float = e["t"]
		var d: float = e["d"]
		var k: float = clamp(t / d, 0.0, 1.0)
		var n: Node3D = e["n"]

		match String(e["kind"]):
			"ring":
				var r: float = lerp(float(e["r0"]), float(e["r1"]), 1.0 - pow(1.0 - k, 2.2))
				n.scale = Vector3(r, 1.0, r)
				var a: float = pow(1.0 - k, 1.5)
				var tint: Color = e["tint"]
				var mm: StandardMaterial3D = (n as MeshInstance3D).material_override
				mm.albedo_color = Color(tint.r, tint.g, tint.b, a)
			"flash":
				var s: float = float(e["size"]) * (0.35 + 1.5 * k)
				var mi2: MeshInstance3D = n.get_child(0)
				mi2.scale = Vector3(s, s, s)
				var fa: float = pow(1.0 - k, 2.0)
				var fm: StandardMaterial3D = mi2.material_override
				fm.albedo_color.a = fa * 0.30
				var lt: OmniLight3D = n.get_child(1)
				lt.light_energy = 1.4 * fa
			"cleave":
				# the crescent sweeps through the swing arc while it stretches and fades
				var face: float = e["face"]
				n.rotation = Vector3(-0.28, face - 1.00 + 2.0 * k, 0.0)
				var cs: float = 0.62 + 0.40 * pow(k, 0.7)
				n.scale = Vector3(cs, 1.0, cs)
				var ca: float = sin(clamp(k, 0.0, 1.0) * PI)
				ca = pow(ca, 0.60) * 0.52
				var cm: StandardMaterial3D = (n as MeshInstance3D).material_override
				cm.albedo_color = Color(CLEAVE_COL.r, CLEAVE_COL.g, CLEAVE_COL.b, ca)
			"rune":
				var rs: float = 2.15 * (0.45 + 0.55 * pow(k, 0.35))
				n.scale = Vector3(rs, 1.0, rs)
				n.rotation.y = k * 1.4
				var ra: float = sin(clamp(k, 0.0, 1.0) * PI) * 0.42
				var rm: StandardMaterial3D = (n as MeshInstance3D).material_override
				rm.albedo_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, ra)
			"pillar":
				var ph: float = 0.35 + 0.9 * pow(k, 0.4)
				var pw: float = (1.0 - 0.45 * k) * (0.6 + 0.6 * pow(k, 0.3))
				n.scale = Vector3(pw, ph, pw)
				n.rotation.y = t * 3.0
				# a sharp in-and-out spike, not a plateau: the shaft must not sit at full
				# brightness for most of its life the way pow(.., 0.7) made it
				var pa: float = sin(clamp(k, 0.0, 1.0) * PI)
				pa = pow(pa, 1.5)
				for c in n.get_children():
					var pmi := c as MeshInstance3D
					if pmi:
						var pmat: StandardMaterial3D = pmi.material_override
						pmat.albedo_color.a = pa * float(pmi.get_meta("base_a", 1.0))
			"particles":
				pass

		if t >= d:
			n.visible = false
			if e["kind"] == "particles":
				(n as GPUParticles3D).emitting = false
			_release(String(e["k"]), n)
			_live.remove_at(i)
		i -= 1

# ==========================================================================================
#  PERSISTENT AETHER AURA
# ==========================================================================================
func _build_aura() -> void:
	_aura = Node3D.new()
	_aura.name = "AetherAura"
	root.add_child(_aura)

	# A soft glow pool on the floor so Carl is always standing in his own light. This is the
	# ONLY part of the aura allowed to be obvious, because it sits under him instead of over him.
	var pool := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(3.4, 3.4)
	pq.orientation = PlaneMesh.FACE_Y
	pool.mesh = pq
	var pmat := _add_mat(Color(0.30, 0.12, 0.95, 0.10))
	pmat.albedo_texture = _tex_glow
	pool.material_override = pmat
	pool.position = Vector3(0, 0.04, 0)
	_aura.add_child(pool)

	# A HINT of energy, not a set of dominating rings. The waist-high and shoulder-high bands
	# used to run at 50-62% alpha and cut straight across Carl's torso and head in every frame;
	# the shoulder band is gone entirely and what remains is barely-there ambient motion.
	var specs := [
		{"y": 0.10, "r": 1.45, "tilt": Vector3(0, 0, 0), "spd": 0.55, "col": COL_VIOLET, "a": 0.17},
		{"y": 1.05, "r": 1.05, "tilt": Vector3(0.30, 0, 0.16), "spd": -0.85, "col": COL_CYAN, "a": 0.10},
	]
	for s in specs:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_aura
		var c: Color = s["col"]
		mi.material_override = _add_mat(Color(c.r, c.g, c.b, float(s["a"])))
		var rr: float = s["r"]
		mi.scale = Vector3(rr, 1.0, rr)
		mi.position = Vector3(0, s["y"], 0)
		mi.rotation = s["tilt"]
		_aura.add_child(mi)
		_aura_rings.append({"n": mi, "spd": float(s["spd"]), "tilt": s["tilt"], "a": float(s["a"])})

	_aura_motes = GPUParticles3D.new()
	_aura_motes.amount = 11
	_aura_motes.lifetime = 2.6
	_aura_motes.preprocess = 1.5
	_aura_motes.explosiveness = 0.0
	_aura_motes.draw_pass_1 = _mesh_quad
	_aura_motes.material_override = _particle_mat(Color(0.55, 0.34, 1.45, 1.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.06
	pm.scale_max = 0.15
	pm.color = Color(0.55, 0.32, 1.35, 1.0)
	pm.alpha_curve = _fade_curve()
	_aura_motes.process_material = pm
	_aura_motes.position = Vector3(0, 0.4, 0)
	_aura.add_child(_aura_motes)
	_aura_motes.emitting = true


func _update_aura(dt: float) -> void:
	if _aura == null:
		return
	_aura.position = _hero()
	for r in _aura_rings:
		var mi: MeshInstance3D = r["n"]
		mi.rotation.y += float(r["spd"]) * dt
	# gentle breathing pulse so the aura never looks static
	var pulse: float = 0.82 + 0.18 * sin(_t * 2.1)
	for r in _aura_rings:
		var mi2: MeshInstance3D = r["n"]
		var mat: StandardMaterial3D = mi2.material_override
		mat.albedo_color.a = float(r["a"]) * pulse

# ==========================================================================================
#  WHIRLWIND
# ==========================================================================================
func _build_whirlwind() -> void:
	_whirl = Node3D.new()
	_whirl.name = "Whirlwind"
	_whirl.visible = false
	root.add_child(_whirl)

	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		var blade := MeshInstance3D.new()
		blade.mesh = _mesh_blade
		var mat := _add_mat(Color(0.26, 0.82, 1.30, 0.30))
		mat.albedo_texture = _tex_streak
		blade.material_override = mat
		blade.set_meta("base_a", 0.30)
		blade.position = Vector3(sin(a) * 1.62, 0.45 + 0.32 * i, cos(a) * 1.62)
		blade.rotation = Vector3(0.10, a + PI * 0.5, 0.95)
		_whirl.add_child(blade)

	# two tilted energy bands binding the blades together
	for j in range(2):
		var band := MeshInstance3D.new()
		band.mesh = _mesh_ring
		band.material_override = _add_mat(Color(0.22, 0.70, 1.18, 0.24))
		var rr: float = 1.7 - 0.35 * j
		band.scale = Vector3(rr, 1.0, rr)
		band.set_meta("base_a", 0.24)
		band.position = Vector3(0, 0.55 + 1.1 * j, 0)
		band.rotation = Vector3(0.22 * (1 if j == 0 else -1), 0, 0.18)
		_whirl.add_child(band)


func _update_whirlwind(dt: float) -> void:
	if _whirl == null or not _whirl.visible:
		return
	_whirl_t += dt
	var k: float = clamp(_whirl_t / _whirl_d, 0.0, 1.0)
	_whirl.position = _hero()
	_whirl.rotation.y += dt * 13.0
	var a: float = sin(clamp(k, 0.0, 1.0) * PI)
	a = pow(a, 0.55)
	var s: float = 0.75 + 0.35 * pow(k, 0.4)
	_whirl.scale = Vector3(s, 1.0, s)
	for c in _whirl.get_children():
		var mi := c as MeshInstance3D
		if mi:
			var mat: StandardMaterial3D = mi.material_override
			mat.albedo_color.a = a * float(mi.get_meta("base_a", 0.7))
	if _whirl_t >= _whirl_d:
		_whirl.visible = false

# ==========================================================================================
#  4. CAMERA SHAKE  (offset-only, always decays back to exact zero)
# ==========================================================================================
func shake(amount: float, dur: float) -> void:
	_shake = max(_shake, amount)
	_shake_t = max(_shake_t, dur)


func _update_shake(dt: float) -> void:
	if cam == null:
		return
	if _shake_t <= 0.0:
		if _shake != 0.0 or cam.h_offset != 0.0 or cam.v_offset != 0.0:
			_shake = 0.0
			cam.h_offset = 0.0
			cam.v_offset = 0.0
		return
	_shake_t -= dt
	var decay: float = clamp(_shake_t / 0.5, 0.0, 1.0)
	var amp: float = _shake * decay
	cam.h_offset = sin(_t * 61.0) * amp * 0.5 + sin(_t * 37.0) * amp * 0.3
	cam.v_offset = cos(_t * 53.0) * amp * 0.45 + sin(_t * 29.0) * amp * 0.25
	if _shake_t <= 0.0:
		_shake = 0.0
		cam.h_offset = 0.0
		cam.v_offset = 0.0

# ==========================================================================================
#  POOLING
# ==========================================================================================
func _acquire(kind: String, factory: Callable) -> Node:
	var arr: Array = _pools.get(kind, [])
	if arr.size() > 0:
		var n: Node = arr.pop_back()
		_pools[kind] = arr
		return n
	return factory.call()


func _release(kind: String, n: Node) -> void:
	var arr: Array = _pools.get(kind, [])
	if arr.size() < 12:
		arr.append(n)
		_pools[kind] = arr
	else:
		n.queue_free()

# ==========================================================================================
#  FACTORIES
# ==========================================================================================
func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 22
	p.lifetime = 0.85
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.draw_pass_1 = _mesh_quad
	p.material_override = _particle_mat(Color(1.4, 1.9, 2.4, 1.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.direction = Vector3(0, 0.35, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -13.0, 0)
	pm.damping_min = 1.2
	pm.damping_max = 3.0
	pm.scale_min = 0.14
	pm.scale_max = 0.34
	pm.scale_curve = _shrink_curve()
	pm.alpha_curve = _fade_curve()
	pm.color = Color(1, 1, 1, 1)
	p.process_material = pm
	root.add_child(p)
	return p


func _make_nova() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.3
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.draw_pass_1 = _mesh_quad
	p.material_override = _particle_mat(Color(1.5, 0.6, 2.8, 1.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 0.9
	pm.emission_ring_inner_radius = 0.2
	pm.emission_ring_height = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -2.2, 0)
	pm.radial_accel_min = 4.0
	pm.radial_accel_max = 9.0
	pm.scale_min = 0.18
	pm.scale_max = 0.46
	pm.scale_curve = _shrink_curve()
	pm.alpha_curve = _fade_curve()
	pm.color = Color(1, 1, 1, 1)
	p.process_material = pm
	root.add_child(p)
	return p


func _make_shards() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var shard := PrismMesh.new()
	shard.size = Vector3(0.09, 0.26, 0.09)
	p.draw_pass_1 = shard
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.85, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(0.45, 0.8, 1.0)
	m.emission_energy_multiplier = 3.0
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.material_override = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3(0, 0.5, 0)
	pm.spread = 170.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 8.5
	pm.gravity = Vector3(0, -11.0, 0)
	pm.angular_velocity_min = -420.0
	pm.angular_velocity_max = 420.0
	pm.scale_min = 0.55
	pm.scale_max = 1.15
	pm.alpha_curve = _fade_curve()
	pm.color = Color(1.4, 2.0, 2.6, 1.0)
	p.process_material = pm
	root.add_child(p)
	return p


func _make_flash() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_quad
	var m := _add_mat(Color(1, 1, 1, 1))
	m.albedo_texture = _tex_glow
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.render_priority = 6
	mi.material_override = m
	n.add_child(mi)
	var lt := OmniLight3D.new()
	lt.omni_range = 9.0
	lt.light_energy = 0.0
	lt.shadow_enabled = false
	n.add_child(lt)
	root.add_child(n)
	return n


func _make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_ring
	mi.material_override = _add_mat(Color(1, 1, 1, 1))
	root.add_child(mi)
	return mi


func _make_ring_wide() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_ring_wide
	mi.material_override = _add_mat(Color(1, 1, 1, 1))
	root.add_child(mi)
	return mi


func _make_crescent() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_crescent
	mi.material_override = _add_mat(Color(1, 1, 1, 1))
	root.add_child(mi)
	return mi


func _make_rune() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := _add_mat(Color(1, 1, 1, 1))
	m.albedo_texture = _tex_rune
	mi.material_override = m
	root.add_child(mi)
	return mi


## The war-cry light pillar. Three crossed vertical planes with a soft gradient beat a
## cylinder here: a tube has a hard silhouette that reads as a solid white column, while
## crossed soft-edged planes read as an actual shaft of light from every camera angle.
func _make_pillar() -> Node3D:
	var n := Node3D.new()
	var specs := [
		{"w": 1.15, "h": 5.2, "a": 0.20, "c": Color(1.15, 0.74, 0.28)},
		{"w": 2.40, "h": 3.9, "a": 0.075, "c": Color(0.85, 0.48, 0.18)},
	]
	for s in specs:
		for i in range(3):
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(float(s["w"]), float(s["h"]))
			mi.mesh = q
			var c: Color = s["c"]
			var m := _add_mat(Color(c.r, c.g, c.b, float(s["a"])))
			m.albedo_texture = _tex_pillar
			mi.material_override = m
			mi.position = Vector3(0, float(s["h"]) * 0.5, 0)
			mi.rotation = Vector3(0, PI * float(i) / 3.0, 0)
			mi.set_meta("base_a", float(s["a"]))
			n.add_child(mi)
	root.add_child(n)
	return n

# ==========================================================================================
#  SHARED RESOURCES  (fonts, generated textures, generated meshes)
# ==========================================================================================
func _build_resources() -> void:
	_font = _load_font()
	_tex_glow = _make_glow_tex(64)
	_tex_streak = _make_streak_tex(64)
	_tex_rune = _make_rune_tex(160)
	_tex_pillar = _make_pillar_tex(64)
	# radial alpha profiles: a thin hot band for shock rings, a fat one for the nova, and a
	# crescent whose energy is concentrated along its LEADING (outer) edge.
	_mesh_ring = _make_arc_mesh(0.80, 1.0, 360.0, 56, [0.0, 0.55, 1.0, 0.55, 0.0])
	_mesh_ring_wide = _make_arc_mesh(0.52, 1.0, 360.0, 56, [0.0, 0.45, 0.85, 1.0, 0.30, 0.0])
	_mesh_crescent = _make_arc_mesh(2.55, 3.95, 124.0, 34, [0.0, 0.30, 1.0, 0.45, 0.0])
	_mesh_aura = _make_arc_mesh(0.74, 1.0, 360.0, 48, [0.0, 0.6, 1.0, 0.6, 0.0])
	_mesh_quad = QuadMesh.new()
	_mesh_quad.size = Vector2(1.0, 1.0)
	_mesh_blade = QuadMesh.new()
	_mesh_blade.size = Vector2(0.58, 2.05)


func _load_font() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["DejaVu Sans", "Liberation Sans", "Arial", "Sans-Serif"])
	sf.font_weight = 700
	sf.multichannel_signed_distance_field = true
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return sf


## Unshaded additive material — the workhorse for every VFX surface.
func _add_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.albedo_color = col
	m.render_priority = 4
	return m


func _particle_mat(col: Color) -> StandardMaterial3D:
	var m := _add_mat(col)
	m.albedo_texture = _tex_glow
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.render_priority = 5
	return m


func _fade_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.55, 0.9))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


func _shrink_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.35, 0.75))
	c.add_point(Vector2(1.0, 0.05))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

# ---------------------------------------------------------------- generated textures
func _make_glow_tex(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var d: float = Vector2(x - c, y - c).length() / (n * 0.5)
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.4)
			var core: float = clamp(1.0 - d * 2.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clamp(a + core * 0.35, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_streak_tex(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		var v: float = float(y) / float(n - 1)
		# taper along the blade length: hot at the base, sharp point at the tip
		var lengthwise: float = pow(clamp(1.0 - v, 0.0, 1.0), 0.7)
		for x in range(n):
			var u: float = float(x) / float(n - 1)
			var across: float = clamp(1.0 - abs(u - 0.5) * 2.0, 0.0, 1.0)
			across = pow(across, 1.6)
			# the blade narrows toward the tip
			var width: float = clamp(1.0 - abs(u - 0.5) * 2.0 / max(0.12, 1.0 - v * 0.85), 0.0, 1.0)
			var a: float = clamp(across * lengthwise * 0.35 + pow(width, 1.4) * lengthwise, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_pillar_tex(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		var v: float = float(y) / float(n - 1)   # 0 = top of the beam, 1 = the ground
		# bright through the mid-shaft, feathered at BOTH ends so it never clips to a
		# white disc where it meets the ground
		var a: float = pow(clamp(v, 0.0, 1.0), 1.4)
		a = a * (0.34 + 0.66 * clamp((1.0 - v) * 3.4, 0.0, 1.0))
		a = a * (0.86 + 0.14 * sin(v * 30.0))                # faint energy banding
		for x in range(n):
			var u: float = float(x) / float(n - 1)
			var across: float = clamp(1.0 - abs(u - 0.5) * 2.0, 0.0, 1.0)
			across = pow(across, 1.8)
			img.set_pixel(x, y, Color(1, 1, 1, clamp(a * across, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## The war-cry ground rune: outer band, inner band, radial spokes, glyph ticks.
func _make_rune_tex(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = (x - c) / (n * 0.5)
			var dy: float = (y - c) / (n * 0.5)
			var r: float = sqrt(dx * dx + dy * dy)
			var ang: float = atan2(dy, dx)
			var a := 0.0
			a = max(a, _band(r, 0.90, 0.030))
			a = max(a, _band(r, 0.80, 0.014) * 0.7)
			a = max(a, _band(r, 0.56, 0.022))
			a = max(a, _band(r, 0.30, 0.016) * 0.8)
			# 12 radial spokes between the two main bands
			if r > 0.57 and r < 0.79:
				var sp: float = abs(sin(ang * 6.0))
				a = max(a, pow(sp, 26.0) * 0.95)
			# 6 glyph ticks in the inner disc
			if r > 0.32 and r < 0.54:
				var g: float = abs(sin(ang * 3.0 + 0.4))
				a = max(a, pow(g, 40.0) * 0.8)
			# soft inner wash so the rune reads as a lit disc
			a = max(a, clamp(1.0 - r / 0.95, 0.0, 1.0) * 0.06)
			if r > 1.0:
				a = 0.0
			img.set_pixel(x, y, Color(1, 1, 1, clamp(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _band(r: float, at: float, w: float) -> float:
	var d: float = abs(r - at) / w
	return clamp(1.0 - d, 0.0, 1.0)

# ---------------------------------------------------------------- generated meshes
## A flat annulus (or arc of one) in the XZ plane, radius 1.0 at the outer edge so callers can
## just scale the MeshInstance3D. Vertex alpha feathers the inner/outer edges and — for arcs —
## the angular ends, which is what makes the crescent read as energy rather than a solid plate.
func _make_arc_mesh(r_in: float, r_out: float, arc_deg: float, segs: int, alphas: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var full: bool = arc_deg >= 359.0
	var span: float = deg_to_rad(arc_deg)
	var a0: float = -span * 0.5
	var rows: int = alphas.size()

	var grid := []
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var ang: float = a0 + span * t
		var taper := 1.0
		if not full:
			taper = pow(sin(t * PI), 0.5)
		var row := []
		for j in range(rows):
			var rr: float = lerp(r_in, r_out, float(j) / float(rows - 1))
			row.append({
				"p": Vector3(sin(ang) * rr, 0.0, cos(ang) * rr),
				"a": float(alphas[j]) * taper,
				"uv": Vector2(t, float(j) / float(rows - 1)),
			})
		grid.append(row)

	for i in range(segs):
		for j in range(rows - 1):
			var v00: Dictionary = grid[i][j]
			var v10: Dictionary = grid[i + 1][j]
			var v01: Dictionary = grid[i][j + 1]
			var v11: Dictionary = grid[i + 1][j + 1]
			for v in [v00, v10, v11, v00, v11, v01]:
				st.set_normal(Vector3.UP)
				st.set_color(Color(1, 1, 1, float(v["a"])))
				st.set_uv(v["uv"])
				st.add_vertex(v["p"])
	return st.commit()
