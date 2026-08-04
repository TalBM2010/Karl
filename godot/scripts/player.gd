extends Node3D
class_name KarlPlayer
## CARL — the hero. A real rigged glTF humanoid driven by Godot's AnimationPlayer.
##
## Godot imports .glb with its skeleton and animation clips natively, so locomotion is real
## skeletal animation (idle / walk / run) rather than hand-rotated primitives.
##
## Identity (must always read): bare-chested muscular barbarian, WHITE BOXERS WITH RED HEARTS,
## barefoot, dark hair + beard, carrying a GLOWING CYAN double-bit energy axe in his right hand.
##
## Contract used by game.gd:
##   set_state("idle"|"move"|"attack") ; attack() ; height (float)

const TARGET_HEIGHT := 2.4
const CHOP_TIME := 0.42

var anim: AnimationPlayer
var skel: Skeleton3D
var model: Node3D
var _state := "idle"
var _chop := 0.0
var _right_arm_idx := -1
var axe: Node3D

func build() -> void:
	var packed: PackedScene = load("res://assets/Xbot.glb")
	if packed == null:
		push_error("Carl: Xbot.glb failed to load")
		return
	model = packed.instantiate()
	add_child(model)

	# scale the imported rig to our hero height
	var aabb := _model_aabb(model)
	if aabb.size.y > 0.01:
		var s := TARGET_HEIGHT / aabb.size.y
		model.scale = Vector3(s, s, s)

	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skin_and_dress()
	if skel:
		_right_arm_idx = skel.find_bone("mixamorig_RightArm")
		if _right_arm_idx < 0:
			_right_arm_idx = skel.find_bone("mixamorigRightArm")
		_attach_axe()
	set_state("idle")

func _model_aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a := mi.get_aabb()
		a.position += mi.global_position - global_position if mi.is_inside_tree() else Vector3.ZERO
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box

## Warm bare skin + heart-print boxers so the mannequin reads as Carl.
func _skin_and_dress() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.84, 0.56, 0.33)
	skin.roughness = 0.62
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = skin

	if skel == null:
		return
	var hips := skel.find_bone("mixamorig_Hips")
	if hips < 0:
		hips = skel.find_bone("mixamorigHips")
	if hips < 0:
		return

	var att := BoneAttachment3D.new()
	att.bone_idx = hips
	skel.add_child(att)

	var shorts_mat := StandardMaterial3D.new()
	shorts_mat.albedo_color = Color(0.93, 0.91, 0.86)
	shorts_mat.roughness = 0.85
	var shorts := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.30
	cyl.bottom_radius = 0.33
	cyl.height = 0.42
	shorts.mesh = cyl
	shorts.material_override = shorts_mat
	shorts.position = Vector3(0, -0.02, 0)
	att.add_child(shorts)

	var heart_mat := StandardMaterial3D.new()
	heart_mat.albedo_color = Color(1.0, 0.20, 0.35)
	heart_mat.emission_enabled = true
	heart_mat.emission = Color(0.9, 0.12, 0.28)
	heart_mat.emission_energy_multiplier = 1.4
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 10:
		var h := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.045
		sp.height = 0.07
		h.mesh = sp
		h.material_override = heart_mat
		var a := rng.randf() * TAU
		h.position = Vector3(cos(a) * 0.32, rng.randf_range(-0.16, 0.14), sin(a) * 0.32)
		att.add_child(h)

## Glowing cyan double-bit energy axe, parented to the right hand bone.
func _attach_axe() -> void:
	var hand := skel.find_bone("mixamorig_RightHand")
	if hand < 0:
		hand = skel.find_bone("mixamorigRightHand")
	if hand < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = hand
	skel.add_child(att)

	axe = Node3D.new()
	att.add_child(axe)

	var haft_mat := StandardMaterial3D.new()
	haft_mat.albedo_color = Color(0.16, 0.11, 0.07)
	haft_mat.roughness = 0.9
	var haft := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.045
	hm.bottom_radius = 0.05
	hm.height = 1.8
	haft.mesh = hm
	haft.material_override = haft_mat
	axe.add_child(haft)

	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.42, 0.78, 1.0)
	blade_mat.metallic = 0.35
	blade_mat.roughness = 0.15
	blade_mat.emission_enabled = true
	blade_mat.emission = Color(0.25, 0.66, 1.0)
	blade_mat.emission_energy_multiplier = 3.2
	for s in [-1.0, 1.0]:
		var bit := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.52, 0.62, 0.14)
		bit.mesh = pm
		bit.material_override = blade_mat
		bit.position = Vector3(0.20 * s, 0.82, 0)
		bit.rotation_degrees = Vector3(0, 0, 90 * s)
		axe.add_child(bit)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.35, 0.72, 1.0)
	glow.light_energy = 2.4
	glow.omni_range = 6.0
	glow.position = Vector3(0, 0.85, 0)
	axe.add_child(glow)

	axe.position = Vector3(0, 0.06, 0)
	axe.rotation_degrees = Vector3(0, 0, 105)

# ---------------------------------------------------------------- animation state
func set_state(s: String) -> void:
	if s == _state or anim == null:
		return
	_state = s
	var want := "idle"
	if s == "move":
		want = "run"
	var clip := _find_clip(want)
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
	_chop = CHOP_TIME

func _process(delta: float) -> void:
	if _chop > 0.0:
		_chop = max(0.0, _chop - delta)
		if skel and _right_arm_idx >= 0:
			# additive overhead chop layered over locomotion
			var k := 1.0 - (_chop / CHOP_TIME)
			var swing := -2.1 + 2.9 * (k * k)
			var pose := skel.get_bone_pose_rotation(_right_arm_idx)
			skel.set_bone_pose_rotation(_right_arm_idx, pose * Quaternion(Vector3.RIGHT, swing))
