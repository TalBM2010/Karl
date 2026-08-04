extends Node3D
## DUNGEON KARL — Godot orchestration.
##
## Owns the fixed Diablo-IV isometric camera, the hero, and the auto-demo director that drives
## the game for capture runs. Visual/system modules live in their own scripts (world.gd,
## player.gd, and the modules added by builders) so they can be improved independently.
##
## Modules plug in by being added here; each exposes `build()` and optional `_process`.

# Fixed pitched iso — the D4 signature. ~43° pitch; pulled close enough that Carl reads
# as a prominent hero (~1/6 of frame height) sitting in the lower-middle third.
const CAM_OFFSET := Vector3(7.4, 9.6, 7.4)
const CAM_OFFSET_BOSS := Vector3(12.0, 15.5, 12.0)   # whole-boss framing for the Juicer
const CaptureAgent := preload("res://scripts/capture.gd")

var world: KarlWorld
var carl: KarlPlayer
var cam: Camera3D

var hero_pos := Vector3.ZERO
var hero_face := 0.0
var _cam_target := Vector3.ZERO
var _cam_pos := Vector3.ZERO
var _demo_t := 0.0
var _attack_cd := 0.0
var is_capture := false
var modules := {}

## Emitted so feature modules can react without touching this script.
signal hero_attacked(target_pos: Vector3, damage: int, crit: bool)
signal enemy_killed(pos: Vector3)
signal floor_changed(index: int)

func _ready() -> void:
	is_capture = OS.get_cmdline_user_args().size() > 0

	world = KarlWorld.new()
	world.name = "World"
	add_child(world)
	world.build()

	carl = KarlPlayer.new()
	carl.name = "Carl"
	add_child(carl)
	carl.build()

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 400.0
	add_child(cam)
	_cam_pos = _cam_target + CAM_OFFSET
	cam.position = _cam_pos
	cam.look_at(_cam_target + Vector3(0, 1.6, 0))

	_load_modules()

	var cap: Node = CaptureAgent.new()
	cap.name = "Capture"
	add_child(cap)

## Optional feature modules plug in here — each is res://scripts/modules/<name>.gd,
## extends Node, and implements `setup(game)`. Missing files are skipped silently, so
## builders can own one file each without ever touching this orchestration script.
func _load_modules() -> void:
## Each module is isolated: a module that fails to parse, instantiate, or set up is skipped
## with a warning instead of aborting the loop. Without this, one bad script silently took
## every later module down with it (that bit us during parallel development).
	for m in ["hud", "combat", "enemies", "loot", "floors", "screens"]:
		var path := "res://scripts/modules/%s.gd" % m
		if not ResourceLoader.exists(path):
			continue
		var scr: Script = load(path)
		if scr == null or not scr.can_instantiate():
			push_warning("module '%s' failed to load — skipping" % m)
			continue
		var inst: Variant = scr.new()
		if not (inst is Node):
			push_warning("module '%s' is not a Node — skipping" % m)
			continue
		var node: Node = inst
		node.name = m
		add_child(node)
		if node.has_method("setup"):
			node.call("setup", self)
		modules[m] = node

func _process(delta: float) -> void:
	_demo_director(delta)
	_update_camera(delta)

## Auto-play so captures always show motion: Carl patrols and swings.
func _demo_director(delta: float) -> void:
	_demo_t += delta
	var target := Vector3(sin(_demo_t * 0.35) * 7.0, 0, cos(_demo_t * 0.35) * 7.0)
	var to := target - hero_pos
	to.y = 0
	var moving := to.length() > 0.4
	if moving:
		var dir := to.normalized()
		hero_pos += dir * 4.2 * delta
		hero_face = atan2(dir.x, dir.z)
	if carl:
		carl.position = hero_pos
		carl.rotation.y = lerp_angle(carl.rotation.y, hero_face, 0.18)
		carl.set_state("move" if moving else "idle")
		_attack_cd -= delta
		if _attack_cd <= 0.0:
			_attack_cd = 1.4
			carl.attack()

func _update_camera(delta: float) -> void:
	_cam_target = _cam_target.lerp(hero_pos, 0.08)
	_cam_pos = _cam_pos.lerp(_cam_target + CAM_OFFSET, 0.10)
	cam.position = _cam_pos
	cam.look_at(_cam_target + Vector3(0, 1.6, 0))
