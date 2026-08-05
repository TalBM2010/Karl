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

# The shared screen-space text arbiter (damage numbers register their keep-out rects here so loot
# labels and nameplates slide clear of them). Preloaded so any module can create the single shared
# instance; guarded everywhere so a missing arbiter just restores the old un-coordinated behaviour.
const TextArbiter := preload("res://scripts/modules/text_arbiter.gd")

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
const CLEAVE_COL := Color(0.34, 0.92, 1.42)   # the cleave ability arc

# The per-swing axe arc — a crisp cyan-edged trace of the chop. Kept just under CLEAVE_COL so a
# swing arc + a hit flash landing in the same frame still hold their hue instead of summing white.
const SWING_COL := Color(0.40, 0.94, 1.46)

# DUST is deliberately NOT additive: a muted, warm cavern grey drawn with ALPHA (MIX) blend, so it
# grounds Carl and punctuates a heavy hit WITHOUT ever spending a coin of the additive-white budget
# that the arbiter guards. It reads as kicked earth, not light.
const COL_DUST := Color(0.46, 0.40, 0.33)

const TEXT_LIFE := 1.15
const MAX_TEXT := 3
# The largest pixel_size any number uses (a crit). Vertical lane spacing is sized off THIS so a
# lane always clears whatever number lands in it, crit or not — see spawn_damage's layout block.
const PS_MAX := 0.00039

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

# --- run dust (persistent emitter under Carl's feet) --------------------------------------
var _run_dust: GPUParticles3D = null
var _prev_hero := Vector3.ZERO
var _speed := 0.0
var _mesh_swing: ArrayMesh = null      # tight arc that traces the axe on a committed swing

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
	_build_run_dust()
	_prev_hero = _hero()

	# React to the rest of the game if/when it starts talking to us.
	if g.has_signal("hero_attacked"):
		g.hero_attacked.connect(_on_hero_attacked)
	if g.has_signal("enemy_killed"):
		g.enemy_killed.connect(_on_enemy_killed)

	_demo = bool(g.is_capture) if "is_capture" in g else false

	_ensure_arbiter()


## The shared text arbiter is a single node stashed on game.modules; whichever text module runs
## first creates it. Combat loads first, so this is usually where it is born — but loot.gd and
## enemies.gd mirror this guarded lazy-create so none of the three depends on the others existing.
func _ensure_arbiter() -> Node:
	if game == null or not ("modules" in game):
		return null
	var a = game.modules.get("text_arbiter", null)
	if a != null and is_instance_valid(a):
		return a
	a = TextArbiter.new()
	a.name = "TextArbiter"
	game.add_child(a)
	if a.has_method("setup"):
		a.setup(game)
	game.modules["text_arbiter"] = a
	return a


func _arbiter() -> Node:
	if game and "modules" in game:
		var a = game.modules.get("text_arbiter", null)
		if a != null and is_instance_valid(a):
			return a
	return null


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
	# The committed swing traces Carl's axe toward whatever he just hit.
	var hp: Vector3 = _hero()
	var to: Vector3 = target_pos - hp
	var face: float = atan2(to.x, to.z) if to.length() > 0.05 else _face()
	swing_arc(hp, face)
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
	_update_run_dust(dt)
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

		# every blow follows through with an axe arc toward the target it lands on
		swing_arc(hp, atan2(tp.x - hp.x, tp.z - hp.z))

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

	# ANTI-OVERLAP LAYOUT. On the boss cam every blow lands on the boss at screen-centre, so two
	# numbers spawned within a life of each other pile onto the same point — the old horizontal
	# "slots" nudged them only ~one line-height apart, far less than a 7-digit crit is WIDE
	# (~250px), so a white PHYSICAL and an orange CRITICAL rendered stacked and unreadable.
	# Fix: give every number its own VERTICAL LANE. Lanes are pitched by a full crit line-height
	# so two numbers can never share a row whatever their glyph width; a gentle per-lane
	# horizontal fan keeps the column from reading as rigid. A fixed_size Label3D behaves as if it
	# sat one unit from the camera, so its apparent WORLD size is (pixel_size * font_size *
	# distance) — every offset below is scaled by that distance, so on-screen spacing is constant
	# no matter how tight or wide the boss cam happens to frame.
	var dist := 12.0
	if cam:
		dist = maxf(2.0, cam.global_position.distance_to(pos))
	var right := Vector3.RIGHT
	if cam:
		right = cam.global_transform.basis.x
	var lane_h: float = 128.0 * PS_MAX * dist     # one crit line-height, in world units

	# Claim the lowest vertical lane not currently held by a live number. MAX_TEXT lanes always
	# suffice because we retire the oldest before exceeding MAX_TEXT.
	var occupied: Dictionary = {}
	for e0 in _texts:
		occupied[int(e0.get("lane", 0))] = true
	var lane: int = 0
	while occupied.has(lane) and lane < MAX_TEXT:
		lane += 1

	_text_seq += 1
	# small horizontal fan: 0, +, -, ... centred on the target so numbers still read as "its" hit
	var fan_dir: float = 0.0 if lane == 0 else (1.0 if lane % 2 == 1 else -1.0)
	holder.visible = true
	holder.position = pos \
		+ right * (fan_dir * lane_h * 0.85 + _rng.randf_range(-0.10, 0.10) * lane_h) \
		+ Vector3(0, 2.1 + lane_h * 2.55 * float(lane) + _rng.randf_range(-0.05, 0.05), 0)
	holder.scale = Vector3(0.25, 0.25, 0.25)

	# Gentle rise. Numbers already start high (2.1) and the lanes are pitched 2.55 crit-lines
	# apart, so the drift must stay well under that pitch over a life or a fresh high-lane number
	# would sink into an older low-lane one — kept modest and gravity-tailed for a soft settle.
	var vx: float = _rng.randf_range(-0.35, 0.35)
	var vz: float = _rng.randf_range(-0.25, 0.25)
	_texts.append({
		"n": holder, "m": main, "s": sub, "t": 0.0,
		"d": TEXT_LIFE * (1.18 if type == DmgType.CRIT else 1.0),
		"p0": holder.position,
		"v": Vector3(vx, 1.55 if type == DmgType.CRIT else 1.35, vz),
		"col": col, "scol": sub_col,
		"lane": lane,
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

		# Stamp this number's keep-out rect (top priority) so loot labels and nameplates slide clear
		# of it. Only while it is bright enough to matter — a nearly-faded ghost must not shove other
		# text around. Height is padded to cover the "CRITICAL!/PHYSICAL" sub-label sitting under it.
		if a > 0.12:
			var arb: Node = _arbiter()
			if arb and arb.has_method("register"):
				var ext: Vector2 = arb.half_extent(m.pixel_size, m.font_size, m.text.length())
				# The sub-label ("CRITICAL!"/"PHYSICAL"…) hangs a good way BELOW the number, so the
				# keep-out rect must reach down past it — a rect sized to the number alone let other
				# text land on the sub. Extend the half-height to cover the sub's bottom edge.
				var half_h: float = ext.y
				var sb_ext: Vector2 = arb.half_extent(sb.pixel_size, sb.font_size, sb.text.length())
				var pxw: float = arb.px_per_world(n.global_position)
				var drop_px: float = absf(n.global_position.y - sb.global_position.y) * pxw
				half_h = maxf(half_h, drop_px + sb_ext.y)
				arb.register(n.get_instance_id(), n.global_position, ext.x, half_h, 3)
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
## Direction, in the XZ plane, from Carl toward an impact — the knockback push axis.
func _push_dir(pos: Vector3) -> Vector3:
	var d: Vector3 = pos - _hero()
	d.y = 0.0
	if d.length() < 0.05:
		return Vector3(sin(_face()), 0.0, cos(_face()))
	return d.normalized()


## Normal hit: sparks + a crisp white hit-flash on the struck point + a directional knockback
## streak + a small kick of dust at its feet.
func hit_impact(pos: Vector3, tint: Color) -> void:
	var dir: Vector3 = _push_dir(pos)
	_sparks(pos + Vector3(0, 1.1, 0), tint, 0.85)
	hit_flash(pos + Vector3(0, 1.05, 0), dir, false)
	_dust_burst(Vector3(pos.x, 0.06, pos.z) + dir * 0.35, 0.7)


## Crit / heavy hit: bigger sparks, a hot white flash, a stronger knockback streak, an expanding
## ground shock ring, a burst of dust kicked up at the point of impact, and camera shake.
func heavy_impact(pos: Vector3) -> void:
	var dir: Vector3 = _push_dir(pos)
	_sparks(pos + Vector3(0, 1.2, 0), Color(1.85, 0.95, 0.26), 1.35)
	hit_flash(pos + Vector3(0, 1.15, 0), dir, true)
	shock_ring(pos, Color(1.20, 0.54, 0.13), 0.7, 4.0, 0.50)
	_dust_burst(Vector3(pos.x, 0.06, pos.z), 1.5)
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
	_dust_burst(Vector3(pos.x, 0.06, pos.z), 1.2)
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


func _flash(pos: Vector3, tint: Color, size: float, dur: float, peak: float = 0.30) -> void:
	var n: Node3D = _acquire("flash", Callable(self, "_make_flash"))
	n.position = pos
	n.visible = true
	var mi: MeshInstance3D = n.get_child(0)
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	var lt: OmniLight3D = n.get_child(1)
	lt.light_color = Color(clamp(tint.r, 0, 1), clamp(tint.g, 0, 1), clamp(tint.b, 0, 1))
	_live.append({"n": n, "t": 0.0, "d": dur, "k": "flash", "kind": "flash", "size": size, "peak": peak})


## HIT FLASH — the brief white/additive pop on the enemy Carl just struck, plus a short
## directional streak reading as the knockback impulse. Both persist ~0.4s (with an exp-decay
## envelope) so they are still bright enough to LAND in a 1–8fps capture instead of vanishing
## between frames, yet localized enough to punctuate the frame rather than wash it.
func hit_flash(pos: Vector3, dir: Vector3, hot: bool) -> void:
	if hot:
		_flash(pos, Color(1.65, 1.30, 0.72), 1.05, 0.46, 0.46)
	else:
		_flash(pos, Color(1.30, 1.48, 1.66), 0.82, 0.40, 0.40)
	_streak(pos, dir, hot)


## A short additive smear shot along the knockback axis away from Carl.
func _streak(pos: Vector3, dir: Vector3, hot: bool) -> void:
	var mi: MeshInstance3D = _acquire("streak", Callable(self, "_make_streak_quad"))
	mi.visible = true
	var mat: StandardMaterial3D = mi.material_override
	var tint: Color = Color(1.55, 1.02, 0.44) if hot else Color(0.86, 1.24, 1.58)
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	var yaw: float = atan2(dir.x, dir.z)
	_live.append({"n": mi, "t": 0.0, "d": 0.34 if hot else 0.30, "k": "streak", "kind": "streak",
		"base": pos, "dir": dir, "yaw": yaw, "tint": tint, "hot": hot})


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


## SWING ARC — a crisp cyan-edged crescent that traces Carl's axe through a committed swing and
## then fades. Fires on every real hit (NOT an ability, so it does NOT claim the big-effect lock):
## it is small, tight to the axe and short-lived, the follow-through that makes a chop read as
## weighty. It sits at the hero, spatially clear of the hit flash out on the target, so the two
## additive transients never overlap into a white blob.
func swing_arc(pos: Vector3, facing: float) -> void:
	var mi: MeshInstance3D = _acquire("swing", Callable(self, "_make_swing"))
	mi.position = pos + Vector3(0, 1.05, 0)
	mi.visible = true
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(SWING_COL.r, SWING_COL.g, SWING_COL.b, 0.0)
	_live.append({"n": mi, "t": 0.0, "d": 0.50, "k": "swing", "kind": "swing", "face": facing})


## A one-shot burst of ground dust. `scale` drives how far and how much is kicked up — a light
## scuff on a normal hit, a real cloud at the point of a heavy blow.
func _dust_burst(pos: Vector3, scale: float) -> void:
	var p: GPUParticles3D = _acquire("dust", Callable(self, "_make_dust"))
	p.position = pos
	p.visible = true
	var pm: ParticleProcessMaterial = p.process_material
	pm.initial_velocity_min = 1.1 * scale
	pm.initial_velocity_max = 3.0 * scale
	pm.scale_min = 0.30 * scale
	pm.scale_max = 0.85 * scale
	p.emitting = true
	p.restart()
	_live.append({"n": p, "t": 0.0, "d": 0.9, "k": "dust", "kind": "particles"})

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
				fm.albedo_color.a = fa * float(e.get("peak", 0.30))
				var lt: OmniLight3D = n.get_child(1)
				lt.light_energy = 1.4 * fa
			"swing":
				# the crescent sweeps through the chop while it stretches and fades. Tighter and
				# faster than the cleave ability so it reads as a single axe stroke, not a spell.
				var sf: float = e["face"]
				n.rotation = Vector3(-0.34, sf - 0.72 + 1.55 * k, 0.0)
				var sc: float = 0.80 + 0.32 * pow(k, 0.6)
				n.scale = Vector3(sc, 1.0, sc)
				var sa: float = sin(clamp(k, 0.0, 1.0) * PI)
				sa = pow(sa, 0.50) * 0.66
				var sm: StandardMaterial3D = (n as MeshInstance3D).material_override
				sm.albedo_color = Color(SWING_COL.r, SWING_COL.g, SWING_COL.b, sa)
			"streak":
				# a short skid smear shot away from Carl: stretches out along the push axis and
				# fades fast, a directional cue that still lands legibly in a slow capture.
				var dir: Vector3 = e["dir"]
				var ln: float = lerp(0.7, 1.9, pow(k, 0.5))
				n.rotation = Vector3(0.0, float(e["yaw"]), 0.0)
				n.scale = Vector3(0.5, 1.0, ln)
				n.position = (e["base"] as Vector3) + dir * ln * 0.55
				var sta: float = pow(1.0 - k, 1.7) * (0.5 if bool(e["hot"]) else 0.42)
				var tint: Color = e["tint"]
				var stm: StandardMaterial3D = (n as MeshInstance3D).material_override
				stm.albedo_color = Color(tint.r, tint.g, tint.b, sta)
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
#  RUN DUST  (a low ground puff that follows Carl's feet while he moves)
# ==========================================================================================
## A persistent, low-velocity dust emitter kicked up only while Carl is actually running. Alpha
## (MIX) blended in a warm cavern grey — off the additive budget entirely — so it grounds the run
## without ever nudging the frame toward white.
func _build_run_dust() -> void:
	_run_dust = GPUParticles3D.new()
	_run_dust.amount = 16
	_run_dust.lifetime = 0.85
	_run_dust.one_shot = false
	_run_dust.explosiveness = 0.0
	_run_dust.local_coords = false
	_run_dust.draw_pass_1 = _mesh_quad
	_run_dust.material_override = _dust_particle_mat(Color(COL_DUST.r, COL_DUST.g, COL_DUST.b, 0.55))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.34
	pm.direction = Vector3(0, 0.35, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, 0.25, 0)          # dust drifts up and settles, never falls hard
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	pm.scale_min = 0.35
	pm.scale_max = 0.8
	pm.scale_curve = _grow_curve()            # each puff expands as it thins out
	pm.alpha_curve = _dust_alpha_curve()
	pm.color = Color(1, 1, 1, 1)
	_run_dust.process_material = pm
	_run_dust.position = _prev_hero + Vector3(0, 0.05, 0)
	_run_dust.emitting = false
	root.add_child(_run_dust)


func _update_run_dust(dt: float) -> void:
	if _run_dust == null:
		return
	var hp: Vector3 = _hero()
	var inst: float = 0.0
	if dt > 0.0001:
		inst = (hp - _prev_hero).length() / dt
	_prev_hero = hp
	# smooth so a single jittery lavapipe delta can't flicker the emitter on and off
	_speed = lerpf(_speed, inst, 0.35)
	_run_dust.position = Vector3(hp.x, 0.05, hp.z)
	var moving: bool = _speed > 0.7 and _speed < 40.0   # upper guard rejects teleport spikes
	if _run_dust.emitting != moving:
		_run_dust.emitting = moving

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


func _make_swing() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_swing
	mi.material_override = _add_mat(Color(1, 1, 1, 1))
	root.add_child(mi)
	return mi


func _make_streak_quad() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 2.0)
	q.orientation = PlaneMesh.FACE_Y     # lies on the ground plane; long axis is local Z
	mi.mesh = q
	var m := _add_mat(Color(1, 1, 1, 1))
	m.albedo_texture = _tex_streak
	mi.material_override = m
	root.add_child(mi)
	return mi


## One-shot ground dust for impacts. Alpha (MIX) blended so it reads as kicked earth and never
## contributes to additive white — the same reason the run-dust emitter uses this material.
func _make_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.85
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.draw_pass_1 = _mesh_quad
	p.material_override = _dust_particle_mat(Color(COL_DUST.r, COL_DUST.g, COL_DUST.b, 0.6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.direction = Vector3(0, 0.4, 0)
	pm.spread = 95.0
	pm.initial_velocity_min = 1.1
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -1.1, 0)
	pm.damping_min = 0.8
	pm.damping_max = 2.0
	pm.scale_min = 0.30
	pm.scale_max = 0.85
	pm.scale_curve = _grow_curve()
	pm.alpha_curve = _dust_alpha_curve()
	pm.color = Color(1, 1, 1, 1)
	p.process_material = pm
	root.add_child(p)
	return p


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
	# the swing arc: tighter to the axe (reach ~1.3-2.4), thinner, energy hard on the leading edge
	_mesh_swing = _make_arc_mesh(1.30, 2.40, 152.0, 30, [0.0, 0.22, 0.7, 1.0, 0.35, 0.0])
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


## Dust material: unshaded, soft glow sprite, but ALPHA (MIX) blended rather than additive, so it
## occludes like real dust and stays completely off the additive-white budget the arbiter guards.
func _dust_particle_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.albedo_texture = _tex_glow
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.render_priority = 2   # under the additive VFX so dust never veils a flash or number
	return m


func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.55))
	c.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


## Dust fades IN fast off the ground then feathers away — never a hard pop, never a lingering haze.
func _dust_alpha_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.18, 1.0))
	c.add_point(Vector2(0.55, 0.7))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


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
