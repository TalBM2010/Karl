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

# boss state machine
var _boss_pos := Vector3(0, 0, -11.0)
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

func setup(g) -> void:
	game = g
	_rng.seed = 91177
	_materials()
	_build_donut()
	_build_spiders()
	_build_boss()
	set_process(true)

# ================================================================= materials
func _materials() -> void:
	m_crystal = StandardMaterial3D.new()
	m_crystal.albedo_color = Color(0.30, 0.20, 0.52)
	m_crystal.metallic = 0.30
	m_crystal.roughness = 0.14
	m_crystal.emission_enabled = true
	m_crystal.emission = Color(0.34, 0.16, 0.78)
	m_crystal.emission_energy_multiplier = 0.45
	m_crystal.rim_enabled = true
	m_crystal.rim = 1.0

	m_crystal_dark = StandardMaterial3D.new()
	m_crystal_dark.albedo_color = Color(0.13, 0.09, 0.26)
	m_crystal_dark.metallic = 0.45
	m_crystal_dark.roughness = 0.22
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
	m_flesh.albedo_color = Color(0.74, 0.31, 0.25)   # flushed, over-pumped
	m_flesh.roughness = 0.38
	m_flesh.metallic_specular = 0.6
	m_flesh.rim_enabled = true
	m_flesh.rim = 0.85
	m_flesh.rim_tint = 0.25

	m_flesh_dark = StandardMaterial3D.new()
	m_flesh_dark.albedo_color = Color(0.34, 0.10, 0.09)
	m_flesh_dark.roughness = 0.6

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
	m_gold.emission_energy_multiplier = 1.5

	m_fur = StandardMaterial3D.new()
	m_fur.albedo_color = Color(0.93, 0.80, 0.60)     # cream Persian
	m_fur.roughness = 0.85
	m_fur.rim_enabled = true
	m_fur.rim = 0.9

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
func _plate(parent: Node3D, text: String, lvl: int, col: Color, y: float, w: float) -> void:
	var lab := Label3D.new()
	lab.text = "%s  ⟨%d⟩" % [text, lvl]
	lab.font_size = 96
	lab.pixel_size = w * 0.0022
	lab.modulate = col
	lab.outline_size = 26
	lab.outline_modulate = Color(0, 0, 0, 0.9)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, y + w * 0.16, 0)
	lab.no_depth_test = false
	parent.add_child(lab)

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
	_mi(parent, qb, back, Vector3(0, y, 0))
	var qf := QuadMesh.new()
	qf.size = Vector2(w * 0.86, w * 0.055)
	_mi(parent, qf, fill, Vector3(0, y, 0.001))

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
			k = 0.46 / ab.size.y
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
	cl.light_energy = 1.5
	cl.omni_range = 3.2
	cl.shadow_enabled = false
	cl.position = Vector3(0, 0.09, 0)
	crown.add_child(cl)

	_plate(donut, "Princess Donut", 8, Color(1.0, 0.85, 0.45), 0.86, 0.75)
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
		var rad := 6.0 + _rng.randf() * 3.0
		s.position = Vector3(cos(a) * rad, 0, sin(a) * rad)
		spiders.append({
			"node": s,
			"legs": s.get_meta("legs"),
			"speed": 1.5 + _rng.randf() * 0.6,
			"phase": _rng.randf() * TAU,
			"stop": 2.2 + _rng.randf() * 0.9,
		})

func _make_spider(idx: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Arachnid%d" % idx
	var body := Node3D.new()
	body.position = Vector3(0, 0.78, 0)
	root.add_child(body)

	# abdomen: a big rear crystal, tipped up — the menacing part of the silhouette
	var abd := _shard(7, 0.42, 0.62, 0.34, 0.35, _rng)
	_mi(body, abd, m_crystal, Vector3(0, 0.10, -0.52), Vector3(1.0, 1.15, 1.25), Vector3(-0.55, 0, 0))
	# cephalothorax
	var tho := _shard(6, 0.30, 0.30, 0.26, 0.3, _rng)
	_mi(body, tho, m_crystal, Vector3(0, 0.0, 0.06), Vector3(1.1, 0.9, 1.25))
	# glowing violet core, half sunk into the thorax
	var core := SphereMesh.new()
	core.radius = 1.0
	core.height = 2.0
	core.radial_segments = 10
	core.rings = 6
	_mi(body, core, m_core, Vector3(0, 0.06, -0.10), Vector3.ONE * 0.15)
	if idx < 2:
		var l := OmniLight3D.new()
		l.light_color = Color(0.62, 0.24, 1.0)
		l.light_energy = 2.2
		l.omni_range = 5.0
		l.shadow_enabled = false
		l.position = Vector3(0, 0.10, -0.10)
		body.add_child(l)

	# head shards + six bright eyes
	_mi(body, _shard(5, 0.20, 0.20, 0.16, 0.25, _rng), m_crystal_dark, Vector3(0, -0.03, 0.34),
		Vector3(1.0, 0.8, 1.3))
	for r in 2:
		for c in 3:
			var ex := (float(c) - 1.0) * 0.10
			_ball(body, Vector3(ex, 0.02 - 0.07 * r, 0.48 - absf(ex) * 0.4),
				Vector3.ONE * (0.030 if r == 0 else 0.021), m_eye, 6, 4)
	# fangs
	for s in [-1.0, 1.0]:
		_mi(body, _shard(4, 0.05, 0.05, 0.22, 0.0, _rng), m_crystal_dark,
			Vector3(0.07 * s, -0.14, 0.42), Vector3.ONE, Vector3(0.5, 0, 0))

	# --- eight legs, each a two-segment crystal armature that arches ABOVE the body
	var legs: Array = []
	var femur := _shard(4, 0.075, 0.5, 0.10, 0.15, _rng)
	var tibia := _shard(4, 0.055, 0.5, 0.08, 0.15, _rng)
	for side in [-1.0, 1.0]:
		for i in 4:
			var yaw := (0.85 - 0.52 * float(i)) * side
			var hip := Node3D.new()
			hip.position = Vector3(0.22 * side, 0.02, 0.22 - 0.15 * float(i))
			hip.rotation = Vector3(0, yaw, 0)
			body.add_child(hip)
			var up := Node3D.new()
			hip.add_child(up)
			# femur: out and UP
			var f := _mi(up, femur, m_crystal, Vector3(0.34 * side, 0.30, 0), Vector3(1, 1.25, 1),
				Vector3(0, 0, -0.95 * side))
			# knee node so the tibia spears back down to a point on the floor
			var knee := Node3D.new()
			knee.position = Vector3(0.66 * side, 0.60, 0)
			up.add_child(knee)
			_mi(knee, tibia, m_crystal_dark, Vector3(0.22 * side, -0.42, 0), Vector3(1, 1.45, 1),
				Vector3(0, 0, 0.42 * side))
			legs.append({"hip": hip, "up": up, "side": side, "i": i})

	root.set_meta("legs", legs)
	root.set_meta("body", body)
	_plate(root, "Crystal Arachnid", 6, Color(0.80, 0.62, 1.0), 1.75, 0.95)
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
	_ball(b, Vector3(0, 4.85, 0.98), Vector3(0.11, 0.62, 0.22), m_flesh_dark, 8, 5)           # linea alba

	# ---------------- absurd traps, swallowing the neck
	for s in [-1.0, 1.0]:
		_ball(b, Vector3(0.95 * s, 7.30, -0.10), Vector3(1.15, 0.85, 1.05), m_flesh, 14, 8)
	_ball(b, Vector3(0, 7.05, -0.15), Vector3(0.75, 0.60, 0.75), m_flesh, 10, 6)

	# ---------------- tiny angry head, sunk between the traps
	var head := Node3D.new()
	head.position = Vector3(0, 7.55, 0.28)
	head.rotation = Vector3(0.22, 0, 0)
	b.add_child(head)
	_ball(head, Vector3.ZERO, Vector3(0.46, 0.50, 0.46), m_flesh, 12, 7)
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
	_ball(head, Vector3(0, 0.34, -0.10), Vector3(0.44, 0.30, 0.42), m_flesh_dark, 10, 6)     # buzzcut

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

	# scale the whole hulk to the target height
	var k := BOSS_HEIGHT / 8.15
	b.scale = Vector3(k, k, k)
	_plate(boss, "The Juicer", 15, Color(1.0, 0.42, 0.30), BOSS_HEIGHT + 0.9, 3.4)
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
		lab.font_size = 64
		lab.pixel_size = 0.0055
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
		_limb(b, base, base + dir * 0.95, 0.14, 0.14, m_glass, 8)
		_limb(b, base + dir * 0.95, base + dir * 1.28, 0.16, 0.16, steel, 8)
		_limb(b, base + dir * 1.28, base + dir * 1.52, 0.30, 0.30, steel, 8)
		_limb(b, base - dir * 0.30, base, 0.07, 0.07, steel, 6)

# ================================================================= AI / animation
func _process(delta: float) -> void:
	_t += delta
	if game == null:
		return
	var hero: Vector3 = game.hero_pos if "hero_pos" in game else Vector3.ZERO
	_tick_donut(delta, hero)
	_tick_spiders(delta, hero)
	_tick_boss(delta, hero)

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
			head.global_position = gp.global_position
			head.global_rotation = Vector3(0, donut.global_rotation.y, 0)

func _tick_spiders(delta: float, hero: Vector3) -> void:
	for s in spiders:
		var n: Node3D = s["node"]
		var to := hero - n.position
		to.y = 0
		var d := to.length()
		var moving := d > float(s["stop"])
		if moving:
			var dir := to.normalized()
			# skittering: never a straight line
			var strafe := Vector3(-dir.z, 0, dir.x) * sin(_t * 2.2 + float(s["phase"])) * 0.45
			n.position += (dir + strafe).normalized() * float(s["speed"]) * delta
		n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), 0.12)
		var body: Node3D = n.get_meta("body")
		body.position.y = 0.78 + sin(_t * 5.0 + float(s["phase"])) * 0.035
		var rate: float = 7.0 if moving else 2.2
		var amp: float = 0.40 if moving else 0.12
		for leg in s["legs"]:
			var up: Node3D = leg["up"]
			var ph: float = float(s["phase"]) + float(leg["i"]) * 1.6 + (0.0 if leg["side"] > 0.0 else PI)
			up.rotation = Vector3(0, 0, sin(_t * rate + ph) * amp * leg["side"] * -1.0)
			up.position.y = maxf(0.0, sin(_t * rate + ph)) * amp * 0.22

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
			if d > 5.2:
				_boss_pos += to.normalized() * 1.15 * delta
			_boss_cd -= delta
			if _boss_cd <= 0.0 and d < 12.0:
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
