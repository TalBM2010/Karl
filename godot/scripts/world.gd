extends Node3D
class_name KarlWorld
## WORLD & LOOK — the Crystal Depths cavern, built procedurally.
##
## Owns: WorldEnvironment (the Forward+ grade — tonemap/glow/SSAO/SSIL/volumetric fog),
## lighting, the ground material, and the crystal formations that light the scene.
##
## Target (reference frames A/B): a DARK, moody, high-contrast underground cavern with deep
## blacks, saturated blue/violet crystal glow, and real atmospheric depth receding into fog.
## Mood first — the fancy renderer features must serve darkness, not wash it out.

const GROUND_SIZE := 240.0

var crystals: Array[Node3D] = []
var env: Environment
var fog_color := Color(0.045, 0.10, 0.145)

func build() -> void:
	_build_environment()
	_build_lights()
	_build_ground()
	_build_crystals()
	_build_boulders()

# ---------------------------------------------------------------- environment / grade
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = fog_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.30, 0.40)
	env.ambient_light_energy = 0.35          # low: lights + emissives own the mood

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0

	# glow: only genuinely bright things (crystals, VFX) bloom — not the whole frame
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# contact shadows / indirect darkening — this is what primitives could never fake
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6

	# depth fog: sightlines receding into atmosphere
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_light_energy = 0.7
	env.fog_density = 0.018
	env.fog_sky_affect = 1.0

	# god-ray haze through the crystal light
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.35, 0.62, 0.80)
	env.volumetric_fog_emission = Color(0.02, 0.06, 0.09)
	env.volumetric_fog_length = 90.0

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.18
	env.adjustment_brightness = 0.98

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.light_color = Color(0.78, 0.88, 1.0)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 90.0
	key.rotation_degrees = Vector3(-52, 38, 0)
	add_child(key)

	var rim := DirectionalLight3D.new()   # warm separation on the hero
	rim.light_color = Color(1.0, 0.66, 0.42)
	rim.light_energy = 0.35
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-18, -140, 0)
	add_child(rim)

# ---------------------------------------------------------------- ground
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.115, 0.155, 0.185)
	mat.roughness = 0.92
	mat.metallic = 0.05

	# procedural stone relief (native Godot noise -> real normal map under SSAO/lighting)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.055
	n.fractal_octaves = 5
	var nrm := NoiseTexture2D.new()
	nrm.noise = n
	nrm.as_normal_map = true
	nrm.bump_strength = 3.5
	nrm.width = 512
	nrm.height = 512
	mat.normal_enabled = true
	mat.normal_texture = nrm
	mat.normal_scale = 1.4
	mat.uv1_scale = Vector3(26, 26, 1)

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.name = "Ground"
	add_child(mi)

	var body := StaticBody3D.new()          # click-to-move raycast target
	var col := CollisionShape3D.new()
	var shape := WorldBoundaryShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 2
	add_child(body)

# ---------------------------------------------------------------- crystals
func _crystal_material(hue: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = hue * 0.55
	m.metallic = 0.15
	m.roughness = 0.12
	m.emission_enabled = true
	m.emission = hue
	m.emission_energy_multiplier = energy
	m.rim_enabled = true
	m.rim = 0.7
	return m

func _build_crystals() -> void:
	var hues := [
		Color(0.22, 0.62, 1.0),    # blue
		Color(0.55, 0.32, 1.0),    # violet
		Color(0.90, 0.35, 0.95),   # magenta
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260803
	# three depth bands so the cavern reads with real distance
	var bands := [
		{"n": 12, "min_r": 7.0, "max_r": 20.0, "s": 1.0, "light": true},
		{"n": 14, "min_r": 20.0, "max_r": 45.0, "s": 1.9, "light": true},
		{"n": 16, "min_r": 45.0, "max_r": 95.0, "s": 3.6, "light": false},
	]
	for band in bands:
		for i in int(band["n"]):
			var ang := rng.randf() * TAU
			var rad: float = rng.randf_range(band["min_r"], band["max_r"])
			var pos := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
			var hue: Color = hues[rng.randi() % hues.size()]
			var cluster := _crystal_cluster(rng, hue, float(band["s"]), bool(band["light"]))
			cluster.position = pos
			add_child(cluster)
			crystals.append(cluster)

func _crystal_cluster(rng: RandomNumberGenerator, hue: Color, scale_mul: float, with_light: bool) -> Node3D:
	var grp := Node3D.new()
	var count := rng.randi_range(3, 6)
	var mat := _crystal_material(hue, rng.randf_range(2.2, 4.0))
	for i in count:
		var pm := PrismMesh.new()
		var h := rng.randf_range(1.8, 4.6) * scale_mul
		pm.size = Vector3(rng.randf_range(0.35, 0.9) * scale_mul, h, rng.randf_range(0.35, 0.9) * scale_mul)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(rng.randf_range(-1.0, 1.0) * scale_mul, h * 0.5, rng.randf_range(-1.0, 1.0) * scale_mul)
		mi.rotation_degrees = Vector3(rng.randf_range(-11, 11), rng.randf() * 360.0, rng.randf_range(-11, 11))
		grp.add_child(mi)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = hue
		l.light_energy = 3.2
		l.omni_range = 14.0 * scale_mul
		l.shadow_enabled = false
		l.position = Vector3(0, 1.6 * scale_mul, 0)
		grp.add_child(l)
	return grp

# ---------------------------------------------------------------- grounding props
func _build_boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.13, 0.155)
	mat.roughness = 0.95
	for i in 44:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(6.0, 70.0)
		var s := rng.randf_range(0.4, 1.9)
		var bm := BoxMesh.new()
		bm.size = Vector3(s * rng.randf_range(0.8, 1.6), s, s * rng.randf_range(0.8, 1.6))
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(cos(ang) * rad, s * 0.28, sin(ang) * rad)
		mi.rotation_degrees = Vector3(rng.randf_range(-16, 16), rng.randf() * 360.0, rng.randf_range(-16, 16))
		add_child(mi)

## Retint the whole cavern for a floor change (floors module drives this).
func set_mood(bg: Color, fog_energy: float = 0.7) -> void:
	fog_color = bg
	env.background_color = bg
	env.fog_light_color = bg
	env.fog_light_energy = fog_energy
