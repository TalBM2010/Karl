extends Node
## CREATURES — Princess Donut, the crystalline arachnids, and the Juicer boss.
##
## Everything here is built from code so the silhouettes can be tuned in the critic loop:
##   * Princess Donut — the rigged Fox.glb reshaped into a small regal Persian cat with a
##     glowing golden crown; pads along beside Carl.
##   * Crystalline arachnids — faceted crystal shards (a flat-shaded ArrayMesh builder, so they
##     catch light per-facet the way a real gem does), violet core, six eyes, eight legs that
##     actually cycle. They crawl the hero down.
##   * The Juicer — a steroid-swollen hulk ~3.7x Carl's height with a MUTANT WHEY jug and
##     syringes in his back. Lumbers in, telegraphs a slam with a red ground ring.
##
## Module contract: extends Node ; setup(game). `game` is the Main node from game.gd.

const HERO_SCALE := 2.4          # Carl's height, to keep every creature in proportion
const BOSS_HEIGHT := 8.9         # ~3.7x Carl — he must DWARF him
const SPIDER_COUNT := 5

var game: Node = null
var donut: Node3D
var boss: Node3D
var spiders: Array = []

var _t := 0.0
var _rng := RandomNumberGenerator.new()

# arachnid liveliness timers (self-driven — the demo director hits phantom targets, so nothing
# actually strikes a real spider; these make hit-reactions and a death dissolve show up anyway).
var _spider_flinch_cd := 1.6
var _spider_death_cd := 7.0

# boss state machine
var _boss_pos := Vector3(0, 0, -14.0)
var _boss_face := 0.0
var _boss_cd := 3.2
var _boss_phase := "walk"        # walk | telegraph | slam | recover
var _boss_ph_t := 0.0
var _boss_ring: MeshInstance3D
var _boss_arm_l: Node3D
var _boss_arm_r: Node3D
var _boss_body: Node3D
var _boss_light: OmniLight3D

# materials
var m_crystal: StandardMaterial3D
var m_crystal_dark: StandardMaterial3D
var m_core: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_flesh: StandardMaterial3D
var m_flesh_dark: StandardMaterial3D
var m_vein: StandardMaterial3D
var m_gold: StandardMaterial3D
var m_fur: StandardMaterial3D
var m_fur_dark: StandardMaterial3D
var m_jug: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_ring: StandardMaterial3D
var m_shadow: StandardMaterial3D          # soft fake contact-shadow (grounding)
var _shadow_tex: ImageTexture

func setup(g) -> void:
	game = g
	_rng.seed = 91177
	_materials()
	_build_donut()
	_build_spiders()
	_build_boss()
	# Contract: react to combat without owning it. hero_attacked -> flinch/knockback the
	# nearest arachnid; enemy_killed -> dissolve it. The demo director fires at phantom targets
	# so these seldom land on a real spider — the arachnid AI therefore also SELF-drives its own
	# telegraphed lunges, flinches and an occasional death-dissolve so captures always show life.
	if game.has_signal("hero_attacked"):
		game.hero_attacked.connect(_on_hero_attacked)
	if game.has_signal("enemy_killed"):
		game.enemy_killed.connect(_on_enemy_killed)
	set_process(true)

# ================================================================= materials
func _materials() -> void:
	# Template materials — each arachnid gets its OWN duplicate (so a hit can flash one spider
	# without lighting up all five). Brighter + more saturated violet than before: the old
	# near-black crystal crushed to a shapeless blob at gameplay distance. emission stays LOW
	# (the bright part is the unshaded core) so the faceted body reads by LIGHT, not as a flat
	# neon slab — emission_operator defaults to ADD and floods a surface if pushed.
	m_crystal = StandardMaterial3D.new()
	m_crystal.albedo_color = Color(0.24, 0.13, 0.52)
	m_crystal.metallic = 0.35
	m_crystal.roughness = 0.16
	m_crystal.emission_enabled = true
	m_crystal.emission = Color(0.46, 0.22, 1.0)
	m_crystal.emission_energy_multiplier = 0.55
	m_crystal.rim_enabled = true
	m_crystal.rim = 1.0
	m_crystal.rim_tint = 0.2

	m_crystal_dark = StandardMaterial3D.new()
	m_crystal_dark.albedo_color = Color(0.12, 0.07, 0.26)
	m_crystal_dark.metallic = 0.5
	m_crystal_dark.roughness = 0.22
	m_crystal_dark.emission_enabled = true
	m_crystal_dark.emission = Color(0.30, 0.13, 0.72)
	m_crystal_dark.emission_energy_multiplier = 0.22
	m_crystal_dark.rim_enabled = true
	m_crystal_dark.rim = 1.0

	m_core = StandardMaterial3D.new()
	m_core.albedo_color = Color(0.55, 0.25, 1.0)
	m_core.emission_enabled = true
	m_core.emission = Color(0.62, 0.20, 1.0)
	m_core.emission_energy_multiplier = 2.4
	m_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	m_eye = StandardMaterial3D.new()
	m_eye.albedo_color = Color(1.0, 0.55, 0.95)
	m_eye.emission_enabled = true
	m_eye.emission = Color(1.0, 0.42, 0.95)
	m_eye.emission_energy_multiplier = 2.6
	m_eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	m_flesh = StandardMaterial3D.new()
	m_flesh.albedo_color = Color(0.66, 0.29, 0.24)   # flushed, over-pumped, NOT plastic
	m_flesh.roughness = 0.72
	m_flesh.metallic_specular = 0.24
	# A stronger rim so his silhouette edges catch the cool cavern and separate from the black
	# background instead of dissolving into it — a big part of why he read as a flat slab.
	m_flesh.rim_enabled = true
	m_flesh.rim = 0.62
	m_flesh.rim_tint = 0.35

	m_flesh_dark = StandardMaterial3D.new()
	m_flesh_dark.albedo_color = Color(0.30, 0.09, 0.08)   # deep crease between muscle bellies
	m_flesh_dark.roughness = 0.62

	m_vein = StandardMaterial3D.new()
	m_vein.albedo_color = Color(0.42, 0.13, 0.22)
	m_vein.roughness = 0.35
	m_vein.rim_enabled = true
	m_vein.rim = 1.0

	m_gold = StandardMaterial3D.new()
	m_gold.albedo_color = Color(1.0, 0.78, 0.24)
	m_gold.metallic = 1.0
	m_gold.roughness = 0.18
	m_gold.emission_enabled = true
	m_gold.emission = Color(1.0, 0.72, 0.18)
	m_gold.emission_energy_multiplier = 0.9

	m_fur = StandardMaterial3D.new()
	m_fur.albedo_color = Color(0.80, 0.66, 0.47)     # cream Persian
	m_fur.roughness = 0.92
	m_fur.rim_enabled = true
	m_fur.rim = 0.45

	m_fur_dark = StandardMaterial3D.new()
	m_fur_dark.albedo_color = Color(0.60, 0.42, 0.28)
	m_fur_dark.roughness = 0.9

	m_jug = StandardMaterial3D.new()
	m_jug.albedo_color = Color(0.90, 0.87, 0.80)
	m_jug.roughness = 0.5

	m_glass = StandardMaterial3D.new()
	m_glass.albedo_color = Color(0.45, 1.0, 0.35)
	m_glass.emission_enabled = true
	m_glass.emission = Color(0.35, 1.0, 0.25)
	m_glass.emission_energy_multiplier = 1.3

	m_ring = StandardMaterial3D.new()
	m_ring.albedo_color = Color(1.0, 0.12, 0.08)
	m_ring.emission_enabled = true
	m_ring.emission = Color(1.0, 0.12, 0.05)
	m_ring.emission_energy_multiplier = 2.0
	m_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Soft radial contact-shadow. Real shadows are off (perf), so every creature drops a fake
	# dark disc onto the floor — the single biggest "these things are standing ON the ground"
	# cue. Baked once as a radial-alpha texture and reused.
	_shadow_tex = _make_shadow_tex()
	m_shadow = StandardMaterial3D.new()
	m_shadow.albedo_color = Color(0, 0, 0, 0.6)
	m_shadow.albedo_texture = _shadow_tex
	m_shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_shadow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m_shadow.cull_mode = BaseMaterial3D.CULL_DISABLED

func _make_shadow_tex() -> ImageTexture:
	var S: int = 64
	var img: Image = Image.create(S, S, false, Image.FORMAT_RGBA8)
	for yy in S:
		for xx in S:
			var dx: float = (float(xx) / float(S - 1) - 0.5) * 2.0
			var dy: float = (float(yy) / float(S - 1) - 0.5) * 2.0
			var r: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = a * a          # soft feathered edge
			img.set_pixel(xx, yy, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)

## Flat soft shadow disc dropped on the floor under a creature. Returns the mesh instance so a
## caller can fade it (e.g. during a death dissolve).
func _ground_shadow(parent: Node3D, radius: float, alpha: float) -> MeshInstance3D:
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	var mat: StandardMaterial3D = m_shadow.duplicate()
	mat.albedo_color = Color(0, 0, 0, alpha)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(0, 0.03, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ================================================================= mesh helpers
## Flat-shaded crystal shard: an irregular prism capped by two apexes. Flat normals are what
## make it read as FACETED — a smooth-normal mesh just looks like a lump.
func _shard(sides: int, r: float, top: float, bot: float, jitter: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var ring: Array[Vector3] = []
	var ring2: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var rr := r * (1.0 - jitter * 0.5 + rng.randf() * jitter)
		ring.append(Vector3(cos(a) * rr, top * 0.28, sin(a) * rr))
		ring2.append(Vector3(cos(a) * rr * 0.72, -bot * 0.30, sin(a) * rr * 0.72))
	var apex := Vector3(0, top, 0)
	var base := Vector3(0, -bot, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, ring[i], apex, ring[j])
		_tri(st, ring[j], ring2[j], ring[i])
		_tri(st, ring2[j], ring2[i], ring[i])
		_tri(st, ring2[j], base, ring2[i])
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)

## A unit crystal spike: faceted, radius 1 in XZ, running from y=0 (butt) to y=1 (point).
## Scaling/orienting it with a Basis is what lets every limb be defined by two endpoints.
func _unit_shard(sides: int, jitter: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var lo: Array[Vector3] = []
	var mid: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides) + rng.randf() * 0.12
		var rr := 1.0 - jitter * 0.5 + rng.randf() * jitter
		lo.append(Vector3(cos(a) * rr * 0.55, 0.02, sin(a) * rr * 0.55))
		mid.append(Vector3(cos(a) * rr, 0.26, sin(a) * rr))
		hi.append(Vector3(cos(a) * rr * 0.42, 0.74, sin(a) * rr * 0.42))
	var tip := Vector3(0, 1.0, 0)
	var butt := Vector3(0, 0.0, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, lo[i], mid[i], mid[j])
		_tri(st, lo[i], mid[j], lo[j])
		_tri(st, mid[i], hi[i], hi[j])
		_tri(st, mid[i], hi[j], mid[j])
		_tri(st, hi[i], tip, hi[j])
		_tri(st, lo[j], butt, lo[i])
	return st.commit()

## Place a unit shard so it runs from `a` to `b` with cross-section radius `rad`.
func _spike(parent: Node, mesh: ArrayMesh, a: Vector3, b: Vector3, rad: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	if d.length() < 0.0001:
		return null
	var y := d
	var ref := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(d).normalized() * rad
	var z := x.normalized().cross(d).normalized() * rad
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.transform = Transform3D(Basis(x, y, z), a)
	parent.add_child(m)
	return m

func _mi(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.scale = scl
	m.rotation = rot
	parent.add_child(m)
	return m

func _ball(parent: Node, pos: Vector3, r: Vector3, mat: Material, segs: int = 12, rings: int = 6) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = rings
	return _mi(parent, sm, mat, pos, r)

## Capsule-ish limb spanning two points (used for boss arms, veins, cat legs).
func _limb(parent: Node, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, segs: int = 10) -> MeshInstance3D:
	var d := b - a
	var len := d.length()
	if len < 0.0001:
		return null
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = len
	cm.radial_segments = segs
	cm.rings = 1
	var m := MeshInstance3D.new()
	m.mesh = cm
	m.material_override = mat
	var y := d / len
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(m)
	return m

## Nameplate + level + tiny health bar, billboarded above a creature.
## Everything goes under one holder stashed as the parent's "plate" meta, so the AI tick can
## fade a whole plate out as a unit (see _tick_spiders) instead of leaving six identical
## "Crystal Arachnid" labels littered across the frame at all times.
func _plate(parent: Node3D, text: String, lvl: int, col: Color, y: float, w: float) -> void:
	var holder := Node3D.new()
	holder.name = "Plate"
	parent.add_child(holder)
	parent.set_meta("plate", holder)

	var lab := Label3D.new()
	lab.text = "%s  ⟨%d⟩" % [text, lvl]
	# CRISPNESS: this was a WORLD-space label — a 96px glyph squeezed into ~10 screen pixels at
	# the camera's 16m standoff, i.e. a 10:1 downsample into unreadable mush. It is now
	# fixed_size, so the glyph is rastered at roughly the size it is displayed at, and holds a
	# constant, legible screen height no matter where the creature is standing.
	lab.font_size = 44
	lab.fixed_size = true
	lab.pixel_size = 0.000255 if w < 1.5 else 0.000420
	lab.modulate = col
	lab.outline_size = 9
	lab.outline_modulate = Color(0, 0, 0, 0.92)
	lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, y + w * 0.16, 0)
	lab.no_depth_test = false
	holder.add_child(lab)
	holder.set_meta("label", lab)
	holder.set_meta("base_col", col)

	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.02, 0.02, 0.03, 0.85)
	back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var fill := StandardMaterial3D.new()
	fill.albedo_color = Color(0.85, 0.12, 0.14)
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.emission_enabled = true
	fill.emission = Color(0.9, 0.1, 0.12)
	fill.emission_energy_multiplier = 1.2
	fill.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	var qb := QuadMesh.new()
	qb.size = Vector2(w, w * 0.09)
	_mi(holder, qb, back, Vector3(0, y, 0))
	var qf := QuadMesh.new()
	qf.size = Vector2(w * 0.86, w * 0.055)
	_mi(holder, qf, fill, Vector3(0, y, 0.001))

# ================================================================= Princess Donut
func _build_donut() -> void:
	donut = Node3D.new()
	donut.name = "PrincessDonut"
	add_child(donut)

	var rig := Node3D.new()
	donut.add_child(rig)

	var head_anchor: Node3D = null
	var packed: PackedScene = load("res://assets/Fox.glb")
	if packed != null:
		var fox: Node3D = packed.instantiate()
		rig.add_child(fox)
		# Fox.glb is authored ~1.4 units long; a cat beside a 2.4 m Carl reads at ~0.45 m tall.
		var ab := _aabb_of(fox)
		var k := 1.0
		if ab.size.y > 0.001:
			k = 0.56 / ab.size.y
		fox.scale = Vector3(k, k * 1.02, k)
		for m in fox.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = m_fur
		var ap: AnimationPlayer = fox.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for name in ap.get_animation_list():
				if name.to_lower().findn("walk") >= 0:
					ap.play(name, 0.2, 1.2)
					break
		var skel: Skeleton3D = fox.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel:
			var hb := -1
			for i in skel.get_bone_count():
				if skel.get_bone_name(i).to_lower().findn("head") >= 0:
					hb = i
					break
			if hb >= 0:
				var att := BoneAttachment3D.new()
				skel.add_child(att)
				att.bone_name = skel.get_bone_name(hb)
				att.bone_idx = hb
				head_anchor = att

	# Persian cat re-dress: ruff, ears, muzzle, whiskers — plus the crown that makes her Donut.
	var head := Node3D.new()
	if head_anchor:
		head_anchor.add_child(head)
		# the bone frame is the fox's; normalise it so our furniture stands upright in world space
		head.top_level = true
	else:
		rig.add_child(head)
		head.position = Vector3(0, 0.34, 0.24)
	donut.set_meta("head", head)

	_ball(head, Vector3(0, 0, 0), Vector3(0.14, 0.13, 0.13), m_fur, 12, 7)          # fluffy ruff
	_ball(head, Vector3(0, -0.02, 0.10), Vector3(0.075, 0.06, 0.06), m_fur, 10, 6)  # flat Persian muzzle
	for s in [-1.0, 1.0]:
		_ball(head, Vector3(0.05 * s, 0.005, 0.115), Vector3(0.020, 0.022, 0.012), m_eye, 8, 5)
		var ear := _shard(3, 0.055, 0.10, 0.02, 0.0, _rng)
		_mi(head, ear, m_fur, Vector3(0.075 * s, 0.105, -0.01), Vector3.ONE, Vector3(0, 0, -0.30 * s))
	_ball(head, Vector3(0, -0.035, 0.145), Vector3(0.018, 0.014, 0.012), m_fur_dark, 8, 5)   # nose

	# --- the crown: a golden band with five points, floating just above her head
	var crown := Node3D.new()
	crown.position = Vector3(0, 0.16, 0.0)
	head.add_child(crown)
	var band := CylinderMesh.new()
	band.top_radius = 0.072
	band.bottom_radius = 0.078
	band.height = 0.048
	band.radial_segments = 14
	band.cap_top = false
	band.cap_bottom = false
	_mi(crown, band, m_gold, Vector3.ZERO)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var spike := _shard(4, 0.026, 0.075, 0.01, 0.0, _rng)
		_mi(crown, spike, m_gold, Vector3(cos(a) * 0.072, 0.048, sin(a) * 0.072))
	var gem := SphereMesh.new()
	gem.radius = 1.0
	gem.height = 2.0
	gem.radial_segments = 8
	gem.rings = 5
	_mi(crown, gem, m_core, Vector3(0, 0.055, 0.0), Vector3.ONE * 0.030)
	var cl := OmniLight3D.new()
	cl.light_color = Color(1.0, 0.80, 0.35)
	cl.light_energy = 0.32
	cl.omni_range = 1.3
	cl.shadow_enabled = false
	cl.position = Vector3(0, 0.09, 0)
	crown.add_child(cl)

	_plate(donut, "Princess Donut", 8, Color(1.0, 0.85, 0.45), 0.82, 0.62)
	donut.position = Vector3(1.6, 0, 1.2)

func _aabb_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box

# ================================================================= crystalline arachnids
func _build_spiders() -> void:
	for i in SPIDER_COUNT:
		var s := _make_spider(i)
		add_child(s)
		var a := TAU * float(i) / float(SPIDER_COUNT) + 0.6
		var rad := 6.5 + _rng.randf() * 3.0
		s.position = Vector3(cos(a) * rad, 0, sin(a) * rad)
		spiders.append({
			"node": s,
			"legs": s.get_meta("legs"),
			"body": s.get_meta("body"),
			"speed": 1.5 + _rng.randf() * 0.6,
			"phase": _rng.randf() * TAU,
			# each one holds its own arc of the encirclement, so they never pile into one blob
			"slot": TAU * float(i) / float(SPIDER_COUNT),
			"stop": 3.1 + _rng.randf() * 1.1,
			# --- animation state (all absolute-time so it survives 1-8fps capture) ---
			"lstate": "idle",              # idle | wind | lunge | recover  (telegraphed attack)
			"lt": 0.0,                     # time in current lunge phase
			"lcd": 2.5 + _rng.randf() * 4.0,  # seconds until the next lunge
			"flinch": 0.0,                 # >0 while recoiling from a hit
			"flash": 0.0,                  # >0 = crystal hit-flash (decays)
			"dstate": "",                  # "" | dissolve | respawn  (death dissolve)
			"dt": 0.0,
			"mat_c": s.get_meta("mat_c"),
			"mat_cd": s.get_meta("mat_cd"),
			"mat_core": s.get_meta("mat_core"),
			"shadow": s.get_meta("shadow"),
			"base_scale": 0.86,
		})

func _make_spider(idx: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Arachnid%d" % idx

	# Per-spider material copies so a hit can flash THIS spider's crystal/core without touching
	# the other four (the templates are shared). Stored on the dict for the flash/dissolve paths.
	var mc: StandardMaterial3D = m_crystal.duplicate()
	var mcd: StandardMaterial3D = m_crystal_dark.duplicate()
	var mco: StandardMaterial3D = m_core.duplicate()
	mco.emission = Color(0.66, 0.28, 1.0)
	mco.emission_energy_multiplier = 2.6          # hostile violet core (kept short of blowing out)
	root.set_meta("mat_c", mc)
	root.set_meta("mat_cd", mcd)
	root.set_meta("mat_core", mco)

	# soft contact shadow FIRST so it sits under everything (root-local; scaled with the root)
	var shadow := _ground_shadow(root, 1.35, 0.62)
	root.set_meta("shadow", shadow)

	var body := Node3D.new()
	body.position = Vector3(0, 0.62, 0)
	root.add_child(body)

	var chunk := _unit_shard(7, 0.35, _rng)
	var limb_shard := _unit_shard(4, 0.20, _rng)

	# abdomen: a bigger rear crystal reared HIGH over the back — the menacing part of the read
	_spike(body, chunk, Vector3(0, -0.14, -0.28), Vector3(0, 0.56, -1.02), 0.50, mc)
	_spike(body, chunk, Vector3(0, -0.06, -0.16), Vector3(0, 0.38, -0.58), 0.28, mcd)
	# cephalothorax
	_spike(body, chunk, Vector3(0, -0.16, 0.30), Vector3(0, 0.24, -0.18), 0.40, mc)
	# head plate + fangs (chelicerae jut forward, darker so they read as a mouth)
	_spike(body, chunk, Vector3(0, -0.02, 0.12), Vector3(0, -0.12, 0.58), 0.20, mcd)
	for s in [-1.0, 1.0]:
		_spike(body, limb_shard, Vector3(0.08 * s, -0.10, 0.46), Vector3(0.13 * s, -0.46, 0.64), 0.055, mcd)
	# dorsal spines — sharper, taller, so the top edge reads as jagged crystal not a lump
	for i in 4:
		_spike(body, limb_shard, Vector3(0, 0.10 + 0.045 * i, -0.18 - 0.20 * i),
			Vector3(0, 0.60 + 0.10 * i, -0.30 - 0.24 * i), 0.05, mcd)

	# glowing violet core, half sunk into the thorax — bigger + brighter than before
	var core := SphereMesh.new()
	core.radius = 1.0
	core.height = 2.0
	core.radial_segments = 10
	core.rings = 6
	var core_mi := _mi(body, core, mco, Vector3(0, 0.12, -0.02), Vector3.ONE * 0.145)
	root.set_meta("core_mi", core_mi)
	# every arachnid casts a small violet pool now (grounding + the hostile glow), but with a
	# tight range + modest energy so five of them stay inside the light budget and the facets on
	# the body still read (a hotter light washed the crystal into one flat magenta blob).
	var l := OmniLight3D.new()
	l.light_color = Color(0.60, 0.26, 1.0)
	l.light_energy = 1.15 if idx < 3 else 0.85
	l.omni_range = 3.0
	l.shadow_enabled = false
	l.position = Vector3(0, 0.18, -0.02)
	body.add_child(l)

	# six bright eyes on the head plate
	for r in 2:
		for c in 3:
			var ex := (float(c) - 1.0) * 0.085
			_ball(body, Vector3(ex, 0.02 - 0.09 * r, 0.48 - absf(ex) * 0.5),
				Vector3.ONE * (0.030 if r == 0 else 0.020), m_eye, 6, 4)

	# --- eight legs. Each is hip -> knee (out and UP) -> foot (down to a point on the floor),
	# built from connected endpoints so the armature can never come apart. Knees peak higher and
	# feet reach wider now, for the unmistakable peaked-spider-leg silhouette at gameplay distance.
	var legs: Array = []
	for side in [-1.0, 1.0]:
		for i in 4:
			var yaw: float = (1.05 - 0.62 * float(i)) * side
			var hip := Node3D.new()
			hip.position = Vector3(0.20 * side, -0.02, 0.18 - 0.13 * float(i))
			hip.rotation = Vector3(0, yaw, 0)
			body.add_child(hip)
			var swing := Node3D.new()           # animated: the whole leg pivots here
			hip.add_child(swing)
			var knee_p := Vector3(0.54 * side, 0.62, 0.08)
			var foot_p := Vector3(0.98 * side, -0.62, 0.28)
			_spike(swing, limb_shard, Vector3.ZERO, knee_p, 0.085, mc)
			_ball(swing, knee_p, Vector3.ONE * 0.045, mc, 8, 5)
			var lower := Node3D.new()
			lower.position = knee_p
			swing.add_child(lower)
			_spike(lower, limb_shard, Vector3.ZERO, foot_p - knee_p, 0.062, mcd)
			# the two front leg-pairs are the ones that rear up on a lunge wind-up
			legs.append({"swing": swing, "lower": lower, "side": side, "i": i, "front": i <= 1})

	root.set_meta("legs", legs)
	root.set_meta("body", body)
	# knee-to-waist on Carl: bigger presence than the old 0.74, still short of the hero's read
	root.scale = Vector3.ONE * 0.86
	_plate(root, "Crystal Arachnid", 6, Color(0.82, 0.64, 1.0), 2.20, 0.74)
	return root

# ================================================================= THE JUICER
func _build_boss() -> void:
	boss = Node3D.new()
	boss.name = "TheJuicer"
	add_child(boss)

	var b := Node3D.new()                     # everything that bobs / sways
	boss.add_child(b)
	_boss_body = b

	# ---------------- legs (tree-trunk thick, comically short vs the torso)
	for s in [-1.0, 1.0]:
		var hip := Vector3(0.95 * s, 3.55, 0)
		var knee := Vector3(1.02 * s, 1.85, 0.10)
		var ankle := Vector3(1.05 * s, 0.42, -0.05)
		_limb(b, hip, knee, 0.92, 0.66, m_flesh, 12)
		_ball(b, hip.lerp(knee, 0.35), Vector3(0.98, 1.05, 0.95), m_flesh, 12, 7)
		_limb(b, knee, ankle, 0.62, 0.40, m_flesh, 10)
		_ball(b, knee.lerp(ankle, 0.32) - Vector3(0, 0, 0.22), Vector3(0.52, 0.62, 0.46), m_flesh, 10, 6)
		_ball(b, Vector3(1.05 * s, 0.26, 0.34), Vector3(0.60, 0.28, 0.86), m_flesh, 10, 6)   # foot

	# ---------------- hips + torso: a giant inverted triangle
	_ball(b, Vector3(0, 3.90, 0), Vector3(1.55, 0.95, 1.10), m_flesh, 14, 8)
	_ball(b, Vector3(0, 4.75, 0), Vector3(1.60, 0.90, 1.15), m_flesh, 14, 8)      # waist
	_ball(b, Vector3(0, 5.85, 0.05), Vector3(2.35, 1.15, 1.40), m_flesh, 16, 9)   # rib cage
	for s in [-1.0, 1.0]:
		_ball(b, Vector3(2.05 * s, 5.55, -0.05), Vector3(0.95, 1.25, 1.10), m_flesh, 12, 7)   # lats
		_ball(b, Vector3(1.05 * s, 6.55, 0.55), Vector3(1.25, 0.80, 0.85), m_flesh, 14, 8)    # pec
		_ball(b, Vector3(0.62 * s, 4.55, 0.85), Vector3(0.52, 0.36, 0.34), m_flesh, 10, 6)    # abs
		_ball(b, Vector3(0.62 * s, 5.15, 0.90), Vector3(0.55, 0.38, 0.36), m_flesh, 10, 6)
	_ball(b, Vector3(0, 6.55, 0.62), Vector3(0.16, 0.72, 0.30), m_flesh_dark, 8, 5)           # pec cleft
	for s2 in [-1.0, 1.0]:
		_ball(b, Vector3(1.05 * s2, 5.80, 0.70), Vector3(1.05, 0.10, 0.36), m_flesh_dark, 8, 5)   # under-pec
		_ball(b, Vector3(1.75 * s2, 6.30, 0.10), Vector3(0.10, 0.85, 0.62), m_flesh_dark, 8, 5)   # delt/pec split
		_ball(b, Vector3(0.62 * s2, 4.90, 1.00), Vector3(0.46, 0.07, 0.16), m_flesh_dark, 8, 5)   # ab line
		_ball(b, Vector3(0.95 * s2, 3.05, 0.62), Vector3(0.14, 0.62, 0.34), m_flesh_dark, 8, 5)   # quad split
	_ball(b, Vector3(0, 4.85, 0.98), Vector3(0.11, 0.62, 0.22), m_flesh_dark, 8, 5)           # linea alba

	# ---------------- absurd traps, swallowing the neck
	for s in [-1.0, 1.0]:
		_ball(b, Vector3(0.95 * s, 7.30, -0.10), Vector3(1.15, 0.85, 1.05), m_flesh, 14, 8)
	_ball(b, Vector3(0, 7.05, -0.15), Vector3(0.75, 0.60, 0.75), m_flesh, 10, 6)

	# ---------------- tiny angry head, sunk between the traps
	var head := Node3D.new()
	head.position = Vector3(0, 7.98, 0.95)
	head.rotation = Vector3(0.30, 0, 0)
	b.add_child(head)
	_ball(head, Vector3.ZERO, Vector3(0.52, 0.56, 0.52), m_flesh, 12, 7)
	_limb(head, Vector3(0, -0.42, -0.30), Vector3(0, -0.05, -0.05), 0.34, 0.30, m_flesh, 10)
	_ball(head, Vector3(0, 0.20, 0.30), Vector3(0.42, 0.11, 0.18), m_flesh_dark, 10, 5)      # scowling brow
	for s in [-1.0, 1.0]:
		var e := SphereMesh.new()
		e.radius = 1.0
		e.height = 2.0
		e.radial_segments = 8
		e.rings = 5
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(1.0, 0.25, 0.15)
		em.emission_enabled = true
		em.emission = Color(1.0, 0.18, 0.08)
		em.emission_energy_multiplier = 2.6
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mi(head, e, em, Vector3(0.19 * s, 0.06, 0.40), Vector3.ONE * 0.085)
	_ball(head, Vector3(0, -0.26, 0.30), Vector3(0.30, 0.16, 0.24), m_flesh_dark, 10, 5)     # roaring jaw
	_ball(head, Vector3(0, 0.40, -0.16), Vector3(0.44, 0.22, 0.40), m_flesh_dark, 10, 6)     # buzzcut

	# ---------------- arms: forced out wide, they physically cannot hang down
	for s in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(2.20 * s, 6.60, 0)
		b.add_child(arm)
		if s < 0.0:
			_boss_arm_l = arm
		else:
			_boss_arm_r = arm
		_ball(arm, Vector3(0, 0, 0), Vector3(1.20, 1.15, 1.15), m_flesh, 14, 8)             # delt
		var elbow := Vector3(1.30 * s, -1.95, 0.15)
		var wrist := Vector3(1.55 * s, -3.65, 0.55)
		_limb(arm, Vector3(0.25 * s, -0.35, 0), elbow, 0.86, 0.62, m_flesh, 12)
		_ball(arm, Vector3(0.80 * s, -1.05, 0.30), Vector3(0.72, 0.85, 0.70), m_flesh, 12, 7)  # bicep
		_ball(arm, Vector3(0.62 * s, -0.42, 0.28), Vector3(0.70, 0.09, 0.38), m_flesh_dark, 8, 5)  # delt/bicep split
		_ball(arm, Vector3(0.72 * s, -1.10, -0.42), Vector3(0.55, 0.80, 0.52), m_flesh, 10, 6) # tricep
		_limb(arm, elbow, wrist, 0.66, 0.42, m_flesh, 10)
		_ball(arm, elbow.lerp(wrist, 0.30), Vector3(0.60, 0.72, 0.58), m_flesh, 10, 6)
		_ball(arm, wrist, Vector3(0.50, 0.52, 0.50), m_flesh, 10, 6)                        # fist
		# bulging veins tracked over the arm
		for v in 3:
			var t0 := 0.15 + 0.25 * v
			var a0 := Vector3(0.25 * s, -0.35, 0).lerp(elbow, t0) + Vector3(0.55 * s, 0, 0.45)
			var a1 := Vector3(0.25 * s, -0.35, 0).lerp(elbow, t0 + 0.30) + Vector3(0.30 * s, 0, 0.62)
			_limb(arm, a0, a1, 0.055, 0.045, m_vein, 6)
		if s < 0.0:
			_build_jug(arm, wrist)

	# chest veins
	for v in 4:
		var y := 5.6 + 0.55 * v
		_limb(b, Vector3(-0.9 + 0.6 * v, y, 1.15), Vector3(-0.4 + 0.6 * v, y + 0.5, 1.05), 0.055, 0.04, m_vein, 6)

	_build_syringes(b)

	# ---------------- slam telegraph ring
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 40
	ring.ring_segments = 5
	_boss_ring = _mi(boss, ring, m_ring, Vector3(0, 0.06, 0))
	_boss_ring.visible = false

	_boss_light = OmniLight3D.new()
	_boss_light.light_color = Color(1.0, 0.30, 0.18)
	_boss_light.light_energy = 0.0
	_boss_light.omni_range = 14.0
	_boss_light.shadow_enabled = false
	_boss_light.position = Vector3(0, 1.2, 0)
	boss.add_child(_boss_light)

	# ---------------- dedicated 3-point rig riding with the Juicer.
	# The cavern grade is deliberately moody and was crushing an 8.9m dark-red hulk into a flat
	# black slab at boss-cam distance. This is a self-contained key/fill/rim that models his
	# musculature back out of the shadows WITHOUT touching world.gd's global grade — the deep
	# blacks and the moody tone map are untouched.
	#
	# FILL — soft warm wash straight-on so the whey jug, syringes and chest read at all.
	var boss_fill := OmniLight3D.new()
	boss_fill.light_color = Color(1.0, 0.64, 0.58)
	boss_fill.light_energy = 1.30
	boss_fill.omni_range = 15.0
	boss_fill.omni_attenuation = 1.5
	boss_fill.shadow_enabled = false
	boss_fill.position = Vector3(0.0, BOSS_HEIGHT * 0.70, 4.0)
	boss.add_child(boss_fill)

	# KEY — warmer, from upper front-side. This is what carves each muscle belly: a real
	# N·L gradient across his pecs/delts/arms so he stops reading as one dark mass. The dark
	# crease slivers between muscles only "cut" once there is a key like this lighting the domes.
	var boss_key := OmniLight3D.new()
	boss_key.light_color = Color(1.0, 0.74, 0.52)
	boss_key.light_energy = 2.30
	boss_key.omni_range = 17.0
	boss_key.omni_attenuation = 1.4
	boss_key.shadow_enabled = false
	boss_key.position = Vector3(4.2, BOSS_HEIGHT * 0.98, 3.4)
	boss.add_child(boss_key)

	# RIM — cool indigo from behind and above, matching the cavern ambient. It draws a bright
	# cold edge down his traps, shoulders and lats so his silhouette pops OFF the black
	# background — the classic D4 separation that keeps a dark boss from vanishing into the murk.
	var boss_rim := OmniLight3D.new()
	boss_rim.light_color = Color(0.48, 0.62, 1.0)
	boss_rim.light_energy = 2.60
	boss_rim.omni_range = 16.0
	boss_rim.omni_attenuation = 1.3
	boss_rim.shadow_enabled = false
	boss_rim.position = Vector3(-2.6, BOSS_HEIGHT * 0.92, -5.2)
	boss.add_child(boss_rim)

	# grounds the 8.9m hulk so he isn't floating on the cavern floor
	_ground_shadow(boss, 3.4, 0.6)

	# scale the whole hulk to the target height
	var k := BOSS_HEIGHT / 8.15
	b.scale = Vector3(k, k, k)
	# NO world-space nameplate on the boss: the HUD already owns his identity with a full
	# broadcast boss bar (name, subtitle, level diamond, affix pips). Now that the boss camera
	# actually frames all 8.9m of him, a floating "The Juicer ⟨15⟩" landed right on top of that
	# bar and read as a smear of doubled text.
	boss.position = _boss_pos

func _build_jug(parent: Node3D, wrist: Vector3) -> void:
	var jug := Node3D.new()
	jug.position = wrist + Vector3(-0.35, -0.55, 0.35)
	jug.rotation = Vector3(0.15, 0, 0.35)
	parent.add_child(jug)
	var body := CylinderMesh.new()
	body.top_radius = 0.58
	body.bottom_radius = 0.64
	body.height = 1.35
	body.radial_segments = 14
	_mi(jug, body, m_jug, Vector3.ZERO)
	var lid := CylinderMesh.new()
	lid.top_radius = 0.30
	lid.bottom_radius = 0.36
	lid.height = 0.30
	lid.radial_segments = 12
	var lidm := StandardMaterial3D.new()
	lidm.albedo_color = Color(0.75, 0.10, 0.09)
	lidm.roughness = 0.5
	_mi(jug, lid, lidm, Vector3(0, 0.80, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.66
	band.bottom_radius = 0.66
	band.height = 0.62
	band.radial_segments = 14
	band.cap_top = false
	band.cap_bottom = false
	_mi(jug, band, lidm, Vector3(0, 0.05, 0))
	for a in [0.0, PI]:
		var lab := Label3D.new()
		lab.text = "MUTANT\nWHEY"
		lab.font_size = 52
		lab.pixel_size = 0.0042
		lab.modulate = Color(1.0, 0.95, 0.75)
		lab.outline_size = 18
		lab.outline_modulate = Color(0.25, 0.0, 0.0, 1.0)
		lab.position = Vector3(sin(a) * 0.68, 0.06, cos(a) * 0.68)
		lab.rotation = Vector3(0, a, 0)
		lab.double_sided = false
		jug.add_child(lab)

func _build_syringes(b: Node3D) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78)
	steel.metallic = 0.9
	steel.roughness = 0.25
	var specs := [
		[Vector3(-1.15, 6.30, -1.15), Vector3(-0.55, 0.55, -0.62)],
		[Vector3(0.55, 6.85, -1.05), Vector3(0.35, 0.75, -0.56)],
		[Vector3(1.35, 5.75, -1.10), Vector3(0.62, 0.42, -0.66)],
		[Vector3(-0.35, 5.30, -1.20), Vector3(-0.20, 0.60, -0.77)],
	]
	for sp in specs:
		var base: Vector3 = sp[0]
		var dir: Vector3 = (sp[1] as Vector3).normalized()
		_limb(b, base, base + dir * 0.92, 0.105, 0.105, m_glass, 8)
		_limb(b, base + dir * 0.92, base + dir * 1.16, 0.075, 0.075, steel, 8)
		_limb(b, base + dir * 1.16, base + dir * 1.24, 0.20, 0.20, steel, 8)
		_limb(b, base - dir * 0.34, base, 0.045, 0.045, steel, 6)

# ================================================================= AI / animation
func _process(delta: float) -> void:
	_t += delta
	if game == null:
		return
	var hero: Vector3 = game.hero_pos if "hero_pos" in game else Vector3.ZERO
	_tick_donut(delta, hero)
	_tick_spiders(delta, hero)
	_tick_boss(delta, hero)

# ------------------------------------------------------------------ combat reactions (contract)
## A hero blow near an arachnid: flinch it, flash its crystal, knock it back off the hero.
func _on_hero_attacked(target_pos: Vector3, _damage: int, crit: bool) -> void:
	var i: int = _nearest_spider(target_pos, 3.6)
	if i >= 0:
		_hit_spider(i, crit)

## An enemy death near an arachnid dissolves it (it then respawns to keep the ring populated).
func _on_enemy_killed(pos: Vector3) -> void:
	var i: int = _nearest_spider(pos, 3.2)
	if i >= 0 and String(spiders[i]["dstate"]) == "":
		spiders[i]["dstate"] = "dissolve"
		spiders[i]["dt"] = 0.0

func _nearest_spider(pos: Vector3, max_d: float) -> int:
	var best: int = -1
	var bd: float = max_d
	for i in spiders.size():
		var n: Node3D = spiders[i]["node"]
		if String(spiders[i]["dstate"]) != "":
			continue
		var d: float = Vector3(n.position.x - pos.x, 0.0, n.position.z - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best

## Apply a flinch: recoil timer, crystal hit-flash, and a real knockback impulse away from Carl.
func _hit_spider(i: int, crit: bool) -> void:
	var s: Dictionary = spiders[i]
	if String(s["dstate"]) != "":
		return
	s["flinch"] = 0.32
	s["flash"] = 0.22
	var n: Node3D = s["node"]
	var hero: Vector3 = game.hero_pos if game and "hero_pos" in game else Vector3.ZERO
	var away: Vector3 = Vector3(n.position.x - hero.x, 0.0, n.position.z - hero.z)
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	n.position += away.normalized() * (0.85 if crit else 0.5)

func _tick_donut(delta: float, hero: Vector3) -> void:
	if donut == null:
		return
	var carl: Node3D = game.carl if "carl" in game else null
	var face: float = carl.rotation.y if carl else 0.0
	# heel position: at Carl's left and slightly behind, in HIS frame
	var off := Vector3(cos(face) * -1.15, 0, sin(face) * 1.15) + Vector3(sin(face), 0, cos(face)) * -0.55
	var target := hero + off
	var to := target - donut.position
	to.y = 0
	var d := to.length()
	if d > 0.10:
		var sp: float = clampf(d * 3.2, 0.0, 6.5)
		donut.position += to.normalized() * sp * delta
		donut.rotation.y = lerp_angle(donut.rotation.y, atan2(to.x, to.z), 0.20)
	donut.position.y = sin(_t * 7.0) * 0.02
	var head: Node3D = donut.get_meta("head") if donut.has_meta("head") else null
	if head and head.top_level:
		# the fox head bone rolls around; keep the crown level and just follow the position
		var gp := head.get_parent() as Node3D
		if gp:
			head.global_transform = Transform3D(Basis(Vector3.UP, donut.rotation.y), gp.global_position)

func _tick_spiders(delta: float, hero: Vector3) -> void:
	# Self-driven liveliness so captures always show a hit-reaction and a death dissolve even
	# though the demo director never actually strikes a real spider (contract signals aside).
	_spider_flinch_cd -= delta
	if _spider_flinch_cd <= 0.0 and spiders.size() > 0:
		_spider_flinch_cd = _rng.randf_range(1.2, 2.6)
		var pick: int = _engaged_spider(hero)
		if pick >= 0:
			_hit_spider(pick, _rng.randf() < 0.35)
	_spider_death_cd -= delta
	if _spider_death_cd <= 0.0 and spiders.size() > 0:
		_spider_death_cd = _rng.randf_range(7.0, 11.0)
		var pk: int = _engaged_spider(hero)
		if pk >= 0 and String(spiders[pk]["dstate"]) == "":
			spiders[pk]["dstate"] = "dissolve"
			spiders[pk]["dt"] = 0.0

	for s in spiders:
		var n: Node3D = s["node"]
		var body: Node3D = s["body"]

		# ---- death dissolve: freeze, sink, shrink, flare then fade, respawn to keep the ring full
		if String(s["dstate"]) == "dissolve":
			_tick_dissolve(s, n, body, hero, delta)
			continue

		var ring: float = float(s["stop"])
		var anchor: Vector3 = hero + Vector3(cos(float(s["slot"])), 0, sin(float(s["slot"]))) * ring
		var to := anchor - n.position
		to.y = 0
		var d := to.length()
		var face := hero - n.position

		# ---- telegraphed attack state machine (all absolute-time; survives 1-8fps captures)
		var lst: String = String(s["lstate"])
		s["lt"] = float(s["lt"]) + delta
		var lt: float = float(s["lt"])
		var wind_k: float = 0.0      # 0..1 crouch/rear wind-up
		var strike_k: float = 0.0    # 0..1 forward strike
		match lst:
			"idle":
				s["lcd"] = float(s["lcd"]) - delta
				if float(s["lcd"]) <= 0.0 and face.length() < 9.0:
					s["lstate"] = "wind"
					s["lt"] = 0.0
			"wind":
				wind_k = clampf(lt / 0.55, 0.0, 1.0)
				if lt >= 0.55:
					s["lstate"] = "lunge"
					s["lt"] = 0.0
			"lunge":
				wind_k = 1.0 - clampf(lt / 0.30, 0.0, 1.0)
				strike_k = clampf(lt / 0.30, 0.0, 1.0)
				if lt >= 0.30:
					s["lstate"] = "recover"
					s["lt"] = 0.0
			"recover":
				strike_k = 1.0 - clampf(lt / 0.65, 0.0, 1.0)
				if lt >= 0.65:
					s["lstate"] = "idle"
					s["lt"] = 0.0
					s["lcd"] = _rng.randf_range(3.5, 7.5)

		# ---- movement: hold+creep-back during wind-up, DART on the lunge, else seek the ring
		if lst == "lunge":
			var din: Vector3 = face
			din.y = 0.0
			if din.length() > 0.01:
				n.position += din.normalized() * (float(s["speed"]) + 5.5) * strike_k * delta
		elif lst == "wind":
			# rear back a touch — the read is "it's coiling to pounce"
			var db: Vector3 = face
			db.y = 0.0
			if db.length() > 0.01:
				n.position -= db.normalized() * 0.6 * wind_k * delta
		else:
			var moving := d > 0.5
			if moving:
				var dir := to.normalized()
				var strafe := Vector3(-dir.z, 0, dir.x) * sin(_t * 2.2 + float(s["phase"])) * 0.45
				n.position += (dir + strafe).normalized() * float(s["speed"]) * delta

		n.rotation.y = lerp_angle(n.rotation.y, atan2(face.x, face.z), 0.12)

		# ---- hit reaction (flinch + crystal flash), both decaying on absolute time
		s["flinch"] = maxf(0.0, float(s["flinch"]) - delta)
		s["flash"] = maxf(0.0, float(s["flash"]) - delta)
		var fe: float = float(s["flinch"]) / 0.32          # 1 -> 0 recoil envelope
		var flash_e: float = float(s["flash"]) / 0.22       # 1 -> 0 hit-flash envelope
		var mc: StandardMaterial3D = s["mat_c"]
		var mcd: StandardMaterial3D = s["mat_cd"]
		var mco: StandardMaterial3D = s["mat_core"]
		mc.emission_energy_multiplier = 0.55 + 2.4 * flash_e
		mcd.emission_energy_multiplier = 0.22 + 1.6 * flash_e
		mco.emission_energy_multiplier = 2.6 + 3.0 * flash_e

		# ---- plates: fade out on the stragglers so the frame carries 2-3 readable plates
		if n.has_meta("plate"):
			var holder: Node3D = n.get_meta("plate")
			var a: float = clampf((10.5 - face.length()) / 2.5, 0.0, 1.0)
			holder.visible = a > 0.03
			if holder.visible and holder.has_meta("label"):
				var pl: Label3D = holder.get_meta("label")
				var bc: Color = holder.get_meta("base_col")
				pl.modulate = Color(bc.r, bc.g, bc.b, a)

		# ---- body pose: idle bob + wind-up crouch (rear up) + strike (lunge forward) + flinch recoil
		var bob: float = sin(_t * 5.0 + float(s["phase"])) * 0.04
		var crouch: float = wind_k * 0.14
		body.position.y = 0.62 + bob - crouch - fe * 0.06
		# pitch: negative = front rears UP (wind-up), positive = front slams DOWN (strike)
		body.rotation.x = -0.42 * wind_k + 0.5 * strike_k - 0.55 * fe
		body.rotation.z = sin(_t * 5.0 + float(s["phase"]) + 1.0) * 0.05 + sin(_t * 42.0) * 0.06 * fe

		# ---- legs: normal crawl, but the two front pairs REAR when winding up / slam on the strike
		var moving2 := lst != "wind" and lst != "lunge" and d > 0.5
		var rate: float = 8.0 if moving2 else 2.6
		var amp: float = 1.0 if moving2 else 0.34
		for leg in s["legs"]:
			var ph: float = float(s["phase"]) + float(leg["i"]) * 1.9 + (0.0 if leg["side"] > 0.0 else PI)
			var w := sin(_t * rate + ph)
			var swing: Node3D = leg["swing"]
			var lower: Node3D = leg["lower"]
			var lift: float = 0.0
			if bool(leg["front"]):
				lift = wind_k * 0.7 - strike_k * 0.5     # raise on wind-up, stab down on strike
			swing.rotation = Vector3(0, w * 0.26 * amp, maxf(w, 0.0) * 0.30 * amp * -leg["side"] + lift)
			lower.rotation = Vector3(0, 0, maxf(-w, 0.0) * 0.34 * amp * leg["side"])

## Return the arachnid closest to Carl that is alive and actually engaged, or -1.
func _engaged_spider(hero: Vector3) -> int:
	var best: int = -1
	var bd: float = 9.0
	for i in spiders.size():
		if String(spiders[i]["dstate"]) != "":
			continue
		var n: Node3D = spiders[i]["node"]
		var d: float = Vector3(n.position.x - hero.x, 0.0, n.position.z - hero.z).length()
		if d < bd:
			bd = d
			best = i
	return best

## Death dissolve: sink + shrink + a violet flare that fades, then respawn at a fresh ring slot.
func _tick_dissolve(s: Dictionary, n: Node3D, body: Node3D, hero: Vector3, delta: float) -> void:
	s["dt"] = float(s["dt"]) + delta
	var p: float = clampf(float(s["dt"]) / 0.9, 0.0, 1.0)
	var base_scale: float = float(s["base_scale"])
	n.scale = Vector3.ONE * base_scale * (1.0 - 0.55 * p)
	body.position.y = 0.62 - 0.9 * p
	var mc: StandardMaterial3D = s["mat_c"]
	var mcd: StandardMaterial3D = s["mat_cd"]
	var mco: StandardMaterial3D = s["mat_core"]
	var flare: float = sin(p * PI)                     # brighten then die
	mc.emission_energy_multiplier = 0.55 + 3.0 * flare
	mcd.emission_energy_multiplier = 0.22 + 2.0 * flare
	mco.emission_energy_multiplier = 2.6 + 4.0 * flare
	var sh: MeshInstance3D = s["shadow"]
	if sh and sh.material_override:
		(sh.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.62 * (1.0 - p))
	if n.has_meta("plate"):
		(n.get_meta("plate") as Node3D).visible = false
	if p >= 1.0:
		# respawn on a fresh far ring slot so the encirclement stays populated
		var a: float = _rng.randf() * TAU
		var rad: float = 7.0 + _rng.randf() * 2.5
		n.position = hero + Vector3(cos(a), 0, sin(a)) * rad
		n.scale = Vector3.ONE * base_scale
		body.position.y = 0.62
		mc.emission_energy_multiplier = 0.55
		mcd.emission_energy_multiplier = 0.22
		mco.emission_energy_multiplier = 2.6
		if sh and sh.material_override:
			(sh.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.62)
		s["slot"] = a
		s["stop"] = 3.1 + _rng.randf() * 1.1
		s["dstate"] = ""
		s["dt"] = 0.0
		s["lstate"] = "idle"
		s["lt"] = 0.0
		s["lcd"] = _rng.randf_range(2.5, 5.0)
		s["flinch"] = 0.0
		s["flash"] = 0.0

func _tick_boss(delta: float, hero: Vector3) -> void:
	if boss == null:
		return
	_boss_ph_t += delta
	var to := hero - _boss_pos
	to.y = 0
	var d := to.length()
	if d > 0.01:
		_boss_face = lerp_angle(_boss_face, atan2(to.x, to.z), 0.05)

	match _boss_phase:
		"walk":
			# he holds at ~9.5 m: any closer and an 8.9 m hulk simply falls out of the
			# game's fixed iso frame, so the whole silhouette stops reading.
			if d > 9.0:
				_boss_pos += to.normalized() * 1.30 * delta
			_boss_cd -= delta
			if _boss_cd <= 0.0 and d < 16.0:
				_boss_phase = "telegraph"
				_boss_ph_t = 0.0
				_boss_ring.visible = true
		"telegraph":
			var k: float = clampf(_boss_ph_t / 1.30, 0.0, 1.0)
			var r: float = lerpf(1.2, 5.6, k)
			_boss_ring.scale = Vector3(r, 1.0 + 5.0 * k, r)
			var pulse: float = 0.55 + 0.45 * sin(_boss_ph_t * 22.0)
			m_ring.emission_energy_multiplier = 1.2 + 2.6 * k * pulse
			_boss_light.light_energy = 1.6 * k
			if k >= 1.0:
				_boss_phase = "slam"
				_boss_ph_t = 0.0
		"slam":
			var k: float = clampf(_boss_ph_t / 0.35, 0.0, 1.0)
			_boss_light.light_energy = lerpf(5.0, 0.0, k)
			_boss_ring.scale = Vector3(5.6, 6.0, 5.6) * (1.0 + 0.25 * k)
			m_ring.emission_energy_multiplier = lerpf(6.0, 0.0, k)
			if k >= 1.0:
				_boss_phase = "recover"
				_boss_ph_t = 0.0
				_boss_ring.visible = false
				if game.has_signal("hero_attacked"):
					pass
		"recover":
			if _boss_ph_t > 1.5:
				_boss_phase = "walk"
				_boss_cd = 5.5

	boss.position = _boss_pos
	boss.rotation.y = _boss_face
	_boss_ring.rotation.y = -_boss_face      # ring stays world-aligned

	# --- lumbering body motion + slam arm arc
	var lumber := sin(_t * 1.55)
	_boss_body.position.y = absf(lumber) * 0.16 - 0.08
	_boss_body.rotation.z = lumber * 0.075
	_boss_body.rotation.x = -0.05 + sin(_t * 3.1) * 0.02
	var raise := 0.0
	match _boss_phase:
		"telegraph":
			raise = -clampf(_boss_ph_t / 1.30, 0.0, 1.0) * 1.5
		"slam":
			raise = lerpf(-1.5, 0.85, clampf(_boss_ph_t / 0.35, 0.0, 1.0))
		"recover":
			raise = lerpf(0.85, 0.0, clampf(_boss_ph_t / 1.5, 0.0, 1.0))
		_:
			raise = sin(_t * 1.55 + 0.6) * 0.16
	if _boss_arm_l:
		_boss_arm_l.rotation.x = raise
	if _boss_arm_r:
		_boss_arm_r.rotation.x = raise
