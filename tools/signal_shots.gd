extends Node
##
## Visual evidence for the signal override. Signals never fire during an
## export (that is the purity guard), so the only way to SEE crumble and the
## cursor-anchored ripple is to fire one on a live canvas and save the frame.
##
## Writes exports/_signal_shots/*.png and exits.

const OUT := "res://exports/signal_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _crumble_strip()
	await _ripple_strip()
	await _demo_sheets()
	print("OK  wrote ", ProjectSettings.globalize_path(OUT))
	get_tree().quit()


func _stage(path: String) -> Dictionary:
	var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()
	canvas.live_playback = false   # tests pose by hand; no live clock
	var sv := SubViewport.new()
	sv.size = Vector2i(canvas.design_size)
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = canvas.design_size
	rect.color = canvas.clear_color
	sv.add_child(rect)
	sv.add_child(canvas)
	add_child(sv)
	return {"canvas": canvas, "sv": sv}


func _shot(sv: SubViewport, name: String, scale := 4) -> void:
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	if scale > 1:
		img.resize(img.get_width() * scale, img.get_height() * scale,
				   Image.INTERPOLATE_NEAREST)
	img.save_png("%s/%s.png" % [OUT, name])


## TV-out drives the title/subtitle crumble. MAIN_MENU authors no crumble_fx,
## so the defaults apply: direction 90 degrees is straight DOWN, spread 12.
func _crumble_strip() -> void:
	var st := _stage("res://anims/main_menu.tscn")
	var canvas: ZenCanvas = st["canvas"]
	var sv: SubViewport = st["sv"]
	await get_tree().process_frame
	var t := 2.0
	canvas.pose(t)
	await _shot(sv, "crumble_0_before")

	var bus: ZenSignalBus = canvas.bus()
	canvas.pose(t)
	bus.fire("TV-out")
	bus.set_process(false)
	var shots := [0.15, 0.35, 0.55, 0.9, 1.4, 2.0]
	var at := 0.0
	for s in shots:
		bus.advance(float(s) - at)
		at = float(s)
		canvas.pose(t)
		await _shot(sv, "crumble_%.2f" % at)
	sv.queue_free()


## mouse_ripple's `ripple` is usesPos + posAnchor: the authored path is
## TRANSLATED to the emitted point, so the ring is born under the cursor.
func _ripple_strip() -> void:
	for p in [Vector2(0.25, 0.30), Vector2(0.75, 0.70), Vector2(0.5, 0.5)]:
		var st := _stage("res://anims/mouse_ripple.tscn")
		var canvas: ZenCanvas = st["canvas"]
		var sv: SubViewport = st["sv"]
		await get_tree().process_frame
		var t := 0.75
		canvas.pose(t)
		var bus: ZenSignalBus = canvas.bus()
		bus.fire("ripple", {"pos": p})
		bus.set_process(false)
		bus.advance(0.2)
		canvas.pose(t)
		await _shot(sv, "ripple_at_%.2f_%.2f" % [p.x, p.y])
		sv.queue_free()


## The sig_* demos (tools/gen_signal_demos.gd), each driven through a short
## script of pointer events and signal clock steps, one contact sheet per demo.
## A step is [action, arg]: press/release/move at a canvas fraction, fire a
## signal by name, end (the end trigger, arg = wrap count), or wait seconds -
## every wait is followed by a frame.
const DEMOS := {
	"sig_press_anchor": [["press", Vector2(0.3, 0.4)], ["wait", 0.08], ["wait", 0.2],
		["wait", 0.3], ["press", Vector2(0.75, 0.6)], ["wait", 0.15]],
	"sig_release_seek": [["wait", 0.0], ["release", Vector2(0.2, 0.25)], ["wait", 0.15],
		["wait", 0.25], ["wait", 0.25], ["wait", 0.1]],
	"sig_follow": [["move", Vector2(0.8, 0.3)], ["press", Vector2(0.8, 0.3)], ["wait", 0.15],
		["wait", 0.3], ["move", Vector2(0.2, 0.7)], ["wait", 0.1], ["release", Vector2(0.2, 0.7)],
		["wait", 0.2], ["wait", 0.3], ["wait", 0.2]],
	"sig_code": [["fire", "flash"], ["wait", 0.05], ["move", Vector2(0.3, 0.6)],
		["fire", "ping"], ["wait", 0.15], ["wait", 0.5], ["wait", 0.6]],
	"sig_end_once": [["wait", 0.0], ["end", 0], ["wait", 0.15], ["wait", 0.5]],
	"sig_end_every_loop": [["end", 1], ["wait", 0.1], ["wait", 0.4], ["end", 2], ["wait", 0.1]],
	"sig_end_first_loop": [["end", 1], ["wait", 0.1], ["wait", 0.4], ["end", 2], ["wait", 0.1]],
	"sig_then_chain": [["press", Vector2(0.5, 0.5)], ["wait", 0.3], ["wait", 0.2],
		["wait", 0.3], ["wait", 0.3], ["wait", 0.4], ["wait", 0.6]],
	"sig_starfall": [["wait", 0.0], ["press", Vector2(0.4, 0.7)], ["wait", 0.15],
		["wait", 0.4], ["wait", 0.25], ["wait", 0.3], ["wait", 0.5], ["end", 1], ["wait", 0.3]],
}
const DEMO_POSE_T := {"sig_end_once": 2.0, "sig_starfall": 2.0}


func _demo_sheets() -> void:
	for nm in DEMOS:
		var st := _stage(ZenSceneOps.path_of(nm))
		var canvas: ZenCanvas = st["canvas"]
		var sv: SubViewport = st["sv"]
		await get_tree().process_frame
		var t := float(DEMO_POSE_T.get(nm, 0.5))
		var bus: ZenSignalBus = canvas.bus()
		canvas.pose(t)
		var frames: Array = []
		for step in DEMOS[nm]:
			var arg: Variant = step[1]
			match String(step[0]):
				"press", "release", "move": canvas.pointer(String(step[0]), arg)
				"fire": bus.fire(String(arg))
				"end": bus.trigger("end", null, int(arg))
				"wait":
					bus.advance(float(arg))
					bus.set_process(false)
					canvas.pose(t)
					sv.render_target_update_mode = SubViewport.UPDATE_ONCE
					await RenderingServer.frame_post_draw
					frames.append(sv.get_texture().get_image())
			bus.set_process(false)
		_save_sheet(frames, nm)
		sv.queue_free()


## Frames in rows of three at 2x, with a 4px gutter.
func _save_sheet(frames: Array, nm: String) -> void:
	var fw: int = frames[0].get_width() * 2
	var fh: int = frames[0].get_height() * 2
	var cols := mini(3, frames.size())
	var rows := ceili(frames.size() / 3.0)
	var sheet := Image.create(cols * (fw + 4), rows * (fh + 4), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.4, 0.4, 0.4))
	for i in frames.size():
		var img: Image = frames[i]
		img.convert(Image.FORMAT_RGBA8)
		img.resize(fw, fh, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(img, Rect2i(0, 0, fw, fh), Vector2i((i % 3) * (fw + 4), (i / 3) * (fh + 4)))
	sheet.save_png("%s/demo_%s.png" % [OUT, nm])
