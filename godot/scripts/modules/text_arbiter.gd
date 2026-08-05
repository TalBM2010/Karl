extends Node
## SHARED SCREEN-SPACE TEXT ARBITER
##
## Three independent systems draw billboarded Label3D text into the frame and don't know about
## each other: damage numbers (combat.gd), loot / ground labels (loot.gd) and enemy nameplates
## (enemies.gd). On the boss cam every blow lands at screen-centre, so their rects collide and the
## text becomes an unreadable smear (see coh8lab2/shot_05, shot_07).
##
## This node is the ONE place they coordinate. It is intentionally tiny, passive (no _process) and
## fault-isolated: any module may create it (whichever runs first), it is stashed on
## game.modules["text_arbiter"], and every caller guards the reach so a missing/failed arbiter just
## means the old, un-coordinated behaviour — never a crash.
##
## PRIORITY when two rects clash:  damage(3) > loot(2) > nameplate(1).
##   * Damage numbers only REGISTER their rect (they keep their own vertical-lane system and win
##     ties) — they never yield.
##   * Loot labels and nameplates PLACE: they query for overlaps with equal-or-higher rects and
##     slide to the nearest free vertical band; if boxed in under a damage number they report
##     `hidden` so the caller can dim out.
##
## Rects are keyed by the label's instance id and stamped with the process-frame they were touched
## on; anything not refreshed for a frame is pruned, so nothing leaks and the set stays tiny. This
## also makes coordination order-independent: damage is registered first each frame (combat
## processes before the others), so lower-priority text always sees the current damage rects, while
## the only cross-priority stale case (a nameplate yielding to a loot label processed later) reads
## last frame's near-static loot rect — visually identical.

const PRI_DAMAGE := 3
const PRI_LOOT := 2
const PRI_PLATE := 1

# Every rect is inflated by this many screen pixels on each side. The nominal glyph box we compute
# ignores the heavy 9-14px text OUTLINE and the ascender/descender overhang, so two rects that only
# TOUCH still render as visually overlapping text. The margin turns "touching" into a real, readable
# gap between separated labels.
const MARGIN := 13.0

var _game: Node = null
var _cam: Camera3D = null
var _rects: Dictionary = {}     # instance_id -> {rect: Rect2, pri: int, frame: int}
var _frame: int = -1

func setup(g) -> void:
	_game = g
	_cam = g.cam if (g and "cam" in g) else null


func _cam_ok() -> bool:
	if _cam == null or not is_instance_valid(_cam):
		# the camera may not have existed when we were created; pull it lazily
		_cam = _game.cam if (_game and "cam" in _game and _game.cam != null) else null
	return _cam != null and is_instance_valid(_cam)


func _vp_h() -> float:
	if _cam and _cam.get_viewport():
		return maxf(1.0, _cam.get_viewport().get_visible_rect().size.y)
	return 1000.0


func _tan_half_fov() -> float:
	var f: float = _cam.fov if _cam else 38.0
	return maxf(0.01, tan(deg_to_rad(f) * 0.5))


## Screen half-extent (pixels) of a `fixed_size` Label3D. For fixed_size labels the on-screen size
## is distance-independent: full glyph height = pixel_size * font_size * viewport_h / (2 tan(fov/2))
## (this reproduces the 115px / 72px figures noted in combat.gd). Width is estimated from a ~0.6
## glyph aspect — approximate is fine, the rect only needs to be a sensible keep-out box.
func half_extent(pixel_size: float, font_size: int, chars: int) -> Vector2:
	if not _cam_ok():
		return Vector2(24.0, 14.0)
	var h_px: float = pixel_size * float(font_size) * _vp_h() / (2.0 * _tan_half_fov())
	var half_h: float = h_px * 0.5
	var half_w: float = maxf(1.0, float(chars)) * h_px * 0.30
	return Vector2(half_w, half_h)


## On-screen pixels per world unit at the depth of `world_pos` — lets a caller convert the world
## offset of a two-line label's sub-line into the pixel span its keep-out rect must cover.
func px_per_world(world_pos: Vector3) -> float:
	if not _cam_ok():
		return 1.0
	var dist: float = maxf(0.05, -(_cam.to_local(world_pos).z))
	return _vp_h() / (2.0 * dist * _tan_half_fov())


func _prune(now: int) -> void:
	if now == _frame:
		return
	# Keep only rects touched during the frame that just ended; older ones belong to labels that
	# have gone away. This runs on the first arbiter call of each new process-frame.
	var keep: Dictionary = {}
	for id in _rects:
		var e: Dictionary = _rects[id]
		if int(e["frame"]) >= _frame:
			keep[id] = e
	_rects = keep
	_frame = now


func _rect_at(sp: Vector2, half_w: float, half_h: float) -> Rect2:
	var hw: float = half_w + MARGIN
	var hh: float = half_h + MARGIN
	return Rect2(sp.x - hw, sp.y - hh, hw * 2.0, hh * 2.0)


## True if `r` overlaps any registered rect (other than `id`) whose priority is >= `min_pri`.
func _collides(r: Rect2, min_pri: int, id: int) -> bool:
	for oid in _rects:
		if oid == id:
			continue
		var e: Dictionary = _rects[oid]
		if int(e["pri"]) < min_pri:
			continue
		if r.intersects(e["rect"]):
			return true
	return false


## DAMAGE PATH — stamp a keep-out rect for a top-priority label without moving it.
func register(id: int, world_pos: Vector3, half_w: float, half_h: float, pri: int) -> void:
	if not _cam_ok():
		return
	_prune(Engine.get_process_frames())
	if _cam.is_position_behind(world_pos):
		_rects.erase(id)
		return
	var sp: Vector2 = _cam.unproject_position(world_pos)
	_rects[id] = {"rect": _rect_at(sp, half_w, half_h), "pri": pri, "frame": _frame}


## LOOT / NAMEPLATE PATH — find the nearest vertical band that clears every equal-or-higher rect,
## register the result, and return {pos: adjusted world position, hidden: bool}. `hidden` is only
## true when the label is boxed in directly under a DAMAGE rect and has nowhere free to go.
func place(id: int, world_pos: Vector3, half_w: float, half_h: float, pri: int) -> Dictionary:
	var res: Dictionary = {"pos": world_pos, "hidden": false}
	if not _cam_ok():
		return res
	_prune(Engine.get_process_frames())
	if _cam.is_position_behind(world_pos):
		_rects.erase(id)
		return res

	var sp: Vector2 = _cam.unproject_position(world_pos)
	# Step size and count are bounded so a fully-blocked column nudges the label a sane distance
	# (~200-270px) and then yields/hides, rather than flinging it clear across the frame.
	var band: float = maxf(half_h * 0.5, 12.0)
	var max_steps: int = 16

	var dy: float = 0.0
	var found: bool = false
	# offset 0 first, then alternate up (screen -y) / down with growing magnitude
	if not _collides(_rect_at(sp, half_w, half_h), pri, id):
		found = true
	else:
		for step in range(1, max_steps + 1):
			var up: float = -float(step) * band
			if not _collides(_rect_at(Vector2(sp.x, sp.y + up), half_w, half_h), pri, id):
				dy = up
				found = true
				break
			var down: float = float(step) * band
			if not _collides(_rect_at(Vector2(sp.x, sp.y + down), half_w, half_h), pri, id):
				dy = down
				found = true
				break

	var sp2: Vector2 = Vector2(sp.x, sp.y + dy)
	if found:
		_rects[id] = {"rect": _rect_at(sp2, half_w, half_h), "pri": pri, "frame": _frame}
	else:
		# nowhere free — leave it at rest; hide only if a damage rect actually covers it
		dy = 0.0
		res["hidden"] = _collides(_rect_at(sp, half_w, half_h), PRI_DAMAGE, id)
		if not res["hidden"]:
			_rects[id] = {"rect": _rect_at(sp, half_w, half_h), "pri": pri, "frame": _frame}
		else:
			_rects.erase(id)

	# Turn the screen-vertical nudge back into a WORLD move. The camera has no roll, so a change in
	# world +Y projects to a pure vertical screen shift — measure that px-per-world-Y factor directly
	# (unproject a point 1 unit up) and invert it. project_position was WRONG here: at a fixed
	# camera-forward depth it slid the label down-and-back for this downward-pitched cam.
	var k: float = _cam.unproject_position(world_pos + Vector3(0.0, 1.0, 0.0)).y - sp.y
	var t: float = 0.0
	if absf(k) > 0.00001:
		t = dy / k
	res["pos"] = world_pos + Vector3(0.0, t, 0.0)
	return res
