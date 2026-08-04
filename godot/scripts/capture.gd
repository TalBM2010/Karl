extends Node
## CAPTURE AGENT — the eyes of the build/critic loop.
##
## Runs inside the game, so it saves exact rendered frames no matter how slow the software
## Vulkan (lavapipe) device is. Under xvfb the wall clock and the render clock diverge wildly,
## so this waits on RENDERED FRAMES (RenderingServer.frame_post_draw), not on real time —
## which makes captures deterministic and makes motion strips actually usable.
##
## Usage (after the `--` separator):
##   godot --path godot -- --out /abs/dir --shots 6 --gap 30 --strip 12 --stripgap 6 --quit
##     --out      absolute output directory
##     --shots    number of numbered stills (shot_00.png ...)
##     --gap      rendered frames to advance between stills
##     --strip    number of rapid motion frames (strip_00.png ...)
##     --stripgap rendered frames between strip frames
##     --warm     frames to render before the first shot (let the scene settle)
##     --quit     exit when done (default true)

var out_dir := ""
var shots := 4
var gap := 30
var strip := 0
var stripgap := 6
var warm := 40
var do_quit := true

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		match a[i]:
			"--out": out_dir = a[i + 1]; i += 1
			"--shots": shots = int(a[i + 1]); i += 1
			"--gap": gap = int(a[i + 1]); i += 1
			"--strip": strip = int(a[i + 1]); i += 1
			"--stripgap": stripgap = int(a[i + 1]); i += 1
			"--warm": warm = int(a[i + 1]); i += 1
			"--noquit": do_quit = false
		i += 1
	if out_dir == "":
		return  # not a capture run — just play normally
	set_process(false)
	_run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _advance(warm)
	var manifest := {"shots": [], "strip": [], "errors": []}

	for s in shots:
		var p := "%s/shot_%02d.png" % [out_dir, s]
		if _grab(p):
			manifest["shots"].append(p)
		else:
			manifest["errors"].append("failed shot %d" % s)
		if s < shots - 1:
			await _advance(gap)

	for s in strip:
		var p := "%s/strip_%02d.png" % [out_dir, s]
		if _grab(p):
			manifest["strip"].append(p)
		await _advance(stripgap)

	manifest["fps"] = Engine.get_frames_per_second()
	manifest["renderer"] = RenderingServer.get_video_adapter_name()
	var f := FileAccess.open("%s/capture.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
	print("CAPTURE_OK shots=%d strip=%d fps=%d" % [manifest["shots"].size(), manifest["strip"].size(), manifest["fps"]])
	if do_quit:
		get_tree().quit()

## Wait for n fully-rendered frames.
func _advance(n: int) -> void:
	for i in max(1, n):
		await RenderingServer.frame_post_draw

func _grab(path: String) -> bool:
	var tex := get_viewport().get_texture()
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null or img.is_empty():
		return false
	return img.save_png(path) == OK
