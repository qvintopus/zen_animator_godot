extends Node
##
## Phase 5 visual evidence. Signals never fire during an export (that is the
## purity guard), so the only way to SEE crumble and the cursor-anchored ripple
## is to fire one on a live canvas and save the frame.
##
## Writes exports/_signal_shots/*.png and exits.

const OUT := "res://exports/signal_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _crumble_strip()
	await _ripple_strip()
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
