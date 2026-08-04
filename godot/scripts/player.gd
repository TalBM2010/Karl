extends Node3D
class_name KarlPlayer
## CARL — the hero of Dungeon Crawler Carl.
##
## A rigged Mixamo humanoid (Xbot.glb) driven by Godot's AnimationPlayer, wearing a hand-built
## MUSCLE SUIT: ~50 sculpted volumes parented to BoneAttachment3D nodes so every belly, delt and
## quad deforms with the skeletal animation. Lit muscle bellies + darker crevice slivers between
## them is what makes a smooth mannequin read as CUT.
##
## Identity (must always read at gameplay distance):
##   big bare-chested BEARDED barbarian, BAREFOOT, WHITE BOXERS WITH RED HEARTS,
##   swinging a GLOWING CYAN double-bit energy axe.
##
## Everything is authored in SKELETON REST SPACE (i.e. "sculpting on the T-pose") and then
## converted into bone-local space, so no code anywhere has to guess a Mixamo bone's axis
## convention — see _bulk()/_ell(). All sizes are multiples of `_u`, the shoulder-joint span,
## so the build is resolution-independent of however the .glb happens to be scaled.
##
## Contract used by game.gd:  build() ; set_state("idle"|"move"|"attack") ; attack()

const TARGET_HEIGHT := 2.4
const BROADEN := Vector3(1.10, 1.0, 1.06)   # heavyweight: wider than the stock mannequin
const CHOP_TIME := 0.86
const WINDUP := 0.24                        # fraction of the chop spent winding up
const RECOVER := 0.34                       # trailing fraction spent easing back to carry

var anim: AnimationPlayer
var skel: Skeleton3D
var model: Node3D
var axe: Node3D
var _hand_att: BoneAttachment3D
var _axe_carry := Basis.IDENTITY

var _state := "idle"
var _chop := -1.0
var _bones := {}
var _grest := {}
var _atts := {}

# character-space axes + unit, measured off the rest pose
var _up := Vector3.UP
var _right := Vector3.RIGHT
var _fwd := Vector3.BACK
var _u := 0.5

var m_skin: StandardMaterial3D
var m_crease: StandardMaterial3D
var m_hair: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_glint: StandardMaterial3D
var m_cloth: StandardMaterial3D
var m_metal: StandardMaterial3D
var m_energy: StandardMaterial3D

# ---------------------------------------------------------------- build
func build() -> void:
	process_priority = 20        # run AFTER the AnimationPlayer so pose overrides stick
	var packed: PackedScene = load("res://assets/Xbot.glb")
	if packed == null:
		push_error("Carl: Xbot.glb failed to load")
		return
	model = packed.instantiate()
	add_child(model)

	var aabb := _model_aabb(model)
	var s := 1.0
	if aabb.size.y > 0.01:
		s = TARGET_HEIGHT / aabb.size.y
	model.scale = BROADEN * s

	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D

	_materials()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = m_skin
	if skel:
		_measure()
		_torso()
		_arms()
		_legs()
		_head()
		_boxers()
		_build_axe()
	else:
		push_error("Carl: no Skeleton3D in Xbot.glb")
	set_state("idle")

func _model_aabb(n: Node) -> AABB:
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

# ---------------------------------------------------------------- rest-space measuring
func _bi(n: String) -> int:
	if _bones.has(n):
		return _bones[n]
	var i := skel.find_bone("mixamorig_" + n)
	if i < 0:
		i = skel.find_bone("mixamorig" + n)
	if i < 0:
		i = skel.find_bone(n)
	_bones[n] = i
	return i

## Rest transform of a bone in SKELETON space (walks the parent chain — no engine version risk).
func _gr(i: int) -> Transform3D:
	if i < 0:
		return Transform3D()
	if _grest.has(i):
		return _grest[i]
	var t: Transform3D = skel.get_bone_rest(i)
	var p := skel.get_bone_parent(i)
	if p >= 0:
		t = _gr(p) * t
	_grest[i] = t
	return t

func _pt(n: String) -> Vector3:
	return _gr(_bi(n)).origin

func _measure() -> void:
	var hips := _pt("Hips")
	var neck := _pt("Neck")
	_up = (neck - hips).normalized()
	var r := _pt("RightArm") - _pt("LeftArm")
	_u = max(0.05, r.length())
	_right = (r - _up * r.dot(_up)).normalized()
	_fwd = _up.cross(_right).normalized()
	# disambiguate front/back with the eye bones
	var el := _bi("LeftEye")
	var er := _bi("RightEye")
	if el >= 0 and er >= 0:
		var eye_mid := (_gr(el).origin + _gr(er).origin) * 0.5
		if (eye_mid - _pt("Head")).dot(_fwd) < 0.0:
			_fwd = -_fwd

func _attach(bone: String) -> BoneAttachment3D:
	var idx := _bi(bone)
	if idx < 0:
		idx = 0
	if _atts.has(idx):
		return _atts[idx]
	var a := BoneAttachment3D.new()
	a.name = "att_" + bone
	skel.add_child(a)
	a.bone_name = skel.get_bone_name(idx)
	a.bone_idx = idx
	_atts[idx] = a
	return a

## Place a mesh authored in skeleton-rest space onto a bone.
func _place(bone: String, mi: MeshInstance3D, basis: Basis, origin: Vector3) -> MeshInstance3D:
	var att := _attach(bone)
	mi.transform = _gr(_bi(bone)).affine_inverse() * Transform3D(basis, origin)
	att.add_child(mi)
	return mi

func _sphere_mesh(segs: int, rings: int) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = rings
	return sm

## Axis-aligned muscle mass: radii along (right, up, forward), in units of `_u` (or `unit`).
func _bulk(bone: String, c: Vector3, rx: float, ry: float, rz: float, mat: Material,
		segs: int = 12, rings: int = 6, unit: float = 0.0) -> MeshInstance3D:
	var k := unit if unit > 0.0 else _u
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(segs, rings)
	mi.material_override = mat
	return _place(bone, mi, Basis(_right * rx * k, _up * ry * k, _fwd * rz * k), c)

## Muscle belly spanning two rest-space points (a limb muscle), with side/front radii in `_u`.
func _ell(bone: String, a: Vector3, b: Vector3, rs: float, rf: float, mat: Material,
		segs: int = 12, rings: int = 6) -> MeshInstance3D:
	var half := (b - a) * 0.5
	var yd := half.normalized()
	var ref := _right if absf(yd.dot(_right)) < 0.88 else _up
	var zd := yd.cross(ref).normalized()
	var xd := zd.cross(yd).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(segs, rings)
	mi.material_override = mat
	return _place(bone, mi, Basis(xd * rs * _u, half, zd * rf * _u), (a + b) * 0.5)

## Thin dark sliver used as a crevice between muscle bellies — this is what sells "cut".
func _crease(bone: String, c: Vector3, rx: float, ry: float, rz: float, unit: float = 0.0) -> MeshInstance3D:
	return _bulk(bone, c, rx, ry, rz, m_crease, 8, 4, unit)

# ---------------------------------------------------------------- materials
func _materials() -> void:
	m_skin = StandardMaterial3D.new()
	m_skin.albedo_color = Color(0.79, 0.50, 0.31)
	m_skin.roughness = 0.46
	m_skin.metallic_specular = 0.55
	m_skin.rim_enabled = true          # sweaty fresnel — separates each muscle belly
	m_skin.rim = 0.75
	m_skin.rim_tint = 0.35

	m_crease = StandardMaterial3D.new()
	m_crease.albedo_color = Color(0.30, 0.155, 0.095)
	m_crease.roughness = 0.72

	m_hair = StandardMaterial3D.new()
	m_hair.albedo_color = Color(0.075, 0.052, 0.042)
	m_hair.roughness = 0.82
	m_hair.rim_enabled = true
	m_hair.rim = 0.5

	m_eye = StandardMaterial3D.new()
	m_eye.albedo_color = Color(0.06, 0.05, 0.05)
	m_eye.roughness = 0.25

	m_glint = StandardMaterial3D.new()
	m_glint.albedo_color = Color(0.95, 0.97, 1.0)
	m_glint.emission_enabled = true
	m_glint.emission = Color(0.8, 0.9, 1.0)
	m_glint.emission_energy_multiplier = 0.8

	m_cloth = StandardMaterial3D.new()
	m_cloth.albedo_color = Color(0.90, 0.89, 0.86)
	m_cloth.roughness = 0.82
	var tex := _heart_textures()
	m_cloth.albedo_texture = tex[0]
	m_cloth.emission_enabled = true
	m_cloth.emission_texture = tex[1]
	m_cloth.emission = Color(1, 1, 1)
	m_cloth.emission_energy_multiplier = 0.45
	m_cloth.uv1_scale = Vector3(4, 2, 1)

	m_metal = StandardMaterial3D.new()
	m_metal.albedo_color = Color(0.13, 0.135, 0.15)
	m_metal.metallic = 0.85
	m_metal.roughness = 0.38

	m_energy = StandardMaterial3D.new()
	m_energy.albedo_color = Color(0.05, 0.28, 0.48)
	m_energy.metallic = 0.55
	m_energy.roughness = 0.16
	m_energy.emission_enabled = true
	m_energy.emission = Color(0.02, 0.55, 1.0)
	m_energy.emission_energy_multiplier = 0.85
	m_energy.rim_enabled = true
	m_energy.rim = 1.0

## Procedural white cloth with a red heart print. Returns [albedo, emission_mask].
func _heart_textures() -> Array:
	var n := 64
	var alb := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var white := Color(0.97, 0.96, 0.94)
	var red := Color(0.40, 0.022, 0.06)
	for y in n:
		for x in n:
			# implicit heart curve, centred in the tile
			var px := (float(x) / n - 0.5) * 2.85
			var py := (0.56 - float(y) / n) * 2.85
			var q := px * px + py * py - 1.0
			var inside := q * q * q - px * px * py * py * py <= 0.0
			alb.set_pixel(x, y, red if inside else white)
			emi.set_pixel(x, y, Color(0.75, 0.04, 0.10) if inside else Color(0, 0, 0))
	alb.generate_mipmaps()
	emi.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]

# ---------------------------------------------------------------- torso
func _torso() -> void:
	var sp := _pt("Spine")
	var sp1 := _pt("Spine1")
	var sp2 := _pt("Spine2")
	var neck := _pt("Neck")
	var chest := sp2.lerp(neck, 0.22)

	# pectorals — two broad slabs standing well proud of the base mesh, deep cleft between
	for sgn in [-1.0, 1.0]:
		_bulk("Spine2", chest + _right * (0.31 * sgn * _u) + _fwd * (0.13 * _u) - _up * (0.05 * _u),
			0.36, 0.21, 0.22, m_skin, 14, 8)
		# under-pec shadow line
		_crease("Spine2", chest + _right * (0.29 * sgn * _u) + _fwd * (0.23 * _u) - _up * (0.24 * _u),
			0.28, 0.035, 0.085)
	_crease("Spine2", chest + _fwd * (0.24 * _u) - _up * (0.05 * _u), 0.040, 0.19, 0.10)

	# clavicle shelf
	_bulk("Spine2", neck.lerp(chest, 0.55) + _fwd * (0.05 * _u), 0.50, 0.12, 0.19, m_skin, 12, 5)

	# trapezius — neck-to-shoulder slope, the classic heavyweight cue
	for sgn in [-1.0, 1.0]:
		_bulk("Spine2", neck.lerp(_pt("RightArm" if sgn > 0.0 else "LeftArm"), 0.44) + _up * (0.07 * _u) - _fwd * (0.02 * _u),
			0.40, 0.21, 0.26, m_skin, 12, 6)

	# latissimus — flares wide and high, then tapers to the waist: the V
	for sgn in [-1.0, 1.0]:
		_bulk("Spine2", sp1.lerp(sp2, 0.80) + _right * (0.38 * sgn * _u) - _fwd * (0.02 * _u),
			0.25, 0.38, 0.27, m_skin, 12, 6)
		_bulk("Spine1", sp.lerp(sp1, 0.65) + _right * (0.28 * sgn * _u) - _fwd * (0.01 * _u),
			0.18, 0.26, 0.22, m_skin, 12, 6)
	# spinal erector groove
	_crease("Spine1", sp.lerp(sp2, 0.5) - _fwd * (0.19 * _u), 0.05, 0.44, 0.07)

	# abdominals — 3 rows of pairs, with crevices between
	var abs_top := sp1.lerp(sp2, 0.10)
	var abs_bot := sp.lerp(sp1, 0.0) - _up * (0.12 * _u)
	for row in 3:
		var t := float(row) / 2.0
		var c := abs_top.lerp(abs_bot, t)
		var w := 0.145 - 0.014 * row
		for sgn in [-1.0, 1.0]:
			_bulk("Spine1", c + _right * (0.10 * sgn * _u) + _fwd * (0.20 * _u), w, 0.10, 0.13, m_skin, 10, 6)
		if row < 2:
			var c2 := abs_top.lerp(abs_bot, t + 0.25)
			_crease("Spine1", c2 + _fwd * (0.26 * _u), 0.24, 0.022, 0.05)
	_crease("Spine1", abs_top.lerp(abs_bot, 0.5) + _fwd * (0.27 * _u), 0.020, 0.26, 0.05)
	# serratus / obliques
	for sgn in [-1.0, 1.0]:
		_bulk("Spine", abs_bot + _right * (0.22 * sgn * _u) + _fwd * (0.05 * _u) + _up * (0.07 * _u),
			0.11, 0.18, 0.16, m_skin, 10, 5)

# ---------------------------------------------------------------- arms
func _arms() -> void:
	for side in ["Left", "Right"]:
		var sgn := -1.0 if side == "Left" else 1.0
		var sh := _pt(side + "Arm")
		var el := _pt(side + "ForeArm")
		var hd := _pt(side + "Hand")

		# deltoid — pushed outboard: this is what buys the broad-shouldered silhouette
		_bulk(side + "Arm", sh + _right * (0.13 * sgn * _u) + _up * (0.03 * _u), 0.33, 0.31, 0.31, m_skin, 14, 8)
		_bulk(side + "Arm", sh + _right * (0.10 * sgn * _u) - _fwd * (0.15 * _u), 0.23, 0.23, 0.18, m_skin, 10, 5)
		_crease(side + "Arm", sh + _right * (0.36 * sgn * _u), 0.05, 0.22, 0.19)

		# biceps peak + triceps horseshoe
		_ell(side + "Arm", sh.lerp(el, 0.16), sh.lerp(el, 0.72), 0.225, 0.225, m_skin, 12, 7)
		_ell(side + "Arm", sh.lerp(el, 0.22) - _fwd * (0.13 * _u), sh.lerp(el, 0.88) - _fwd * (0.09 * _u),
			0.175, 0.15, m_skin, 10, 6)

		# forearm — thick at the elbow, tapering to the wrist
		_ell(side + "ForeArm", el.lerp(hd, 0.00), el.lerp(hd, 0.48), 0.19, 0.19, m_skin, 12, 6)
		_ell(side + "ForeArm", el.lerp(hd, 0.42), el.lerp(hd, 0.95), 0.125, 0.125, m_skin, 10, 5)

# ---------------------------------------------------------------- legs
func _legs() -> void:
	for side in ["Left", "Right"]:
		var sgn := -1.0 if side == "Left" else 1.0
		var hip := _pt(side + "UpLeg")
		var kn := _pt(side + "Leg")
		var ft := _pt(side + "Foot")

		# glute + quad sweep
		_bulk("Hips", hip + _up * (0.02 * _u) - _fwd * (0.15 * _u) + _right * (0.05 * sgn * _u),
			0.24, 0.22, 0.20, m_skin, 12, 6)
		_ell(side + "UpLeg", hip.lerp(kn, 0.08), hip.lerp(kn, 0.74), 0.275, 0.265, m_skin, 12, 7)
		_ell(side + "UpLeg", hip.lerp(kn, 0.40) + _fwd * (0.13 * _u), hip.lerp(kn, 0.94) + _fwd * (0.08 * _u),
			0.15, 0.10, m_skin, 10, 5)      # rectus femoris ridge
		_crease(side + "UpLeg", hip.lerp(kn, 0.62) + _fwd * (0.20 * _u), 0.025, 0.22, 0.05)

		# calf
		_ell(side + "Leg", kn.lerp(ft, 0.06), kn.lerp(ft, 0.54), 0.20, 0.20, m_skin, 12, 6)
		_ell(side + "Leg", kn.lerp(ft, 0.48), kn.lerp(ft, 0.95), 0.10, 0.10, m_skin, 10, 5)

# ---------------------------------------------------------------- head
func _head() -> void:
	var head := _pt("Head")
	var top := _pt("HeadTop_End")
	var hh := (top - head).length()
	var hr := maxf(hh * 0.70, 0.04 * _u)
	var hc := head.lerp(top, 0.48)
	var eye_mid := hc + _fwd * (0.80 * hr) + _up * (0.10 * hr)
	var el := _bi("LeftEye")
	var er := _bi("RightEye")
	if el >= 0 and er >= 0:
		eye_mid = (_gr(el).origin + _gr(er).origin) * 0.5

	# thick neck / traps continuation
	_bulk("Neck", head.lerp(_pt("Neck"), 0.55), 0.20, 0.17, 0.19, m_skin, 12, 6)

	# From here on every radius is in units of `hr` (the skull radius), not `_u`.
	# --- hair: swept-back dark mass on the crown and down the back of the skull
	_bulk("Head", hc + _up * (0.60 * hr) - _fwd * (0.10 * hr), 1.02, 0.62, 1.04, m_hair, 14, 8, hr)
	_bulk("Head", hc + _up * (0.10 * hr) - _fwd * (0.60 * hr), 0.90, 0.90, 0.62, m_hair, 12, 7, hr)

	# --- heavy brow ridge, deep-set eyes
	_bulk("Head", eye_mid + _up * (0.26 * hr) + _fwd * (0.30 * hr), 0.50, 0.10, 0.20, m_skin, 12, 5, hr)
	_crease("Head", eye_mid + _up * (0.13 * hr) + _fwd * (0.42 * hr), 0.44, 0.045, 0.09, hr)
	for sgn in [-1.0, 1.0]:
		_bulk("Head", eye_mid + _right * (0.26 * hr * sgn) + _fwd * (0.36 * hr), 0.12, 0.09, 0.08, m_eye, 8, 5, hr)
		_bulk("Head", eye_mid + _right * (0.26 * hr * sgn) + _fwd * (0.42 * hr) + _up * (0.02 * hr),
			0.04, 0.04, 0.04, m_glint, 6, 4, hr)
	# nose
	_bulk("Head", eye_mid - _up * (0.16 * hr) + _fwd * (0.44 * hr), 0.12, 0.17, 0.16, m_skin, 10, 5, hr)

	# --- FULL DARK BEARD: it must frame the face, never swallow it, so every mass is
	# anchored BELOW the nose and pushed out to the jaw line.
	_bulk("Head", eye_mid - _up * (0.72 * hr) + _fwd * (0.10 * hr), 0.50, 0.34, 0.46, m_hair, 14, 8, hr)
	_bulk("Head", eye_mid - _up * (1.02 * hr) + _fwd * (0.06 * hr), 0.34, 0.26, 0.36, m_hair, 12, 6, hr)
	for sgn in [-1.0, 1.0]:
		_bulk("Head", eye_mid + _right * (0.44 * hr * sgn) - _up * (0.48 * hr) - _fwd * (0.04 * hr),
			0.22, 0.34, 0.40, m_hair, 10, 6, hr)
	# moustache, tucked under the nose
	_bulk("Head", eye_mid - _up * (0.33 * hr) + _fwd * (0.40 * hr), 0.22, 0.075, 0.12, m_hair, 10, 5, hr)
	# sideburns tying beard to hair
	for sgn in [-1.0, 1.0]:
		_bulk("Head", eye_mid + _right * (0.50 * hr * sgn) + _up * (0.06 * hr) - _fwd * (0.20 * hr),
			0.16, 0.34, 0.30, m_hair, 8, 5, hr)

# ---------------------------------------------------------------- boxer shorts
func _boxers() -> void:
	var hips := _pt("Hips")
	var lu := _pt("LeftUpLeg")
	var ru := _pt("RightUpLeg")
	var hipw := (ru - lu).length()
	var kn := _pt("LeftLeg")
	var thigh := (kn - lu).length()

	# --- trunk of the shorts: waistband down to the crotch
	var body := CylinderMesh.new()
	body.top_radius = hipw * 0.62
	body.bottom_radius = hipw * 0.82
	body.height = hipw * 1.10
	body.radial_segments = 18
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.material_override = m_cloth
	var c := hips - _up * (hipw * 0.06)
	_place("Hips", mi, Basis(_right, _up, _fwd), c)

	# elastic waistband (plain, so the hem reads)
	var band := CylinderMesh.new()
	band.top_radius = hipw * 0.655
	band.bottom_radius = hipw * 0.645
	band.height = hipw * 0.18
	band.radial_segments = 18
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.88, 0.87, 0.86)
	bm.roughness = 0.85
	var bi := MeshInstance3D.new()
	bi.mesh = band
	bi.material_override = bm
	_place("Hips", bi, Basis(_right, _up, _fwd), c + _up * (hipw * 0.53))

	# --- leg openings: a loose tube down each thigh, so it reads as SHORTS not a skirt
	for side in ["Left", "Right"]:
		var a := _pt(side + "UpLeg")
		var b := _pt(side + "Leg")
		var d := (b - a).normalized()
		var leg := CylinderMesh.new()
		leg.top_radius = hipw * 0.58
		leg.bottom_radius = hipw * 0.54
		leg.height = thigh * 0.50
		leg.radial_segments = 16
		leg.cap_top = false
		leg.cap_bottom = false
		var lm := MeshInstance3D.new()
		lm.mesh = leg
		lm.material_override = m_cloth
		var ref := _right if absf(d.dot(_right)) < 0.88 else _fwd
		var zd := d.cross(ref).normalized()
		var xd := zd.cross(d).normalized()
		_place(side + "UpLeg", lm, Basis(xd, d, zd), a.lerp(b, 0.30))

		# hem ring at the leg opening
		var hem := TorusMesh.new()
		hem.inner_radius = hipw * 0.53
		hem.outer_radius = hipw * 0.585
		hem.rings = 16
		hem.ring_segments = 6
		var hi := MeshInstance3D.new()
		hi.mesh = hem
		hi.material_override = bm
		_place(side + "UpLeg", hi, Basis(xd, d, zd), a.lerp(b, 0.30) + d * (thigh * 0.25))

# ---------------------------------------------------------------- the energy axe
## The axe is NOT parented to the hand bone. A Mixamo hand tumbles through a run cycle and the
## axe tumbled with it (head pointing at the ground, blade across the face). Instead it lives in
## CHARACTER space: it tracks the fist's position every frame but keeps an authored carry
## orientation, and the chop drives the swing arc explicitly. Full art control, still hand-locked.
const AXE_LEN := 1.35          # metres — Carl is TARGET_HEIGHT tall
const AXE_HEAD_Y := 0.62       # head height above the fist, along the haft
const AXE_CARRY_TIP := 22.0    # degrees the haft leans forward when carried
const AXE_CARRY_OUT := 15.0    # degrees it leans away from the body

func _build_axe() -> void:
	if _bi("RightHand") < 0:
		return
	_hand_att = _attach("RightHand")
	axe = Node3D.new()
	axe.name = "Axe"
	add_child(axe)
	_axe_carry = Basis(Vector3.RIGHT, deg_to_rad(AXE_CARRY_TIP)) \
		* Basis(Vector3.BACK, deg_to_rad(AXE_CARRY_OUT)) \
		* Basis(Vector3.UP, deg_to_rad(90.0))     # bits face fore/aft, ready to chop

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.10, 0.078, 0.062)
	wood.roughness = 0.92

	var haft := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.030
	hm.bottom_radius = 0.040
	hm.height = AXE_LEN
	hm.radial_segments = 10
	haft.mesh = hm
	haft.material_override = wood
	haft.position = Vector3(0, AXE_LEN * 0.5 - 0.42, 0)
	axe.add_child(haft)

	# pommel, grip collar and the head socket
	for spec in [[-0.40, 0.062, 0.075], [0.02, 0.055, 0.16], [AXE_HEAD_Y - 0.16, 0.058, 0.075]]:
		var col := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = spec[1]
		cm.bottom_radius = spec[1]
		cm.height = spec[2]
		cm.radial_segments = 10
		col.mesh = cm
		col.material_override = m_metal
		col.position = Vector3(0, spec[0], 0)
		axe.add_child(col)

	var boss := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.062
	bm.bottom_radius = 0.062
	bm.height = 0.34
	bm.radial_segments = 10
	boss.mesh = bm
	boss.material_override = m_metal
	boss.position = Vector3(0, AXE_HEAD_Y, 0)
	axe.add_child(boss)

	# Two mirrored crescent bits — narrow neck at the haft flaring to a broad cutting edge.
	# x = outward from the haft, y = along the haft.
	var poly := PackedVector2Array([
		Vector2(0.10, 0.20), Vector2(0.34, 0.34), Vector2(0.64, 0.54),
		Vector2(0.90, 0.72), Vector2(1.06, 0.44), Vector2(1.12, 0.06),
		Vector2(1.08, -0.32), Vector2(0.92, -0.66), Vector2(0.64, -0.50),
		Vector2(0.34, -0.32), Vector2(0.10, -0.19),
	])
	var blade_mesh := _blade_mesh(poly, 0.16, 0.62)
	for sgn in [1.0, -1.0]:
		var bit := MeshInstance3D.new()
		bit.mesh = blade_mesh
		bit.material_override = m_energy
		bit.scale = Vector3(0.36 * sgn, 0.36, 0.36)
		bit.position = Vector3(0, AXE_HEAD_Y, 0)
		axe.add_child(bit)

	# The glow sits below the head — inside the blade it would blow the whole thing to white.
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.24, 0.68, 1.0)
	glow.light_energy = 1.4
	glow.omni_range = 2.6
	glow.shadow_enabled = false
	glow.position = Vector3(0, AXE_HEAD_Y - 0.30, 0)
	axe.add_child(glow)

## Keep the axe in the fist while holding the authored orientation (+ the chop arc).
func _track_axe(chop_angle: float) -> void:
	if axe == null or _hand_att == null:
		return
	var grip := to_local(_hand_att.global_position)
	var b := _axe_carry
	if chop_angle != 0.0:
		b = Basis(Vector3.RIGHT, chop_angle) * b
	axe.transform = Transform3D(b, grip)

## Extrude a 2D outline into a lens-section blade (sharp rim, thick spine) with flat normals.
func _blade_mesh(poly: PackedVector2Array, half_thick: float, inner: float) -> ArrayMesh:
	var n := poly.size()
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= float(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []
	var inn: Array[Vector3] = []
	var out: Array[Vector3] = []
	for p in poly:
		var q := cen + (p - cen) * inner
		rim.append(Vector3(p.x, p.y, 0.0))
		inn.append(Vector3(q.x, q.y, half_thick))
		out.append(Vector3(q.x, q.y, -half_thick))
	var c_in := Vector3(cen.x, cen.y, half_thick)
	var c_out := Vector3(cen.x, cen.y, -half_thick)
	for i in n:
		var j := (i + 1) % n
		_tri(st, rim[i], inn[i], inn[j])
		_tri(st, rim[i], inn[j], rim[j])
		_tri(st, rim[j], out[j], out[i])
		_tri(st, rim[j], out[i], rim[i])
		_tri(st, inn[i], c_in, inn[j])
		_tri(st, out[j], c_out, out[i])
	st.index()
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	st.set_normal(nrm)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.add_vertex(b)
	st.set_normal(nrm)
	st.add_vertex(c)

# ---------------------------------------------------------------- animation state
func set_state(s: String) -> void:
	if s == _state or anim == null:
		return
	_state = s
	var clip := _find_clip("run" if s == "move" else "idle")
	if clip != "":
		anim.play(clip, 0.18)

func _find_clip(want: String) -> String:
	if anim == null:
		return ""
	for a in anim.get_animation_list():
		if a.to_lower().findn(want) >= 0:
			return a
	var list := anim.get_animation_list()
	return list[0] if list.size() > 0 else ""

func attack() -> void:
	_chop = 0.0

## Overhead chop layered additively on top of whatever locomotion clip is playing, plus the
## axe arc. Runs at process_priority 20, i.e. after the AnimationPlayer has written the pose.
func _process(delta: float) -> void:
	if skel == null:
		return
	if _chop < 0.0:
		_track_axe(0.0)
		return
	_chop += delta
	if _chop > CHOP_TIME:
		_chop = -1.0
		_track_axe(0.0)
		return
	var t := _chop / CHOP_TIME
	var swing := 0.0        # arm: negative = cocked back and up
	var lean := 0.0
	var arc := 0.0          # axe: negative = reared back, positive = driven down and forward
	if t < WINDUP:
		var k := t / WINDUP
		var sm := k * k * (3.0 - 2.0 * k)
		swing = -2.35 * sm
		lean = 0.20 * k
		arc = -0.85 * sm
	elif t < 1.0 - RECOVER:
		var k := (t - WINDUP) / (1.0 - RECOVER - WINDUP)
		var e := 1.0 - pow(1.0 - k, 3.0)          # fast strike, easing into follow-through
		swing = lerpf(-2.35, 1.05, e)
		lean = lerpf(0.20, -0.26, e)
		arc = lerpf(-0.85, 1.95, e)
	else:
		var k := (t - (1.0 - RECOVER)) / RECOVER
		var e := k * k * (3.0 - 2.0 * k)
		swing = lerpf(1.05, 0.0, e)
		lean = lerpf(-0.26, 0.0, e)
		arc = lerpf(1.95, 0.0, e)
	_bend("RightArm", Vector3.RIGHT, swing)
	_bend("RightForeArm", Vector3.RIGHT, swing * 0.35)
	_bend("RightShoulder", Vector3.RIGHT, swing * 0.20)
	_bend("Spine2", Vector3.RIGHT, lean)
	_bend("Spine1", Vector3.RIGHT, lean * 0.6)
	_track_axe(arc)

func _bend(bone: String, axis: Vector3, ang: float) -> void:
	var i := _bi(bone)
	if i < 0:
		return
	skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i) * Quaternion(axis, ang))
