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

enum View { GALLERY, PLAYING, OPTIONS, EXPORT, SHAPE_EDITOR }

## The left column is an accordion of these: one section open at a time, its
## header pinned above its own scrolling list.
enum Section { ANIMS, ASSETS }

const OPTIONS_SCENE := "res://tools/zen_options.tscn"
const EXPORT_SCENE := "res://tools/zen_export_dialog.tscn"
const SHAPE_EDITOR_SCENE := "res://tools/zen_shape_editor.tscn"

## Row 0 of the assets list: create a new asset.
const NEW_ASSET_ROW := "+ new asset..."

var _view: View = View.GALLERY
var _entries: Array = []            # [{path, name, canvas_data...}]
var _sel := 0
var _playing: ZenCanvas = null
var _sub: SubViewport = null
var _options: Control = null
var _export_dialog: Control = null
var _shape_editor: Control = null
var _section: Section = Section.ANIMS
## [{name, path}] from ZenAssets, sorted. Asset ROW i is _assets[i - 1]; row 0
## is NEW_ASSET_ROW.
var _assets: Array = []
var _sel_asset := 0
var _prev_view: View = View.GALLERY   # EXPORT returns here on close

## Names queued with Ctrl+E, in order. Duplicates allowed (chaining an
## animation twice is meaningful); capped at ZenExport.MAX_CHAIN.
var _export_queue: Array[String] = []

## How long a finished one-shot holds on its last frame before replaying.
const REPLAY_HOLD := 0.9
var _replay_hold := 0.0

@onready var _list: VBoxContainer = $Margin/Rows/Body/Left/ListScroll/List
@onready var _list_scroll: ScrollContainer = $Margin/Rows/Body/Left/ListScroll
@onready var _anim_header: Button = $Margin/Rows/Body/Left/AnimHeader
@onready var _asset_header: Button = $Margin/Rows/Body/Left/AssetHeader
@onready var _asset_scroll: ScrollContainer = $Margin/Rows/Body/Left/AssetScroll
@onready var _asset_list: VBoxContainer = $Margin/Rows/Body/Left/AssetScroll/AssetList
@onready var _asset_preview: ZenShapePreview = $Margin/Rows/Body/Right/AssetPreview
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

## Held H: every hotkey of the current screen. The footer shows only the
## essentials - one long legend Label widened the window past the screen.
var _help := ZenHotkeyHelp.new()


func _ready() -> void:
	ZenSettings.apply_startup()
	add_child(_help)
	_anim_header.pressed.connect(_set_section.bind(Section.ANIMS))
	_asset_header.pressed.connect(_set_section.bind(Section.ASSETS))
	_scan()
	_build_list()
	_scan_assets()
	_build_asset_list()
	_set_section(Section.ANIMS)
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

	var shapes: Array = []
	var kinds := {"text": 0, "shape": 0, "global": 0}
	var tracked := 0
	var keys := 0
	var eases := {}
	for e in c.elements():
		var el := e as ZenElement
		if el is ZenText: kinds["text"] += 1
		elif el is ZenShape:
			kinds["shape"] += 1
			var zs := el as ZenShape
			if zs.shape_kind == ZenShape.Kind.CUSTOM:
				var used: Array = [zs.shape_name, ZenAssets.name_of(zs.shape)]
				for r in zs.shape_refs: used.append(ZenAssets.name_of(r))
				for nm in used:
					if nm != "" and not shapes.has(nm): shapes.append(nm)
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
	info["shapes"] = shapes
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
	if _section == Section.ANIMS: _info.text = _render_info(_entries[_sel])
	_keep_visible(_list_scroll, _list, _sel)


## Scroll a list so row `i` is on screen. Deferred a frame: rows built this
## frame have no layout yet, and ensure_control_visible would aim at zero.
func _keep_visible(scroll: ScrollContainer, list: VBoxContainer, i: int) -> void:
	await get_tree().process_frame
	if i >= 0 and i < list.get_child_count():
		scroll.ensure_control_visible(list.get_child(i))


# ---------------------------------------------------------------- sections

## Open one section and collapse the other. Opening the assets while an
## animation plays stops it - the right pane belongs to the open section.
func _set_section(sec: Section) -> void:
	_section = sec
	var anims := sec == Section.ANIMS
	_anim_header.text = "%s animations (%d)" % ["▾" if anims else "▸", _entries.size()]
	_asset_header.text = "%s assets (visual) (%d)" % ["▸" if anims else "▾", _assets.size()]
	_list_scroll.visible = anims
	_asset_scroll.visible = not anims
	if _view == View.PLAYING and not anims:
		_stop()
	if _view in [View.GALLERY, View.PLAYING] and not (anims and _view == View.PLAYING):
		_show_gallery()
	if anims: _select(_sel)
	else: _select_asset(_sel_asset)


func _scan_assets() -> void:
	_assets.clear()
	var paths := ZenAssets.shape_paths()
	for nm in paths:
		_assets.append({"name": nm, "path": paths[nm]})


func _build_asset_list() -> void:
	for ch in _asset_list.get_children():
		_asset_list.remove_child(ch)
		ch.queue_free()
	var labels: Array = [NEW_ASSET_ROW]
	for a in _assets: labels.append(String(a["name"]))
	for i in labels.size():
		var b := Button.new()
		b.text = "  %s" % labels[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(_select_asset.bind(i))
		b.gui_input.connect(_on_asset_row_input.bind(i))
		_asset_list.add_child(b)


func _on_asset_row_input(ev: InputEvent, i: int) -> void:
	if not (ev is InputEventMouseButton): return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click: return
	_select_asset(i)
	_open_shape_editor()
	accept_event()


func _select_asset(i: int) -> void:
	_sel_asset = clampi(i, 0, _assets.size())
	for j in _asset_list.get_child_count():
		(_asset_list.get_child(j) as Button).button_pressed = j == _sel_asset
	_keep_visible(_asset_scroll, _asset_list, _sel_asset)
	if _section != Section.ASSETS: return
	if _sel_asset == 0:
		_asset_preview.shape = null
		_info.text = "[b][color=#e5c07b]new asset[/color][/b]\n\n" \
			+ "Press ENTER to create a pixel shape in the shape editor.\n\n" \
			+ "[color=#5c6370]A pixel shape is a grid of fill and outline cells with no colour " \
			+ "of its own: a custom shape element tints fill with its color track and " \
			+ "outline with its outline_color track, so both stay animatable.[/color]"
		return
	var a: Dictionary = _assets[_sel_asset - 1]
	var px := load(String(a["path"])) as ZenPixelShape
	_asset_preview.shape = px
	_info.text = _render_asset_info(a, px)


func _render_asset_info(a: Dictionary, px: ZenPixelShape) -> String:
	var nm := String(a["name"])
	var L: Array = []
	L.append("[b][color=#e5c07b]%s[/color][/b]" % nm)
	L.append("[color=#5c6370]%s[/color]" % String(a["path"]))
	L.append("")
	if px == null:
		L.append("[color=#e06c75]could not load[/color]")
		return "\n".join(L)
	L.append("[color=#61afef]kind[/color]  pixel shape")
	L.append("[color=#61afef]size[/color]  %d x %d cells" % [px.size.x, px.size.y])
	L.append("[color=#61afef]cells[/color]  %d fill, %d outline" % [
		px.count(ZenPixelShape.FILL), px.count(ZenPixelShape.OUTLINE)])
	var users: Array = []
	for e in _entries:
		if (e.get("shapes", []) as Array).has(nm): users.append(String(e["name"]))
	L.append("[color=#61afef]used by[/color]  %s" % (", ".join(users) if not users.is_empty()
			 else "[color=#5c6370]no animation[/color]"))
	L.append("    [color=#5c6370]press ENTER or double-click to edit[/color]")
	return "\n".join(L)


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
	_asset_preview.visible = _section == Section.ASSETS
	_title.text = "Zen Animator"
	if _section == Section.ASSETS:
		_status.text = "%d assets%s" % [_assets.size(), _queue_suffix()]
		_hint.text = ZenHotkeyHelp.footer([["zen_play", "edit"], ["zen_tab", "animations"],
				["zen_help", "(hold) all hotkeys"], ["zen_back", "quit"]])
		return
	_status.text = "%d animations%s" % [_entries.size(), _queue_suffix()]
	_hint.text = ZenHotkeyHelp.footer([["zen_play", "play"], ["zen_tab", "assets"],
			["zen_help", "(hold) all hotkeys"], ["zen_back", "quit"]])
	_status.text += "   " + _toggle_badges(null)


func _show_playing(nm: String) -> void:
	_view = View.PLAYING
	_stage.visible = true
	_info.visible = false
	_asset_preview.visible = false
	_title.text = nm
	# Only advertise the signal keys when there is something to fire.
	var n := _signal_count()
	var pairs: Array = [["zen_restart", "restart"]]
	if n == 1: pairs.append(["1", "fire signal"])
	elif n > 1: pairs.append(["1-%d" % n, "fire signal"])
	pairs.append_array([["zen_help", "(hold) all hotkeys"], ["zen_back", "back"]])
	_hint.text = ZenHotkeyHelp.footer(pairs)


func _signal_count() -> int:
	if _playing == null or _playing.bus() == null: return 0
	return _playing.bus().names().size()


## Every hotkey of the screen showing now, for the hold-H sheet.
func _show_help() -> void:
	var rows: Array = []
	if _view == View.PLAYING:
		rows.append(["zen_restart", "restart the animation"])
		var n := _signal_count()
		if n > 0: rows.append(["1" if n == 1 else "1-%d" % n, "fire signal (%s)" % ", ".join(_playing.bus().names())])
		rows.append_array([["click a row", "switch to that animation"],
			["zen_toggle_intro", "intro on / off"], ["zen_toggle_loop", "loop on / off"],
			["zen_tab", "switch to assets (stops playback)"],
			["zen_export", "export..."], ["zen_export_queue", "add to the export queue"],
			["zen_back", "back to the gallery"]])
		_help.show_rows(_title.text, rows)
		return
	if _section == Section.ASSETS:
		rows = [["zen_play", "edit the asset (row 1: new asset)"], ["double-click", "edit the asset"],
			["zen_prev", "previous"], ["zen_next", "next"], ["zen_tab", "switch to animations"],
			["zen_restart", "reload the lists"], ["zen_options", "options"], ["zen_back", "quit"]]
	else:
		rows = [["zen_play", "play"], ["double-click", "play"],
			["zen_prev", "previous"], ["zen_next", "next"], ["zen_tab", "switch to assets"],
			["zen_restart", "reload the lists"],
			["zen_toggle_intro", "intro on / off (now %s)" % ("on" if ZenSettings.play_intro() else "off")],
			["zen_toggle_loop", "loop on / off (now %s)" % ("on" if ZenSettings.play_loop() else "off")],
			["zen_options", "options"], ["zen_export", "export..."],
			["zen_export_queue", "add to the export queue"], ["zen_back", "quit"]]
	_help.show_rows("Gallery - " + ("assets" if _section == Section.ASSETS else "animations"), rows)


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
	if _section != Section.ANIMS: _set_section(Section.ANIMS)
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
		_scan_assets()
		_build_asset_list()
		_set_section(_section)
		_select(keep)
		_status.text = "%d animations, %d assets  [reloaded]" % [_entries.size(), _assets.size()]


## ESC backs out one level, then quits - the usual nesting, so it is never a
## surprise which one happens.
func _back() -> void:
	if _view == View.SHAPE_EDITOR:
		return          # the editor owns ESC (it may have unsaved changes)
	elif _view == View.OPTIONS:
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


## The shape editor: the same overlay-child pattern, on the selected asset
## (or a blank one for the "+ new asset" row). Closing it rescans the assets
## and selects whatever it last saved, so a new shape appears selected.
func _open_shape_editor() -> void:
	if _shape_editor != null: return
	_shape_editor = (load(SHAPE_EDITOR_SCENE) as PackedScene).instantiate()
	_shape_editor.closed.connect(_close_shape_editor)
	add_child(_shape_editor)
	var nm := "" if _sel_asset == 0 or _assets.is_empty() else String(_assets[_sel_asset - 1]["name"])
	_shape_editor.open(nm)
	_view = View.SHAPE_EDITOR


func _close_shape_editor() -> void:
	var nm := ""
	if _shape_editor != null:
		nm = _shape_editor.current_name()
		_shape_editor.queue_free()
		_shape_editor = null
	_view = View.GALLERY
	_scan_assets()
	_build_asset_list()
	var row := 0
	for i in _assets.size():
		if String(_assets[i]["name"]) == nm: row = i + 1
	_sel_asset = row
	# Animations may now draw a changed shape; their usage lists still hold.
	_set_section(Section.ASSETS)


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
	if ev.is_action_released("zen_help"):
		_help.visible = false
		return
	if ev.is_echo(): return
	if ev.is_action_pressed("zen_help"):
		if _view in [View.GALLERY, View.PLAYING]:
			_show_help()
			get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("zen_back"):
		_back()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_restart"):
		if _view in [View.GALLERY, View.PLAYING]:
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
	elif ev.is_action_pressed("zen_tab"):
		if _view in [View.GALLERY, View.PLAYING]:
			_set_section(Section.ASSETS if _section == Section.ANIMS else Section.ANIMS)
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
			if _section == Section.ASSETS: _open_shape_editor()
			else: _play(_sel)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_prev"):
		if _view == View.GALLERY:
			if _section == Section.ASSETS: _select_asset(_sel_asset - 1)
			else: _select(_sel - 1)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_next"):
		if _view == View.GALLERY:
			if _section == Section.ASSETS: _select_asset(_sel_asset + 1)
			else: _select(_sel + 1)
			get_viewport().set_input_as_handled()
	else:
		# zen_signal_1..9 fire the nth signal of the playing document.
		for i in range(9):
			if ev.is_action_pressed("zen_signal_%d" % (i + 1)):
				if _view == View.PLAYING:
					_fire(i)
					get_viewport().set_input_as_handled()
				break
