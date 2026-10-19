@tool
class_name ZenGallery
extends Control
##
## The project's main scene: a browser for every animation in `anims/`.
##
## WHY THIS EXISTS: the port had no front door. `project.godot` pointed F5 at
## `tools/export_scene.tscn`, which is a headless-ish batch tool that reads
## `--anim=` off the command line, so pressing F5 in the editor ran an exporter
## with no arguments. Opening a single animation meant finding its .tscn and
## pressing F6. This lists them, shows what each one actually CONTAINS, and
## plays them in place.
##
## It is deliberately a `Control` in a `CanvasLayer`-free scene while the
## animation itself is a `Node2D` in a `SubViewport`: Zen geometry is a fraction
## of a 320x180 design canvas, so an animation must NOT be laid out by Control
## anchors. Rendering it into a fixed-size SubViewport and showing that through
## a `TextureRect` keeps the composition exact at any window size - the same
## reason the exporter renders native and upscales afterwards.
##

## Where animations are found. Scanned at startup, so dropping a new .tscn in
## here makes it appear with no code change.
const ANIM_DIR := "res://anims"

## Scenes that are test fixtures rather than content. `mouse_ripple_hand` is the
## hand-built twin the importer is checked against (tools/compare_ripple.gd);
## listing both would show the same animation twice under near-identical names.
const HIDDEN := ["mouse_ripple_hand"]

enum View { GALLERY, PLAYING, OPTIONS, EXPORT }

const OPTIONS_SCENE := "res://tools/zen_options.tscn"
const EXPORT_SCENE := "res://tools/zen_export_dialog.tscn"

var _view: View = View.GALLERY
var _entries: Array = []            # [{path, name, canvas_data...}]
var _sel := 0
var _playing: ZenCanvas = null
var _sub: SubViewport = null
var _options: Control = null
var _export_dialog: Control = null
var _prev_view: View = View.GALLERY   # EXPORT returns here on close

## Names queued with Ctrl+E, in order. Duplicates allowed (chaining an
## animation twice is meaningful); capped at ZenExport.MAX_CHAIN.
var _export_queue: Array[String] = []

## How long a finished one-shot holds on its last frame before replaying.
const REPLAY_HOLD := 0.9
var _replay_hold := 0.0

@onready var _list: VBoxContainer = $Margin/Rows/Body/Left/ListScroll/List
@onready var _info: RichTextLabel = $Margin/Rows/Body/Right/Info
## The frame keeps the animation's aspect; the TextureRect inside it shows the
## SubViewport. Splitting the two is what stops a non-16:9 window from cropping
## the composition - Zen geometry is fractional, so a clipped stage silently
## hides elements rather than scaling them (the teal diagonals went first).
@onready var _stage: AspectRatioContainer = $Margin/Rows/Body/Right/Stage
@onready var _screen: TextureRect = $Margin/Rows/Body/Right/Stage/View
@onready var _title: Label = $Margin/Rows/Head/Title
@onready var _hint: Label = $Margin/Rows/Foot/Hint
@onready var _status: Label = $Margin/Rows/Head/Status


func _ready() -> void:
	ZenSettings.apply_startup()
	_scan()
	_build_list()
	_show_gallery()
	_select(0)


## Find every animation scene. Sorted so the order is stable across runs rather
## than filesystem-dependent.
func _scan() -> void:
	_entries.clear()
	var d := DirAccess.open(ANIM_DIR)
	if d == null:
		push_error("zen gallery: cannot open %s" % ANIM_DIR)
		return
	var names: Array = []
	for f in d.get_files():
		if not f.ends_with(".tscn"): continue
		var base := f.get_basename()
		if HIDDEN.has(base): continue
		names.append(base)
	names.sort()
	for base in names:
		_entries.append(_describe("%s/%s.tscn" % [ANIM_DIR, base], base))


## Read an animation's metadata WITHOUT playing it.
##
## The scene is instantiated and immediately freed: a PackedScene cannot be
## inspected for exported values any other way, and the alternative (parsing the
## .tscn text) would duplicate Godot's own format handling. `live_playback` is
## cleared first - this instance must never build a clock, it exists only to be
## measured. It is also never added to the tree, so _ready() does not run at all.
func _describe(path: String, base: String) -> Dictionary:
	var info := {"path": path, "name": base, "ok": false}
	var ps := load(path) as PackedScene
	if ps == null: return info
	var c := ps.instantiate() as ZenCanvas
	if c == null:
		if ps.instantiate() != null: ps.instantiate().free()
		return info
	c.live_playback = false

	var kinds := {"text": 0, "shape": 0, "global": 0}
	var tracked := 0
	var keys := 0
	var eases := {}
	for e in c.elements():
		var el := e as ZenElement
		if el is ZenText: kinds["text"] += 1
		elif el is ZenShape: kinds["shape"] += 1
		elif el is ZenGlobal: kinds["global"] += 1
		for prop in el.tracks:
			var arr: Array = el.tracks[prop]
			if arr.is_empty(): continue
			tracked += 1
			keys += arr.size()
			for k in arr:
				var en := String((k as Dictionary).get("ease", "linear"))
				eases[en] = int(eases.get(en, 0)) + 1

	var sig_names: Array = []
	for ch in c.get_children():
		if ch is ZenSignalBus:
			for sd in (ch as ZenSignalBus).signals_data:
				sig_names.append(String((sd as Dictionary).get("name", "?")))

	info["ok"] = true
	info["elements"] = c.elements().size()
	info["kinds"] = kinds
	info["tracks"] = tracked
	info["keys"] = keys
	info["eases"] = eases
	info["signals"] = sig_names
	info["duration"] = c.duration
	info["intro_end"] = c.intro_end
	info["outro_start"] = c.outro_start
	info["play_start"] = c.play_start()
	info["play_end"] = c.play_end()
	info["loop_smooth"] = c.loop_smooth
	info["loop_blend"] = c.loop_blend
	info["pauses"] = c.pauses.size()
	info["design"] = c.design_size
	info["clear"] = c.clear_color
	c.free()
	return info


func _build_list() -> void:
	for ch in _list.get_children(): ch.queue_free()
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var b := Button.new()
		b.text = "  %s" % String(e["name"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(_on_row.bind(i))
		# Double-click plays. `pressed` already fired for the first click, so
		# this only has to start playback - the row is selected by then.
		b.gui_input.connect(_on_row_input.bind(i))
		_list.add_child(b)


## A row click selects. While something is already playing it also SWITCHES to
## the clicked animation rather than stopping back to the metadata panel:
## clicking through a gallery is browsing, and dropping out of playback on every
## click (then needing R to start again) made it unusable.
func _on_row(i: int) -> void:
	var was_playing := _view == View.PLAYING
	_select(i)
	if was_playing:
		_play(i)


## Double-click anywhere on a row plays it, which is what a gallery is expected
## to do. Single click still just selects, so the metadata can be read without
## committing to playback.
func _on_row_input(ev: InputEvent, i: int) -> void:
	if not (ev is InputEventMouseButton): return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click: return
	_select(i)
	_play(i)
	accept_event()


func _select(i: int) -> void:
	if _entries.is_empty(): return
	_sel = clampi(i, 0, _entries.size() - 1)
	for j in _list.get_child_count():
		(_list.get_child(j) as Button).button_pressed = j == _sel
	_info.text = _render_info(_entries[_sel])


## The metadata panel. Everything here is read off the scene, so it describes
## the ACTUAL setup rather than a description that can drift from it.
func _render_info(e: Dictionary) -> String:
	if not bool(e.get("ok", false)):
		return "[color=#e06c75]could not read %s[/color]" % String(e.get("path", "?"))
	var L: Array = []
	L.append("[b][color=#e5c07b]%s[/color][/b]" % String(e["name"]))
	L.append("[color=#5c6370]%s[/color]" % String(e["path"]))
	L.append("")

	var d: Vector2 = e["design"]
	L.append("[color=#61afef]canvas[/color]  %d x %d" % [int(d.x), int(d.y)])

	# The clock. play_start/play_end are what actually RENDERS - the intro is
	# skipped on loops and the outro is never played at all - so both the raw
	# fields and the resolved section are shown; they differ in ways that
	# surprise people (pause_menu is mostly intro).
	L.append("[color=#61afef]duration[/color]  %.3fs" % float(e["duration"]))
	var ie: float = e["intro_end"]
	var os_: float = e["outro_start"]
	L.append("[color=#61afef]intro_end[/color]  %s" % ("%.3fs" % ie if ie > 0.0 else "[color=#5c6370]none[/color]"))
	L.append("[color=#61afef]outro_start[/color]  %s" % ("%.3fs" % os_ if os_ > 0.0 else "[color=#5c6370]unset[/color]"))
	L.append("[color=#61afef]plays[/color]  %.3f .. %.3fs  [color=#5c6370](%.3fs body)[/color]"
			 % [float(e["play_start"]), float(e["play_end"]),
				float(e["play_end"]) - float(e["play_start"])])
	L.append("[color=#61afef]loop[/color]  %s" % ("smooth, %.2fs blend" % float(e["loop_blend"])
			 if bool(e["loop_smooth"]) else "[color=#5c6370]one-shot[/color]"))
	L.append("")

	var k: Dictionary = e["kinds"]
	var parts: Array = []
	for nm in ["text", "shape", "global"]:
		if int(k[nm]) > 0: parts.append("%d %s" % [int(k[nm]), nm])
	L.append("[color=#61afef]elements[/color]  %d  [color=#5c6370](%s)[/color]"
			 % [int(e["elements"]), ", ".join(parts) if not parts.is_empty() else "-"])
	L.append("[color=#61afef]tracks[/color]  %d animated, %d keys"
			 % [int(e["tracks"]), int(e["keys"])])

	# Which easings this document actually uses - the thing that changed when
	# the project moved onto Godot's Tween family, and so worth seeing per-scene.
	var es: Dictionary = e["eases"]
	var ek: Array = es.keys()
	ek.sort_custom(func(a, b): return int(es[a]) > int(es[b]))
	var ep: Array = []
	for nm in ek: ep.append("%s x%d" % [nm, int(es[nm])])
	L.append("[color=#61afef]easings[/color]  %s" % (", ".join(ep) if not ep.is_empty() else "-"))

	# Signals are invisible in an export (the exporter sets every bus inert so a
	# frame stays a pure function of (scene, t)), so listing them here is the
	# only place their existence shows up outside the code.
	var sg: Array = e["signals"]
	if sg.is_empty():
		L.append("[color=#61afef]signals[/color]  [color=#5c6370]none[/color]")
	else:
		L.append("[color=#61afef]signals[/color]  %s" % ", ".join(sg))
		var how := "press 1 while playing to fire" if sg.size() == 1 \
				   else "press 1-%d while playing to fire" % sg.size()
		L.append("    [color=#5c6370]%s[/color]" % how)
	return "\n".join(L)


# ---------------------------------------------------------------- views

func _show_gallery() -> void:
	_view = View.GALLERY
	_stage.visible = false
	_info.visible = true
	_title.text = "Zen Animator"
	_status.text = "%d animations%s" % [_entries.size(), _queue_suffix()]
	_hint.text = "  ENTER / double-click  play      UP/DOWN  select      R  reload" \
			   + "      I  intro      L  loop      O  options      E  export      Ctrl+E  queue      ESC  quit"
	_status.text += "   " + _toggle_badges(null)


func _show_playing(nm: String) -> void:
	_view = View.PLAYING
	_stage.visible = true
	_info.visible = false
	_title.text = nm
	# Only advertise the signal keys when there is something to fire.
	var n := 0
	if _playing != null and _playing.bus() != null: n = _playing.bus().names().size()
	var sig := ""
	if n == 1: sig = "      1  fire signal"
	elif n > 1: sig = "      1-%d  fire signal" % n
	_hint.text = "  R  restart      I  intro      L  loop      E  export      Ctrl+E  queue      ESC  back to gallery%s" % sig


## The I / L state as a compact badge pair. With a canvas, a toggle that does
## not apply to it says so instead of claiming an effect it cannot have.
func _toggle_badges(c: ZenCanvas) -> String:
	var intro := "INTRO %s" % ("on" if ZenSettings.play_intro() else "off")
	var loop := "LOOP %s" % ("on" if ZenSettings.play_loop() else "off")
	if c != null:
		if not c.has_intro(): intro = "INTRO n/a"
		if not c.loop_play and ZenSettings.play_loop(): loop = "LOOP replay"
	return "[%s]  [%s]" % [intro, loop]


func _queue_suffix() -> String:
	return "   [queued: %d]" % _export_queue.size() if not _export_queue.is_empty() else ""


# ---------------------------------------------------------------- playing

## Instantiate and run the selected animation inside a SubViewport.
##
## The viewport is sized to the animation's own design canvas and shown through
## a TextureRect with nearest-neighbour filtering, so the pixel grid stays
## honest at any window size. Stretching it with a Control layout instead would
## reposition every element, because Zen geometry is fractional.
func _play(i: int) -> void:
	_stop()
	var e: Dictionary = _entries[i]
	if not bool(e.get("ok", false)): return
	var ps := load(String(e["path"])) as PackedScene
	if ps == null: return
	_playing = ps.instantiate() as ZenCanvas
	if _playing == null: return
	# Viewer overrides go on BEFORE the canvas enters the tree: its _ready()
	# builds and starts the AnimationPlayer with them.
	_playing.play_intro = ZenSettings.play_intro()
	_playing.play_loop = ZenSettings.play_loop()

	_sub = SubViewport.new()
	_sub.size = Vector2i(_playing.design_size)
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The canvas paints no background of its own unless a `global` element does,
	# so the document's clear_color goes behind it - the same thing the exporter
	# does for a non-transparent render.
	var bg := ColorRect.new()
	bg.size = _playing.design_size
	bg.color = _playing.clear_color
	_sub.add_child(bg)
	_sub.add_child(_playing)
	add_child(_sub)

	_screen.texture = _sub.get_texture()
	# Match the frame to THIS document's canvas, not a hard-coded 16:9.
	_stage.ratio = _playing.design_size.x / maxf(_playing.design_size.y, 1.0)
	_replay_hold = 0.0
	_show_playing(String(e["name"]))
	_update_status()


func _stop() -> void:
	if _sub != null:
		_sub.queue_free()
		_sub = null
	_playing = null
	_screen.texture = null


## R restarts. In the gallery it re-scans instead, so a scene edited in another
## window shows up without leaving the app.
func _restart() -> void:
	if _view == View.PLAYING:
		_play(_sel)
	else:
		var keep := _sel
		_scan()
		_build_list()
		_select(keep)
		_status.text = "%d animations  [reloaded]" % _entries.size()


## ESC backs out one level, then quits - the usual nesting, so it is never a
## surprise which one happens.
func _back() -> void:
	if _view == View.OPTIONS:
		_close_options()
	elif _view == View.EXPORT:
		_close_export()
	elif _view == View.PLAYING:
		_stop()
		_show_gallery()
		_select(_sel)
	else:
		get_tree().quit()


## Options is an overlay on top of the gallery, not a scene change - a scene
## change would re-run _ready() and lose the current selection for no reason,
## since nothing here needs a fresh SceneTree.
func _open_options() -> void:
	if _options != null: return
	_options = (load(OPTIONS_SCENE) as PackedScene).instantiate()
	_options.closed.connect(_close_options)
	add_child(_options)
	_view = View.OPTIONS


func _close_options() -> void:
	if _options != null:
		_options.queue_free()
		_options = null
	_view = View.GALLERY


## Export is the same overlay-child pattern as Options - opening it from
## PLAYING leaves playback running underneath, so closing it returns there
## rather than always falling back to the gallery.
func _open_export() -> void:
	if _export_dialog != null: return
	_export_dialog = (load(EXPORT_SCENE) as PackedScene).instantiate()
	_export_dialog.closed.connect(_close_export)
	add_child(_export_dialog)
	var chain: Array = _export_queue.duplicate()
	if chain.is_empty():
		var current := _playing.scene_file_path.get_file().get_basename() \
					   if _playing != null else String(_entries[_sel].get("name", ""))
		if current != "": chain = [current]
	_prev_view = _view if _view in [View.GALLERY, View.PLAYING] else View.GALLERY
	_export_dialog.open(_entries, chain)
	_view = View.EXPORT


func _close_export() -> void:
	if _export_dialog != null:
		_export_queue = _export_dialog.get_chain()
		if _export_dialog.exported_ok():
			_export_queue.clear()
		_export_dialog.queue_free()
		_export_dialog = null
	_view = _prev_view
	if _view == View.GALLERY: _show_gallery()
	elif _view == View.PLAYING: _show_playing(_title.text)


## Ctrl+E: tag the current selection (gallery) or the playing animation onto
## the export queue without opening the dialog. Refuses a design_size that
## does not match the chain's first link - letterbox/stretch are both wrong,
## so mixing sizes is refused rather than guessed at (ZenExport.plan_chain
## enforces the same rule when the chain actually runs).
func _queue_current() -> void:
	var nm := _playing.scene_file_path.get_file().get_basename() \
			  if _view == View.PLAYING and _playing != null \
			  else String(_entries[_sel].get("name", "")) if not _entries.is_empty() else ""
	if nm == "": return
	var entry := {}
	for e in _entries:
		if String(e.get("name", "")) == nm: entry = e; break
	if entry.is_empty() or not bool(entry.get("ok", false)): return

	if _export_queue.size() >= ZenExport.MAX_CHAIN:
		_status.text = "queue is full (%d max)" % ZenExport.MAX_CHAIN
		return
	if not _export_queue.is_empty():
		var first := {}
		for e in _entries:
			if String(e.get("name", "")) == _export_queue[0]: first = e; break
		var fd: Vector2 = first.get("design", Vector2.ZERO)
		var d: Vector2 = entry["design"]
		if d != fd:
			_status.text = "cannot queue %s: %dx%d canvas, queue is %dx%d" % [
				nm, int(d.x), int(d.y), int(fd.x), int(fd.y)]
			return

	_export_queue.append(nm)
	_status.text = "queued %s  [queued: %d]" % [nm, _export_queue.size()]


## Fire a signal by number while playing. This is the only interactive way to
## see one: an export never fires a signal, by design.
func _fire(n: int) -> void:
	if _playing == null: return
	var bus := _playing.bus()
	if bus == null: return
	var names: Array = bus.names()
	if n < 0 or n >= names.size(): return
	bus.fire(String(names[n]))
	_status.text = "fired  %s" % String(names[n])


func _process(_dt: float) -> void:
	if _view == View.PLAYING: _update_status()


func _update_status() -> void:
	if _playing == null: return
	var ap := _playing.animation_player()
	var t: float = _playing.pose_time
	var tot: float = _playing.play_end()
	var bus := _playing.bus()
	var extra := ""
	if bus != null and bus.is_running(): extra = "   [signal]"
	elif bus != null and bus.is_holding(): extra = "   [signal end]"
	elif _playing.held_pause >= 0: extra = "   [paused]"

	# A one-shot pauses on its last frame (ZenCanvas._process), which in a
	# GALLERY reads as "broken" rather than "finished" - the previous behaviour
	# left it frozen until R was pressed. Loop it here instead, after a short
	# hold so the final pose is actually seen.
	#
	# Deliberately in the gallery and not in ZenCanvas: an export must never
	# loop a one-shot, and neither should a game that plays one deliberately.
	# This is a browsing affordance, so it belongs to the browser.
	#
	# A terminal signal ends the same way: its end pose is held (the bus keeps
	# it, not the timeline pose underneath), then the whole animation restarts.
	# With LOOP off nothing replays - the last frame simply stays.
	if ap != null and _playing.is_finished():
		_replay_hold += get_process_delta_time()
		if extra == "": extra = "   [ended]"
		if ZenSettings.play_loop() and _replay_hold >= REPLAY_HOLD:
			_replay_hold = 0.0
			_play(_sel)
			return
	else:
		_replay_hold = 0.0
	_status.text = "t %.2f / %.2fs%s   %s%s" % [t, tot, extra, _toggle_badges(_playing), _queue_suffix()]


## I / L: flip a viewer toggle, persist it, and restart what is playing so
## the change shows at once instead of on the next cycle.
func _toggle(which: String) -> void:
	if which == "intro": ZenSettings.set_play_intro(not ZenSettings.play_intro())
	else: ZenSettings.set_play_loop(not ZenSettings.play_loop())
	if _view == View.PLAYING: _play(_sel)
	else: _show_gallery()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_echo(): return
	if ev.is_action_pressed("zen_back"):
		_back()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_restart"):
		if _view != View.OPTIONS:
			_restart()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_options"):
		if _view == View.GALLERY:
			_open_options()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_export_queue"):
		if _view in [View.GALLERY, View.PLAYING]:
			_queue_current()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_export") \
		 and not (ev is InputEventKey and (ev as InputEventKey).ctrl_pressed):
		if _view in [View.GALLERY, View.PLAYING]:
			_open_export()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_toggle_intro"):
		if _view in [View.GALLERY, View.PLAYING]:
			_toggle("intro")
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_toggle_loop"):
		if _view in [View.GALLERY, View.PLAYING]:
			_toggle("loop")
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_play"):
		if _view == View.GALLERY:
			_play(_sel)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_prev"):
		if _view == View.GALLERY:
			_select(_sel - 1)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_next"):
		if _view == View.GALLERY:
			_select(_sel + 1)
			get_viewport().set_input_as_handled()
	else:
		# zen_signal_1..9 fire the nth signal of the playing document.
		for i in range(9):
			if ev.is_action_pressed("zen_signal_%d" % (i + 1)):
				if _view == View.PLAYING:
					_fire(i)
					get_viewport().set_input_as_handled()
				break
