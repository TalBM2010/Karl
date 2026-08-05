extends Node3D
class_name KarlWorld
## WORLD & LOOK — the Crystal Depths cavern, built procedurally.
##
## Owns: WorldEnvironment (the Forward+ grade — tonemap/glow/SSAO/volumetric fog), the vignette,
## lighting, the ground material, and the crystal formations that light the scene.
##
## ART DIRECTION (reference frames A/B, Diablo IV bar): a DARK, moody, high-contrast underground
## cavern. Deep blacks everywhere; the ONLY bright things in frame are crystal cores and the pools
## of coloured light they throw. Cool teal/indigo ambient at a whisper, saturated blue/violet
## accents, real atmospheric recession into fog.
##
## FRAMING NOTE (drives every placement decision): game.gd's camera sits at hero + (7.4, 9.6, 7.4)
## with a 38° FOV, i.e. ~37° of pitch. The top of frame hits the ground ~29 m from the camera, so
## nothing past ~32 m from the origin is ever on screen and there is no horizon and no sky. All
## depth has to be manufactured INSIDE that disc: near shards, mid spires, a far rock wall closing
## off the top of the frame, and fog separating the three.

const GROUND_SIZE := 240.0
const WALL_RADIUS := 29.0          # far rock ring — sits just past the top edge of frame
const MAX_CRYSTAL_LIGHTS := 18      # software Vulkan: pay for a few good lights, not many bad ones
const HERO_RING := 7.0             # game.gd patrols Carl on this circle — keep it clear

var crystals: Array[Node3D] = []
var env: Environment
var fog_color := Color(0.030, 0.055, 0.078)

var _rng := RandomNumberGenerator.new()
var _lights_used := 0
var _crystal_mats := {}
var _rock_mat: StandardMaterial3D
var _dark_rock_mat: StandardMaterial3D

func build() -> void:
	_rng.seed = 20260804
	_build_environment()
	_build_vignette()
	_build_lights()
	_build_ground()
	_build_materials()
	_build_cavern_walls()
	_build_rocks()
	_build_crystals()
	_build_debris()
	_build_motes()

# ---------------------------------------------------------------- environment / grade
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.011, 0.016)

	# Ambient is almost off. In a cave nothing lights you but the crystals — that is the whole
	# point of the look, and it is what buys back the deep blacks.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.23, 0.32)
	env.ambient_light_energy = 0.38

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 8.0

	# Glow: high HDR threshold so only emissive crystal cores and light pools bloom. Small
	# levels are muted (they just make aliased sparkle); the wide levels carry the halo.
	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Level weighting is the whole ballgame. The wide levels (4-6) are a 1/16-1/64 res blur; left
	# at full they take every small emissive detail and smear it into a full-screen colour wash —
	# which is exactly the "drowning in blue" failure. Tight halo, almost no wide bleed.
	for i in 7:
		env.set_glow_level(i, 0.0)
	env.set_glow_level(1, 0.30)
	env.set_glow_level(2, 0.85)
	env.set_glow_level(3, 0.55)
	env.set_glow_level(4, 0.18)

	# (SSR was measured here and cut: ~5s per capture run for no visible gain, because the floor
	# is too rough to return a coherent reflection. The wet look comes from the roughness map
	# below instead — glossy patches that throw long specular streaks from the crystal omnis.)

	# Contact darkening — crevices, the seam where rock meets floor, under the hero.
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 3.2
	env.ssao_power = 2.0
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssao_ao_channel_affect = 0.0

	# (SSIL was measured here and cut: +5s per capture run, no read on screen at this light
	# level, and it banded on the large flat rock faces. SSAO alone carries the contact darkening.)

	# Depth fog. Low energy + dark colour: it must separate layers, never milk the frame.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = fog_color
	env.fog_light_energy = 0.40
	env.fog_density = 0.019
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	env.fog_height = 3.2
	env.fog_height_density = 0.075

	# Volumetric haze — ONLY so the crystal omnis throw visible shafts. Every directional light
	# has its volumetric contribution zeroed below: a wide directional scattering into this
	# medium renders as a uniform blue dome over the whole frame that swallows the geometry,
	# which was the single biggest cause of the "flat blue wash".
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.16, 0.34, 0.52)
	env.volumetric_fog_emission = Color(0.002, 0.005, 0.009)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.12
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.06
	env.adjustment_brightness = 1.0
	env.adjustment_color_correction = _grade_lut()

	var we := WorldEnvironment.new()
	we.name = "WorldEnv"
	we.environment = env
	add_child(we)

## Per-channel 1D LUT used as a filmic curve: crushes the toe to real black with a hair of cool
## in the shadows, leaves the highlights alone so crystals still punch.
func _grade_lut() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.10, 0.30, 0.62, 1.0])
	g.colors = PackedColorArray([
		Color(0.000, 0.000, 0.006),
		Color(0.055, 0.062, 0.084),
		Color(0.272, 0.288, 0.322),
		Color(0.640, 0.650, 0.670),
		Color(1.0, 1.0, 1.0),
	])
	var lut := GradientTexture1D.new()
	lut.gradient = g
	lut.width = 256
	return lut

## Cinematic corner falloff. Godot's Environment has no vignette, so this is a full-rect canvas
## overlay on a negative layer — it sits above the 3D and below any HUD the modules add.
func _build_vignette() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode blend_mix, unshaded;
uniform float amount = 0.55;
uniform float inner = 0.30;
uniform float outer = 0.86;
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	d.x *= 1.05;
	float v = smoothstep(inner, outer, length(d) * 1.42);
	COLOR = vec4(0.0, 0.004, 0.010, v * amount);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var rect := ColorRect.new()
	rect.name = "Vignette"
	rect.material = sm
	rect.color = Color(1, 1, 1, 1)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := CanvasLayer.new()
	cl.name = "Grade"
	cl.layer = -1
	cl.add_child(rect)
	add_child(cl)

# ---------------------------------------------------------------- lights
func _build_lights() -> void:
	# A dim cool key. Not "the sun" — just enough directional shape so the hero and the rock
	# relief read, and so we get real shadows for grounding.
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_color = Color(0.50, 0.70, 1.0)
	key.light_energy = 0.62
	key.light_specular = 0.6
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 30.0   # tight = sharp shadows over the visible disc
	key.shadow_blur = 1.6
	key.shadow_bias = 0.11
	key.shadow_normal_bias = 4.5
	key.light_volumetric_fog_energy = 0.0   # see the volumetric note above — non-negotiable
	key.rotation_degrees = Vector3(-58, 34, 0)
	add_child(key)

	# Cold bounce from the crystal field, filling the shadow side without lifting blacks.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.28, 0.42, 0.85)
	fill.light_energy = 0.15
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0
	fill.rotation_degrees = Vector3(-14, -128, 0)
	add_child(fill)

	# Warm kicker so Carl's silhouette separates from all that blue.
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(1.0, 0.62, 0.34)
	rim.light_energy = 0.40
	rim.shadow_enabled = false
	rim.light_volumetric_fog_energy = 0.0
	rim.rotation_degrees = Vector3(-10, 150, 0)
	add_child(rim)

# ---------------------------------------------------------------- ground
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.subdivide_width = 24
	plane.subdivide_depth = 24

	# One coherent set of maps baked from a SHARED crack topology: a broad stone swell carved by a
	# cellular crack network (flagstone slabs), a finer secondary crack pass, and grain. The old
	# ground stacked three independent noise textures (albedo / normal / roughness) that shared no
	# structure, so the relief never lined up with the shading and read as a flat dark plane. Here
	# the normal, the baked crack-AO in the albedo, the roughness (wet in the cracks) and the vein
	# glow are all derived from the same heightfield, so a raking crystal light reads real cracked
	# rock — ridges catch, valleys darken, water pools in the seams.
	var maps := _floor_maps()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = maps["albedo"]

	mat.normal_enabled = true
	mat.normal_texture = maps["normal"]
	mat.normal_scale = 1.35

	mat.roughness = 1.0
	mat.roughness_texture = maps["rough"]
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic = 0.18
	mat.metallic_specular = 0.5

	# Faint mineral glow running ALONG the deep cracks (same topology as the relief), patch-masked
	# so most seams stay dark rock and only a few veins catch the crystal hue.
	mat.emission_enabled = true
	mat.emission = Color(0.14, 0.50, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.emission_texture = maps["emission"]
	# MULTIPLY, not the default ADD: ADD makes the base colour glow across the WHOLE surface and
	# the mask only modulates on top — the "whole floor drowning in blue" failure. MULTIPLY keeps
	# the mask a mask.
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY

	mat.uv1_scale = Vector3(15, 15, 1)   # ~16 m tile: flagstones ~1.2 m, never obviously repeats

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.name = "Ground"
	add_child(mi)

	var body := StaticBody3D.new()          # click-to-move raycast target
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	body.collision_layer = 2
	add_child(body)

## Bakes the four floor maps from one shared heightfield so relief, shading, gloss and vein glow
## all agree. Returns {albedo, normal, rough, emission} as ImageTextures.
##
## Topology: broad simplex swell (the gentle floor undulation) carved by a cellular crack network
## (DISTANCE2_SUB is ~0 at cell boundaries -> those become the mortar lines between flagstones),
## a finer secondary crack pass, plus high-freq grain for tooth. Normals come from finite
## differences on the height, so the cracks are physically the relief — not a decal painted over
## a flat plane.
func _floor_maps() -> Dictionary:
	var R := 512

	var swell := FastNoiseLite.new()
	swell.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	swell.frequency = 0.010
	swell.fractal_octaves = 3
	swell.seed = 7

	var cell := FastNoiseLite.new()
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.frequency = 0.021
	cell.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cell.cellular_jitter = 1.0
	cell.seed = 23

	var cell2 := FastNoiseLite.new()   # finer capillary cracks branching off the main mortar
	cell2.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell2.frequency = 0.052
	cell2.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cell2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cell2.cellular_jitter = 1.0
	cell2.seed = 51

	var grain := FastNoiseLite.new()   # gentle tooth, NOT fine static — kept low so bright pools read as cobbled slabs, not sandpaper
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.09
	grain.seed = 99

	var patch := FastNoiseLite.new()   # where the vein glow is allowed to show
	patch.noise_type = FastNoiseLite.TYPE_SIMPLEX
	patch.frequency = 0.0065
	patch.seed = 91

	# Pass 1: height + crack strength.
	var h := PackedFloat32Array()
	h.resize(R * R)
	var crk := PackedFloat32Array()
	crk.resize(R * R)
	for y in R:
		for x in R:
			var i := y * R + x
			var sw: float = swell.get_noise_2d(float(x), float(y))                 # -1..1
			var c1: float = cell.get_noise_2d(float(x), float(y))                  # ~0 at edges
			var c2: float = cell2.get_noise_2d(float(x), float(y))
			var cr1: float = pow(1.0 - clampf(c1 * 1.7, 0.0, 1.0), 2.2)            # 1 = deep crack
			var cr2: float = pow(1.0 - clampf(c2 * 1.9, 0.0, 1.0), 2.8) * 0.55
			var crack: float = clampf(cr1 + cr2, 0.0, 1.0)
			var g: float = grain.get_noise_2d(float(x), float(y))
			# Flat-topped flagstones: the swell + a light tooth make the slab face, the crack term
			# carves narrow deep mortar lines between them. Small grain weight keeps the lit floor
			# reading as cobbled rock instead of high-frequency speckle.
			h[i] = 0.62 + 0.28 * sw + 0.032 * g - 0.90 * crack
			crk[i] = crack

	# Pass 2: derive normal + albedo(AO) + roughness + emission from the shared height.
	var nimg := Image.create(R, R, false, Image.FORMAT_RGB8)
	var aimg := Image.create(R, R, false, Image.FORMAT_RGB8)
	var rimg := Image.create(R, R, false, Image.FORMAT_RGB8)
	var eimg := Image.create(R, R, false, Image.FORMAT_RGB8)
	var base_stone := Color(0.235, 0.256, 0.292)   # dark wet stone; AO drives it down in the seams
	var nstr := 2.3                                  # height->normal gain
	for y in R:
		for x in R:
			var i := y * R + x
			var xl: float = h[y * R + (x - 1 + R) % R]
			var xr: float = h[y * R + (x + 1) % R]
			var yd: float = h[((y - 1 + R) % R) * R + x]
			var yu: float = h[((y + 1) % R) * R + x]
			var nx: float = (xl - xr) * nstr
			var ny: float = (yd - yu) * nstr
			var nz: float = 1.0
			var inv: float = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
			nimg.set_pixel(x, y, Color(nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5))

			var hv: float = h[i]
			var crack: float = crk[i]
			# Baked AO/relief tint: raised slabs read brighter, mortar seams go dark. This is what
			# makes the floor read even in near-flat lighting where the normal alone is silent.
			var ao: float = clampf(0.58 + 0.5 * hv, 0.28, 1.12) * (1.0 - 0.6 * crack)
			var col: Color = base_stone * ao
			aimg.set_pixel(x, y, col)

			# Roughness: dry, matte on the raised stone; wetter/glossier down in the seams where
			# water would pool, so the crystal omnis throw a thin specular streak along the cracks.
			var rough: float = lerpf(0.52, 0.95, clampf(hv, 0.0, 1.0))
			rough = lerpf(rough, 0.28, crack * 0.72)
			rimg.set_pixel(x, y, Color(rough, rough, rough))

			# Vein glow: only in the deepest cracks, and only inside patch regions, so it stays a
			# scattering of lit seams instead of a glowing grid.
			var pm: float = clampf(patch.get_noise_2d(float(x), float(y)) * 1.7 - 0.15, 0.0, 1.0)
			var em: float = clampf(pow(crack, 1.7) * pm, 0.0, 1.0)
			eimg.set_pixel(x, y, Color(em, em, em))

	return {
		"albedo": ImageTexture.create_from_image(aimg),
		"normal": ImageTexture.create_from_image(nimg),
		"rough": ImageTexture.create_from_image(rimg),
		"emission": ImageTexture.create_from_image(eimg),
	}

## Soft round speck for the dust motes — a bare quad reads as a hard square at any size.
func _dot_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(float(x) - (n - 1) * 0.5, float(y) - (n - 1) * 0.5).length() / (n * 0.5)
			var a := clampf(pow(1.0 - clampf(d, 0.0, 1.0), 2.2), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

## Emission mask for gems: columns = facets (each with its own brightness and a soft internal
## streak), rows = height (molten at the base, near-clear at the tip). Shared by every crystal.
var _facet_glow: ImageTexture
func _facet_glow_texture() -> ImageTexture:
	if _facet_glow:
		return _facet_glow
	var cols := 16
	var rows := 128
	var img := Image.create(cols, rows, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var facet := []
	for c in cols:
		facet.append(r.randf_range(0.22, 1.0))
	var wobble := []
	for c in cols:
		wobble.append(r.randf_range(-0.14, 0.14))
	for y in rows:
		var v := float(y) / float(rows - 1)
		# height falloff: molten base, quick shoulder, faint tip
		# Gentle falloff plus a hot tip. A steep base-only falloff hides the glow, because the
		# fixed 37-degree camera mostly sees the UPPER two-thirds of every spire.
		var fall: float = 0.42 + 0.44 * pow(1.0 - v, 1.1) + 0.30 * pow(v, 7.0)
		for x in cols:
			var c: float = clampf(facet[x] * (fall + wobble[x] * v), 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c))
	_facet_glow = ImageTexture.create_from_image(img)
	return _facet_glow

## Hairline glowing veins in the rock. Rasterised by hand so the result is exact: `vein` is a
## thin ridge wherever the noise crosses zero, `mask` keeps whole regions of floor seam-free.
func _seam_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.011
	n.fractal_octaves = 3
	n.seed = 11
	var mask := FastNoiseLite.new()
	mask.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mask.frequency = 0.004
	mask.seed = 91
	var s := 512
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var v: float = n.get_noise_2d(float(x), float(y))
			var vein: float = pow(1.0 - minf(absf(v) * 13.0, 1.0), 3.0)
			var m: float = clampf(mask.get_noise_2d(float(x), float(y)) * 2.2 - 0.30, 0.0, 1.0)
			var c: float = clampf(vein * m, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c))
	return ImageTexture.create_from_image(img)

func _noise_tex(freq: float, octaves: int, ramp: Gradient) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_gain = 0.42
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	if ramp:
		t.color_ramp = ramp
	return t

func _ramp(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	var o := PackedFloat32Array()
	var c := PackedColorArray()
	for v in offsets:
		o.append(float(v))
	for v in colors:
		c.append(v)
	g.offsets = o
	g.colors = c
	return g

# ---------------------------------------------------------------- shared materials
func _build_materials() -> void:
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(0.380, 0.412, 0.462)
	_rock_mat.roughness = 0.82
	_rock_mat.metallic = 0.12
	_rock_mat.metallic_specular = 0.55
	_rock_mat.rim_enabled = true          # crystal light wrapping the stone edges
	_rock_mat.rim = 0.55
	_rock_mat.rim_tint = 0.25

	# The far wall is deliberately near-black: it is a silhouette, not a subject.
	_dark_rock_mat = StandardMaterial3D.new()
	_dark_rock_mat.albedo_color = Color(0.175, 0.192, 0.230)
	_dark_rock_mat.roughness = 0.95
	_dark_rock_mat.metallic = 0.0
	_dark_rock_mat.rim_enabled = true
	_dark_rock_mat.rim = 0.40
	_dark_rock_mat.rim_tint = 0.2

## Faceted gem material. Emission runs through a vertical gradient (mesh UV.v = height fraction)
## so the crystal is molten at the base and almost clear at the tip — that internal falloff is
## the difference between "gem" and "flat neon slab".
func _crystal_material(hue: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [hue.to_html(false), energy]
	if _crystal_mats.has(key):
		return _crystal_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = hue * 0.32
	m.albedo_color.a = 1.0
	m.metallic = 0.35
	m.metallic_specular = 0.9
	m.roughness = 0.10
	m.emission_enabled = true
	m.emission = hue
	m.emission_energy_multiplier = energy
	m.emission_texture = _facet_glow_texture()
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # see the ground note: ADD flattens
	m.rim_enabled = true
	m.rim = 0.85
	m.rim_tint = 0.4
	_crystal_mats[key] = m
	return m

# ---------------------------------------------------------------- procedural faceted solids
## A faceted spire: stacked irregular rings capped by an off-centre apex, FLAT SHADED so every
## face catches the light differently. This is what makes them read as cut gems rather than
## extruded prisms. UV.v carries the height fraction for the emission falloff.
func _facet_mesh(sides: int, height: float, radius: float, jag: float, lean: Vector2, profile: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF)   # flat shading

	var jitter := []
	for i in sides:
		jitter.append(1.0 + _rng.randf_range(-jag, jag))

	var rings := []
	for p in profile:
		var yf: float = p[0]
		var rs: float = p[1]
		var off := lean * pow(yf, 1.4)
		var ring := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var rr: float = radius * rs * jitter[i]
			ring.append(Vector3(cos(a) * rr + off.x, yf * height, sin(a) * rr + off.y))
		rings.append(ring)

	var apex := Vector3(lean.x + _rng.randf_range(-0.12, 0.12) * radius, height,
		lean.y + _rng.randf_range(-0.12, 0.12) * radius)

	for l in rings.size() - 1:
		var lo: Array = rings[l]
		var hi: Array = rings[l + 1]
		for i in sides:
			var j := (i + 1) % sides
			_tri(st, lo[i], hi[i], hi[j], height)
			_tri(st, lo[i], hi[j], lo[j], height)

	var top: Array = rings[rings.size() - 1]
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, top[i], apex, top[j], height)

	var base: Array = rings[0]
	var c := Vector3(0, 0, 0)
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, base[i], base[j], c, height)

	st.generate_normals()
	return st.commit()

## UV.v is the height fraction (drives the internal glow falloff) and UV.u is the angle around
## the spire's axis, so the emission texture can vary FACET TO FACET. Without that horizontal
## term every face at a given height emits identically and the gem reads as flat neon paper.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, h: float) -> void:
	for p in [a, b, c]:
		var u := atan2(p.z, p.x) / TAU + 0.5
		st.set_uv(Vector2(u, clamp(p.y / max(h, 0.0001), 0.0, 1.0)))
		st.add_vertex(p)

const SPIRE_PROFILE := [[0.0, 1.0], [0.14, 1.05], [0.62, 0.70], [0.80, 0.50]]
const SHARD_PROFILE := [[0.0, 0.94], [0.12, 1.0], [0.70, 0.93], [0.82, 0.84]]
const BOULDER_PROFILE := [[0.0, 0.86], [0.28, 1.05], [0.62, 0.92], [0.86, 0.55]]

# ---------------------------------------------------------------- cavern shell
## A ring of near-black rock masses just outside the camera's reach. They fill the top of every
## frame, so the cavern reads as ENCLOSED instead of an infinite plane, and every glowing crystal
## in the mid ground gets something dark to silhouette against.
func _build_cavern_walls() -> void:
	var count := 26
	for i in count:
		var a := TAU * float(i) / float(count) + _rng.randf_range(-0.06, 0.06)
		var rad := WALL_RADIUS + _rng.randf_range(-1.6, 4.5)
		var h := _rng.randf_range(9.0, 20.0)
		var r := _rng.randf_range(3.4, 6.4)
		var mesh := _facet_mesh(7, h, r, 0.26, Vector2(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-1.2, 1.2)), BOULDER_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _dark_rock_mat
		mi.position = Vector3(cos(a) * rad, -1.2, sin(a) * rad)
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# A skirt of talus where the wall meets the floor, so the junction is not a clean line.
	for i in 30:
		var a := _rng.randf() * TAU
		var rad := WALL_RADIUS - _rng.randf_range(1.0, 6.0)
		var s := _rng.randf_range(1.2, 3.4)
		var mesh := _facet_mesh(6, s * 0.8, s, 0.34, Vector2.ZERO, BOULDER_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _dark_rock_mat
		mi.position = Vector3(cos(a) * rad, -0.25, sin(a) * rad)
		mi.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

# ---------------------------------------------------------------- rocks / stalagmites
func _build_rocks() -> void:
	# Mid-ground stalagmites: the layer that actually creates sightlines and depth cues.
	for i in 30:
		var p := _scatter(10.0, 26.0)
		var h := _rng.randf_range(2.2, 6.5)
		var mesh := _facet_mesh(6, h, _rng.randf_range(0.7, 1.7), 0.30, Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)), SPIRE_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _rock_mat
		mi.position = p
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)

	# Near boulders and rubble: foreground weight, contact shadows, scale reference next to Carl.
	for i in 46:
		var p := _scatter(3.0, 24.0)
		var s := _rng.randf_range(0.35, 1.7)
		var mesh := _facet_mesh(7, s * _rng.randf_range(0.6, 1.1), s, 0.36, Vector2.ZERO, BOULDER_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _rock_mat
		mi.position = p - Vector3(0, s * 0.22, 0)
		mi.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)

	# Flat shelves — broken slabs of cavern floor, they break up the plane without adding height.
	for i in 16:
		var p := _scatter(5.0, 25.0)
		var mesh := _facet_mesh(6, 0.5, _rng.randf_range(2.0, 4.2), 0.30, Vector2.ZERO, BOULDER_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _rock_mat
		mi.position = p - Vector3(0, 0.22, 0)
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

## Random point in an annulus, biased into frame and keeping the hero's patrol circle clear.
##
## FIELD_BIAS is the important half: the camera is welded to hero + (7.4, 9.6, 7.4) and always
## looks down the -X/-Z diagonal, so the framed wedge sits offset from the origin in that
## direction. An origin-centred scatter spends half its props behind the camera. This does not.
const FIELD_BIAS := Vector3(-4.0, 0.0, -4.0)

func _scatter(min_r: float, max_r: float) -> Vector3:
	for attempt in 16:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * (max_r - min_r) + min_r
		var p := Vector3(cos(a) * r, 0, sin(a) * r) + FIELD_BIAS
		if absf(p.length() - HERO_RING) > 2.4:
			return p
	return Vector3(min_r + 3.0, 0, 0) + FIELD_BIAS

# ---------------------------------------------------------------- grounded debris
## Soft dark contact patch laid flat on the floor under a prop. The directional key throws a real
## shadow, but at the camera's standoff a small prop's cast shadow is a few pixels; this blob is
## what actually reads as "sitting ON the floor" the way a D4 prop does — an AO decal, not a
## floating object. Shared material, one radial alpha texture.
var _blob_mat: StandardMaterial3D
func _blob_shadow(radius: float) -> MeshInstance3D:
	if _blob_mat == null:
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		_blob_mat.albedo_color = Color(0.0, 0.004, 0.008, 0.62)
		_blob_mat.albedo_texture = _dot_texture()   # radial: opaque centre -> transparent rim
		_blob_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_blob_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_blob_mat.disable_receive_shadows = true
		_blob_mat.render_priority = 2   # draw over the floor emission so the seam glow doesn't punch through
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _blob_mat
	mi.rotation_degrees = Vector3(-90, _rng.randf() * 360.0, 0)   # lay flat, facing up
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Scattered floor clutter — this is what turns an empty plane into an inhabited cavern floor.
## Three kinds, all grounded with a blob contact shadow: broken crystal shards lying where they
## fell (faintly lit, catching the crystal hue), rock rubble/chips, and bleached bone piles.
func _build_debris() -> void:
	var shard_hues := [Color(0.10, 0.42, 1.0), Color(0.06, 0.72, 1.0), Color(0.42, 0.16, 1.0), Color(0.62, 0.22, 0.72)]
	var shard_energies := [1.1, 1.4, 1.7]

	# Fallen crystal shards — lying on their side. Dimmer than the standing formations so they
	# read as debris, not a second crystal field, but they still catch the eye and prove the floor
	# is lit from within.
	for i in 28:
		var p := _scatter(3.5, 24.0)
		var hue: Color = shard_hues[_rng.randi() % shard_hues.size()]
		var energy: float = shard_energies[_rng.randi() % shard_energies.size()]
		var l: float = _rng.randf_range(0.55, 1.5)
		var rad: float = l * _rng.randf_range(0.15, 0.24)
		var sides := 5 if _rng.randf() < 0.5 else 6
		var mesh := _facet_mesh(sides, l, rad, 0.24, Vector2.ZERO, SHARD_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _crystal_material(hue, energy)
		# Tip it onto its side and let it rest, half-buried, on the floor.
		mi.rotation = Vector3(PI * 0.5 + _rng.randf_range(-0.28, 0.28), _rng.randf() * TAU, _rng.randf_range(-0.32, 0.32))
		mi.position = p + Vector3(0, rad * 0.72, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		var b := _blob_shadow(maxf(l * 0.42, rad * 1.6))
		b.position = Vector3(p.x, 0.02, p.z)
		add_child(b)

	# Rock rubble / chips — the mining detritus between the formations. Small, dense, tumbled.
	for i in 34:
		var p := _scatter(3.0, 25.0)
		var s: float = _rng.randf_range(0.18, 0.55)
		var mesh := _facet_mesh(6, s * _rng.randf_range(0.4, 0.85), s, 0.44, Vector2.ZERO, BOULDER_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _rock_mat
		mi.position = p - Vector3(0, s * 0.16, 0)
		mi.rotation = Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		if s > 0.3:
			var b := _blob_shadow(s * 1.25)
			b.position = Vector3(p.x, 0.02, p.z)
			add_child(b)

	# Bleached bone piles — a few scattered heaps of what the dungeon left behind.
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.66, 0.64, 0.585)   # pale enough to catch the eye against dark rock
	bone_mat.roughness = 0.72
	bone_mat.metallic = 0.0
	bone_mat.rim_enabled = true          # crystal light catching the pale bone
	bone_mat.rim = 0.45
	bone_mat.rim_tint = 0.3
	for pile in 5:
		var c := _scatter(5.0, 22.0)
		var n := _rng.randi_range(3, 6)
		for bi in n:
			var bone := CapsuleMesh.new()
			bone.radius = _rng.randf_range(0.045, 0.085)
			bone.height = _rng.randf_range(0.5, 1.1)
			bone.radial_segments = 6
			bone.rings = 2
			var mi := MeshInstance3D.new()
			mi.mesh = bone
			mi.material_override = bone_mat
			var off := Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
			mi.position = c + Vector3(off.x, bone.radius * 0.9, off.y)
			# Capsule long axis is +Y; tip it nearly flat so bones lie on the ground.
			mi.rotation = Vector3(PI * 0.5 + _rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
		var b := _blob_shadow(0.9)
		b.position = Vector3(c.x, 0.02, c.z)
		add_child(b)

# ---------------------------------------------------------------- crystals
func _build_crystals() -> void:
	# Saturated and channel-separated. A hue whose channels are all high just clips to white
	# under ACES, which is what made the first pass read as neon paper instead of gemstone.
	#
	# The emission energies below are deliberately LOW (peak channel lands near 1.0-2.0). Push
	# them higher and the strongest channel clips, every facet saturates to the same flat value,
	# and the internal structure from the facet mask disappears — plastic fins instead of gems.
	# Brightness comes from the omni pools and from glow catching only the hottest cores.
	var blue := Color(0.10, 0.42, 1.0)
	var azure := Color(0.06, 0.72, 1.0)
	var violet := Color(0.42, 0.16, 1.0)
	var magenta := Color(0.62, 0.22, 0.72)

	# Deliberate layering, not one uniform scatter: hero spires that own the frame, a mid field
	# that carries the light, near shards for foreground parallax, and a far rim that backlights
	# the wall. Each layer has its own scale so the eye reads distance.
	var layers := [
		# hero spires — the tall landmark formations, all of them lit
		{"n": 7, "min_r": 9.0, "max_r": 18.0, "h": [7.0, 12.5], "r": [0.55, 1.0], "cnt": [5, 8], "hues": [blue, violet], "light": 30.0, "lights": 5, "e": [2.1, 2.7]},
		# mid field
		{"n": 24, "min_r": 6.0, "max_r": 21.0, "h": [2.6, 5.6], "r": [0.28, 0.55], "cnt": [4, 7], "hues": [azure, blue, azure, blue, violet], "light": 17.0, "lights": 6, "e": [2.1, 2.6]},
		# near shards — small, dense, foreground
		{"n": 30, "min_r": 3.0, "max_r": 16.0, "h": [1.1, 2.8], "r": [0.16, 0.34], "cnt": [4, 8], "hues": [azure, blue, azure, blue, blue, magenta], "light": 6.5, "lights": 3, "e": [2.0, 2.6]},
		# far rim — big silhouettes glowing against the cavern wall
		{"n": 8, "min_r": 22.0, "max_r": 30.0, "h": [5.0, 10.0], "r": [0.42, 0.85], "cnt": [4, 7], "hues": [blue, violet, blue, violet, magenta], "light": 22.0, "lights": 4, "e": [2.2, 2.8]},
	]

	for layer in layers:
		var budget := int(layer["lights"])
		for i in int(layer["n"]):
			# spend each layer's light budget on its first (largest) formations
			layer["lit"] = budget > 0 and i < budget
			var pos := _scatter(float(layer["min_r"]), float(layer["max_r"]))
			var hues: Array = layer["hues"]
			var hue: Color = hues[_rng.randi() % hues.size()]
			var cluster := _crystal_cluster(layer, hue)
			cluster.position = pos
			add_child(cluster)
			crystals.append(cluster)

func _crystal_cluster(layer: Dictionary, hue: Color) -> Node3D:
	var grp := Node3D.new()
	var hr: Array = layer["h"]
	var rr: Array = layer["r"]
	var cr: Array = layer["cnt"]
	var er: Array = layer["e"]
	var count := _rng.randi_range(int(cr[0]), int(cr[1]))
	var spread: float = float(rr[1]) * 4.0 + float(hr[1]) * 0.18
	var mat := _crystal_material(hue, _rng.randf_range(float(er[0]), float(er[1])))
	var tallest := 0.0

	for i in count:
		# Shards get progressively smaller away from the cluster core — a real formation has one
		# dominant blade with satellites, never a row of equals.
		var falloff: float = 1.0 - 0.62 * (float(i) / float(max(count - 1, 1)))
		var h: float = _rng.randf_range(float(hr[0]), float(hr[1])) * falloff
		var rad: float = _rng.randf_range(float(rr[0]), float(rr[1])) * falloff
		var sides := 5 if _rng.randf() < 0.5 else 6
		var lean := Vector2(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.35, 0.35)) * h * 0.14
		var mesh := _facet_mesh(sides, h, rad, 0.22, lean, SHARD_PROFILE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.0, spread)
		if i == 0:
			off = Vector2.ZERO
		mi.position = Vector3(off.x, -0.15, off.y)
		# Shards fan outward from the cluster centre like a real crystal bloom.
		var tilt := 0.0 if i == 0 else _rng.randf_range(0.10, 0.34)
		var away := atan2(off.x, off.y)
		mi.rotation = Vector3(cos(away) * tilt, _rng.randf() * TAU, -sin(away) * tilt)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grp.add_child(mi)
		tallest = max(tallest, h)

	# Rock mound at the base — real crystal formations erupt from broken stone, and the mound
	# gives the cluster a silhouette and a contact shadow instead of a clean floor intersection.
	if spread > 0.9:
		for i in 3:
			var mr: float = spread * _rng.randf_range(0.35, 0.75)
			var chunk := _facet_mesh(6, mr * _rng.randf_range(0.5, 0.9), mr, 0.38, Vector2.ZERO, BOULDER_PROFILE)
			var cmi := MeshInstance3D.new()
			cmi.mesh = chunk
			cmi.material_override = _rock_mat
			var ca := TAU * (float(i) + _rng.randf()) / 3.0
			cmi.position = Vector3(cos(ca) * spread * 0.5, -mr * 0.35, sin(ca) * spread * 0.5)
			cmi.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
			cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			grp.add_child(cmi)

	var lenergy: float = float(layer["light"])
	if lenergy > 0.0 and bool(layer.get("lit", false)) and _lights_used < MAX_CRYSTAL_LIGHTS:
		_lights_used += 1
		var l := OmniLight3D.new()
		l.light_color = hue
		l.light_energy = lenergy
		# Tight range + steep attenuation = a POOL of colour on the floor, not a blue wash.
		# Tight range + a steep curve is what makes these read as POOLS with darkness between
		# them. Wide, soft omnis just re-create the blue wash from a different direction.
		l.omni_range = clamp(tallest * 2.3, 7.0, 17.0)
		l.omni_attenuation = 1.7
		l.light_specular = 1.0
		l.light_volumetric_fog_energy = 0.30
		l.shadow_enabled = false
		l.position = Vector3(0, maxf(tallest * 0.38, 0.8), 0)
		grp.add_child(l)
	return grp

# ---------------------------------------------------------------- atmosphere
## Slow drifting motes. Cheap CPU particles, but they are most of what sells "air" in a still.
func _build_motes() -> void:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = 180
	p.lifetime = 11.0
	p.preprocess = 8.0
	p.randomness = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(24, 5.0, 24)
	p.position = Vector3(0, 4.5, 0)
	p.direction = Vector3(0.4, 1, 0.2)
	p.spread = 60.0
	p.gravity = Vector3(0, 0.02, 0)
	p.initial_velocity_min = 0.06
	p.initial_velocity_max = 0.35
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	p.color = Color(0.55, 0.82, 1.0, 0.5)

	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)

	# The material lives on the MESH, and its albedo alpha must be low: with an opaque albedo
	# these draw as flat grey squares instead of additive specks, whatever the particle colour.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.55, 0.80, 1.0, 0.30)
	m.albedo_texture = _dot_texture()   # without a soft falloff these read as hard grey squares
	m.disable_receive_shadows = true
	m.no_depth_test = false
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

## Retint the whole cavern for a floor change (floors module drives this).
func set_mood(bg: Color, fog_energy: float = 0.7) -> void:
	fog_color = bg
	env.background_color = bg.darkened(0.85)
	env.fog_light_color = bg
	env.fog_light_energy = fog_energy * 0.65
	env.ambient_light_color = bg.lightened(0.25)
	env.volumetric_fog_albedo = bg.lightened(0.45)
