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

## Where animations are found: res://anims, plus user://anims for scenes an
## exported build saved (ZenSceneOps.DIRS), each with one level of folders.
## Scanned at startup, so dropping a new .tscn in makes it appear with no code
## change.
const ANIM_DIR := "res://anims"

enum View { GALLERY, PLAYING, OPTIONS, EXPORT, SHAPE_EDITOR, SCENE_EDITOR }

## The left column is an accordion of these: one section open at a time, its
## header pinned above its own scrolling list.
enum Section { ANIMS, ASSETS }

const OPTIONS_SCENE := "res://tools/zen_options.tscn"
const EXPORT_SCENE := "res://tools/zen_export_dialog.tscn"
const SHAPE_EDITOR_SCENE := "res://tools/zen_shape_editor.tscn"
const SCENE_EDITOR_SCENE := "res://tools/zen_scene_editor.tscn"

## Row 0 of the assets list: create a new asset.
const NEW_ASSET_ROW := "+ new asset..."

var _view: View = View.GALLERY
var _entries: Array = []            # [{path, name, folder, canvas_data...}]
## What the animations list shows, one per row: {folder, open, count} for a
## folder header, {entry} (an index into _entries) for an animation. Rows
## change with folding and the search; _entries does not.
var _rows: Array = []
## Every folder (ZenSceneOps.folders), and the ones shown expanded.
var _folders: Array = []
var _open := {}
var _sel := 0                       # the cursor ROW; mirrors _anim_sel.cursor
## Shift/Ctrl multi-selection of animations (delete, export as a chain).
var _anim_sel := ZenListSelection.new()
var _playing: ZenCanvas = null
## The entry being played, so a replay or restart survives the list changing.
var _playing_entry: Dictionary = {}
var _sub: SubViewport = null
var _options: Control = null
var _export_dialog: Control = null
var _shape_editor: Control = null
var _scene_editor: Control = null
## The name prompt for rename / duplicate; `_name_action` runs with the name.
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label
var _name_action := Callable()
## (raw text) -> [ok, message]: what the open prompt accepts.
var _name_check := Callable()
var _section: Section = Section.ANIMS
## [{name, path}] from ZenAssets, sorted. Asset ROW i is _assets[i - 1]; row 0
## is NEW_ASSET_ROW.
var _assets: Array = []
var _sel_asset := 0                 # mirrors _asset_sel.cursor
## Row 0 ("+ new asset") is a command, so it is never marked.
var _asset_sel := ZenListSelection.new(1)
## Delete confirmation; `_confirm_action` runs on OK.
var _confirm: ConfirmationDialog
var _confirm_action := Callable()
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
@onready var _search: LineEdit = $Margin/Rows/Body/Left/Search
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
## The top bar: what can be done with the selection (or the playing
## animation) on the left, the always-there switches on the right.
@onready var _bar: HBoxContainer = $Margin/Rows/Bar
@onready var _bar_context: HBoxContainer = $Margin/Rows/Bar/Context
@onready var _bar_global: HBoxContainer = $Margin/Rows/Bar/Global
## The right-click menu of rows and of the playing stage.
var _menu: PopupMenu

## H: every hotkey of the gallery. The footer shows only the
## essentials - one long legend Label widened the window past the screen.
var _help := ZenHotkeyHelp.new()


func _ready() -> void:
	ZenSettings.apply_startup()
	add_child(_help)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete"
	_confirm.ok_button_text = "Move to trash"
	_confirm.confirmed.connect(func(): if _confirm_action.is_valid(): _confirm_action.call())
	add_child(_confirm)
	_build_name_dialog()
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(ZenUI.menu_pressed.bind(_menu))
	add_child(_menu)
	# A click on the playing animation continues it from a pause marker, like
	# SPACE (zen_continue).
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.gui_input.connect(_on_screen_input)
	_anim_header.pressed.connect(_set_section.bind(Section.ANIMS))
	_asset_header.pressed.connect(_set_section.bind(Section.ASSETS))
	_search.text_changed.connect(func(_t): _on_search_changed())
	_search.text_submitted.connect(func(_t): _on_search_submitted())
	for f in ZenSettings.open_folders(): _open[String(f)] = true
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
	var paths := ZenSceneOps.scene_paths()
	var names: Array = paths.keys()
	names.sort()
	for base in names:
		_entries.append(_describe(String(paths[base]), base))
	_folders = ZenSceneOps.folders()


## Read an animation's metadata WITHOUT playing it.
##
## The scene is instantiated and immediately freed: a PackedScene cannot be
## inspected for exported values any other way, and the alternative (parsing the
## .tscn text) would duplicate Godot's own format handling. `live_playback` is
## cleared first - this instance must never build a clock, it exists only to be
## measured. It is also never added to the tree, so _ready() does not run at all.
func _describe(path: String, base: String) -> Dictionary:
	var info := {"path": path, "name": base, "folder": ZenSceneOps.folder_of_path(path), "ok": false}
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

	# Keys are read from the scene's own AnimationPlayer: what is listed here is
	# what plays. Method tracks (the pose callback) are not "animated props".
	var tl := c.timeline()
	tracked = tl.paths().size()
	keys = tl.key_count()

	var sig_names: Array = []
	for ch in c.get_children():
		if ch is ZenSignalBus:
			for sd in (ch as ZenSignalBus).signals_data:
				sig_names.append(_signal_label(ZenSignalData.normalize((sd as Dictionary).duplicate(true))))

	info["ok"] = true
	info["elements"] = c.elements().size()
	info["kinds"] = kinds
	info["tracks"] = tracked
	info["keys"] = keys
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
	_rows = list_rows(_entries, _folders, _open, _search.text)
	ZenUI.fill_list(_list, _rows.map(_row_label), _on_row, _on_row_double, _on_row_context)
	for i in _rows.size():
		if _rows[i].has("folder"):
			(_list.get_child(i) as Button).add_theme_color_override("font_color", ZenUI.LABEL)
	_anim_sel.resize(_rows.size())
	_update_anim_header()


## The rows of the animations list: each folder (A-Z) with its animations
## under it when open, then the top-level animations. A search (`query`,
## ZenSceneOps.filter) hides what does not match and opens every folder that
## holds a match, without touching which folders `open` remembers.
static func list_rows(entries: Array, folders: Array, open: Dictionary, query: String) -> Array:
	var searching := not query.strip_edges().is_empty()
	var by_folder := {}
	for i in ZenSceneOps.filter(entries, query):
		var f := String((entries[i] as Dictionary).get("folder", ""))
		if not by_folder.has(f): by_folder[f] = []
		(by_folder[f] as Array).append(i)
	var all_folders := folders.duplicate()
	for f in by_folder:
		if f != "" and not all_folders.has(f): all_folders.append(f)
	var rows: Array = []
	for f in all_folders:
		var kids: Array = by_folder.get(f, [])
		if searching and kids.is_empty(): continue
		var is_open := searching or open.has(f)
		rows.append({"folder": String(f), "open": is_open, "count": kids.size()})
		if is_open:
			for i in kids: rows.append({"entry": i, "in": String(f)})
	for i in by_folder.get("", []): rows.append({"entry": i})
	return rows


func _row_label(r: Dictionary) -> String:
	if r.has("folder"):
		return "%s %s  (%d)" % ["▾" if bool(r["open"]) else "▸", String(r["folder"]), int(r["count"])]
	var nm := String(_entries[int(r["entry"])]["name"])
	return ("   " + nm) if r.has("in") else nm


## The entry on list row `row`; {} for a folder row (or no such row).
func _entry_at(row: int) -> Dictionary:
	if row < 0 or row >= _rows.size() or not _rows[row].has("entry"): return {}
	return _entries[int(_rows[row]["entry"])]


func _cur_entry() -> Dictionary:
	return _entry_at(_sel)


## The folder of the cursor row: a folder header's own, or the folder the
## animation under the cursor sits in ("" at the top level).
func _cur_folder() -> String:
	if _sel < 0 or _sel >= _rows.size(): return ""
	var r: Dictionary = _rows[_sel]
	if r.has("folder"): return String(r["folder"])
	return String(_cur_entry().get("folder", ""))


func _folder_row(row: int) -> String:
	if row < 0 or row >= _rows.size() or not _rows[row].has("folder"): return ""
	return String(_rows[row]["folder"])


func _row_of(nm: String) -> int:
	for i in _rows.size():
		if not nm.is_empty() and String(_entry_at(i).get("name", "")) == nm: return i
	return -1


func _row_of_folder(f: String) -> int:
	for i in _rows.size():
		if _folder_row(i) == f: return i
	return -1


func _update_anim_header() -> void:
	var anims := _section == Section.ANIMS
	var n := _entries.size()
	var count := "%d" % n
	if not _search.text.strip_edges().is_empty():
		count = "%d of %d" % [ZenSceneOps.filter(_entries, _search.text).size(), n]
	_anim_header.text = "%s animations (%s)" % ["▾" if anims else "▸", count]


## A row click selects. While something is already playing it also SWITCHES to
## the clicked animation rather than stopping back to the metadata panel:
## clicking through a gallery is browsing, and dropping out of playback on every
## click (then needing R to start again) made it unusable.
##
## Shift+click extends the selection and Ctrl+click toggles a row; neither
## switches playback - they are gathering rows to delete or export.
func _on_row(i: int) -> void:
	var m := ZenUI.held_modifiers()
	var was_playing := _view == View.PLAYING
	_select(i, m["shift"], m["ctrl"])
	if was_playing and not (m["shift"] or m["ctrl"]) and not _entry_at(i).is_empty():
		_play(i)


## Double-click anywhere on a row plays it, which is what a gallery is expected
## to do. Single click still just selects, so the metadata can be read without
## committing to playback.
## On a folder row it folds or unfolds the folder instead.
func _on_row_double(i: int) -> void:
	_select(i)
	if _entry_at(i).is_empty(): _toggle_folder(_folder_row(i))
	else: _play(i)


## Folder rows can hold the cursor but are never marked: a selection is of
## animations, so a range across a folder header simply skips it.
func _select(i: int, shift := false, ctrl := false) -> void:
	if _rows.is_empty():
		_refresh_anim_selection()
		return
	_anim_sel.resize(_rows.size())
	_anim_sel.pick(i, shift, ctrl)
	for r in _anim_sel.marks.keys():
		if _entry_at(int(r)).is_empty(): _anim_sel.marks.erase(r)
	_refresh_anim_selection()


## Redraw the animations selection without changing it.
func _refresh_anim_selection() -> void:
	if _rows.is_empty():
		if _section == Section.ANIMS:
			_info.text = "[color=#5c6370]no animation matches[/color]"
			if _view == View.GALLERY: _refresh_bar()
		return
	_anim_sel.resize(_rows.size())
	_sel = _anim_sel.cursor
	ZenUI.show_selection(_list, _anim_sel)
	if _section == Section.ANIMS:
		if _anim_sel.is_multi(): _info.text = _render_multi_info()
		elif _cur_entry().is_empty(): _info.text = _render_folder_info(_folder_row(_sel))
		else: _info.text = _render_info(_cur_entry())
		if _view == View.GALLERY:
			_hint.text = _gallery_hint()
			_refresh_bar()
	ZenUI.scroll_to(_list_scroll, _list, _sel)


## The marked animations' names, in list order. With nothing marked (the
## cursor on a folder) it is empty.
func _marked_anims() -> Array[String]:
	var out: Array[String] = []
	for r in _anim_sel.rows():
		var e := _entry_at(r)
		if not e.is_empty(): out.append(String(e["name"]))
	return out


# ---------------------------------------------------------------- folders

## Fold or unfold folder `f`, remembered across runs. The cursor stays on
## the folder's row. A search shows every matching folder open, so folding
## then waits for the search to clear.
func _toggle_folder(f: String, open := -1) -> void:
	if f.is_empty(): return
	var now := open == 1 or (open == -1 and not _open.has(f))
	if now: _open[f] = true
	else: _open.erase(f)
	ZenSettings.set_open_folders(_open.keys())
	_build_list()
	_select(maxi(_row_of_folder(f), 0))


## LEFT on an animation inside a folder folds that folder, cursor on it.
func _fold_cursor(open: bool) -> void:
	var f := _cur_folder()
	if not f.is_empty(): _toggle_folder(f, 1 if open else 0)


func _render_folder_info(f: String) -> String:
	var names: Array = []
	for e in _entries:
		if String(e.get("folder", "")) == f: names.append(String(e["name"]))
	var L: Array = []
	L.append("[b][color=#e5c07b]%s[/color][/b]  [color=#5c6370]folder[/color]" % f)
	for root in ZenSceneOps.DIRS:
		if DirAccess.dir_exists_absolute("%s/%s" % [root, f]):
			L.append("[color=#5c6370]%s/%s[/color]" % [root, f])
	L.append("")
	L.append("[color=#61afef]animations[/color]  %s" % (str(names.size()) if not names.is_empty()
			 else "[color=#5c6370]none - %s moves animations here[/color]" % ZenHotkeyHelp.key("zen_move")))
	for nm in names: L.append("  " + nm)
	L.append("")
	L.append("    [color=#5c6370]%s or %s / %s to open or close, %s rename, %s trash it (when empty)[/color]"
			 % [ZenHotkeyHelp.key("zen_play"), ZenHotkeyHelp.key("zen_fold"),
				ZenHotkeyHelp.key("zen_unfold"), ZenHotkeyHelp.key("zen_rename"),
				ZenHotkeyHelp.key("zen_delete")])
	return "\n".join(L)


# ---------------------------------------------------------------- search

## Typing narrows the list at once, like the font search in Options. The
## cursor stays on the same animation while it still matches, else it lands
## on the first match.
func _on_search_changed() -> void:
	var keep := String(_cur_entry().get("name", ""))
	_build_list()
	var row := _row_of(keep)
	if row < 0:
		for i in _rows.size():
			if not _entry_at(i).is_empty(): row = i; break
	_select(maxi(row, 0))


## ENTER in the search plays the match under the cursor and hands the keys
## back to the gallery, so 1-9 fire signals rather than typing digits.
func _on_search_submitted() -> void:
	_search.release_focus()
	if not _cur_entry().is_empty(): _play(_sel)
	elif not _rows.is_empty(): _toggle_folder(_folder_row(_sel))


func _focus_search() -> void:
	if _section != Section.ANIMS: _set_section(Section.ANIMS)
	_search.grab_focus()
	_search.select_all()


## _input, not _unhandled_input: the focused search field would swallow the
## arrows and ESC before they got there (the same reason as ZenOptions).
func _input(ev: InputEvent) -> void:
	if not _search.has_focus() or not (ev is InputEventKey) or not ev.is_pressed(): return
	if ev.is_action_pressed("zen_back") and not ev.is_echo():
		if _search.text != "":
			_search.clear()
			_on_search_changed()
		else:
			_search.release_focus()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_prev", true):
		_select(_sel - 1, (ev as InputEventKey).shift_pressed)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_next", true):
		_select(_sel + 1, (ev as InputEventKey).shift_pressed)
		get_viewport().set_input_as_handled()


## The marked assets' names, in list order.
func _marked_assets() -> Array[String]:
	var out: Array[String] = []
	for r in _asset_sel.rows(): out.append(String(_assets[r - 1]["name"]))
	return out


# ---------------------------------------------------------------- sections

## Open one section and collapse the other. Opening the assets while an
## animation plays stops it - the right pane belongs to the open section.
func _set_section(sec: Section) -> void:
	_section = sec
	var anims := sec == Section.ANIMS
	_update_anim_header()
	_search.visible = anims
	if not anims: _search.release_focus()
	_asset_header.text = "%s assets (visual) (%d)" % ["▸" if anims else "▾", _assets.size()]
	_list_scroll.visible = anims
	_asset_scroll.visible = not anims
	if _view == View.PLAYING and not anims:
		_stop()
	if _view in [View.GALLERY, View.PLAYING] and not (anims and _view == View.PLAYING):
		_show_gallery()
	# Switching sections keeps each section's selection.
	if anims: _refresh_anim_selection()
	else: _refresh_asset_selection()


func _scan_assets() -> void:
	_assets.clear()
	var paths := ZenAssets.shape_paths()
	for nm in paths:
		_assets.append({"name": nm, "path": paths[nm]})


func _build_asset_list() -> void:
	var labels: Array = [NEW_ASSET_ROW]
	for a in _assets: labels.append(String(a["name"]))
	ZenUI.fill_list(_asset_list, labels, _on_asset_row, _on_asset_double, _on_asset_context)


func _on_asset_row(i: int) -> void:
	var m := ZenUI.held_modifiers()
	_select_asset(i, m["shift"], m["ctrl"])


func _on_asset_double(i: int) -> void:
	_select_asset(i)
	_open_shape_editor()


func _select_asset(i: int, shift := false, ctrl := false) -> void:
	_asset_sel.resize(_assets.size() + 1)
	_asset_sel.pick(i, shift, ctrl)
	_refresh_asset_selection()


func _refresh_asset_selection() -> void:
	_asset_sel.resize(_assets.size() + 1)
	_sel_asset = _asset_sel.cursor
	ZenUI.show_selection(_asset_list, _asset_sel)
	ZenUI.scroll_to(_asset_scroll, _asset_list, _sel_asset)
	if _section != Section.ASSETS: return
	if _view == View.GALLERY:
		_hint.text = _gallery_hint()
		_refresh_bar()
	if _asset_sel.is_multi():
		_asset_preview.shape = null
		_info.text = _render_multi_asset_info()
		return
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
	var users := _users_of(nm)
	L.append("[color=#61afef]used by[/color]  %s" % (", ".join(users) if not users.is_empty()
			 else "[color=#5c6370]no animation[/color]"))
	L.append("    [color=#5c6370]press ENTER or double-click to edit[/color]")
	return "\n".join(L)


## The animations whose scenes draw shape `nm`.
func _users_of(nm: String) -> Array:
	var users: Array = []
	for e in _entries:
		if (e.get("shapes", []) as Array).has(nm): users.append(String(e["name"]))
	return users


func _render_multi_info() -> String:
	var names := _marked_anims()
	var L: Array = ["[b][color=#e5c07b]%d animations selected[/color][/b]" % names.size(), ""]
	var sizes := {}
	for r in _anim_sel.rows():
		var e := _entry_at(r)
		var d: Vector2 = e.get("design", Vector2.ZERO)
		sizes[d] = true
		L.append("  %s  [color=#5c6370]%d x %d, %.2fs[/color]" % [String(e["name"]),
				 int(d.x), int(d.y), float(e.get("play_end", 0.0)) - float(e.get("play_start", 0.0))])
	L.append("")
	L.append("[color=#61afef]%s[/color]  export them as one chain, in this order" % ZenHotkeyHelp.key("zen_export"))
	if names.size() > ZenExport.MAX_CHAIN:
		L.append("    [color=#e06c75]a chain holds %d at most - the first %d are used[/color]"
				 % [ZenExport.MAX_CHAIN, ZenExport.MAX_CHAIN])
	if sizes.size() > 1:
		L.append("    [color=#e06c75]canvas sizes differ - a chain needs one size[/color]")
	L.append("[color=#61afef]%s[/color]  move them to the trash" % ZenHotkeyHelp.key("zen_delete"))
	return "\n".join(L)


func _render_multi_asset_info() -> String:
	var names := _marked_assets()
	var L: Array = ["[b][color=#e5c07b]%d assets selected[/color][/b]" % names.size(), ""]
	for nm in names:
		var users := _users_of(nm)
		L.append("  %s%s" % [nm, "" if users.is_empty()
				 else "  [color=#e06c75]used by %s[/color]" % ", ".join(users)])
	L.append("")
	L.append("[color=#61afef]%s[/color]  move them to the trash" % ZenHotkeyHelp.key("zen_delete"))
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
	L.append("[color=#61afef]tracks[/color]  %d in the AnimationPlayer, %d keys"
			 % [int(e["tracks"]), int(e["keys"])])
	L.append("    [color=#5c6370]%s to edit, %s for a new animation[/color]"
			 % [ZenHotkeyHelp.key("zen_edit_scene"), ZenHotkeyHelp.key("zen_new")])


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


# ---------------------------------------------------------------- actions
#
# What can be done right now, as ZenUI actions. The top bar and the
# right-click menus both read these, and every one calls the same function
# its hotkey does, so the mouse never reaches something the keys cannot.

static func _act(label: String, fn: Callable, key := "", enabled := true, tip := "", note := "") -> Dictionary:
	return {"label": label, "fn": fn, "key": key, "enabled": enabled, "tip": tip, "note": note}


## The top bar's left half: the selection's (or the playing animation's)
## actions.
func _actions() -> Array:
	if _view == View.PLAYING: return _playing_actions()
	if _section == Section.ASSETS: return _asset_actions()
	if _rows.is_empty(): return []
	if _anim_sel.is_multi(): return _multi_actions()
	if _cur_entry().is_empty(): return _folder_actions(_folder_row(_sel))
	return _anim_actions()


## On the animation under the cursor.
func _anim_actions() -> Array:
	return [_act("Play", _play.bind(_sel), "zen_play", true,
			"Play it here. A one-shot replays after a short hold while Loop is on; click another row to switch."),
		_act("Edit", _open_scene_editor, "zen_edit_scene", true, "Open it in the scene editor."), {},
		_act("Rename", _ask_rename, "zen_rename", true, "Rename the scene file. It stays in its folder."),
		_act("Duplicate", _ask_duplicate, "zen_duplicate", true,
			"Copy it to a new scene next to it, under a name you choose."),
		_act("Move...", _ask_move, "zen_move", true, _MOVE_TIP),
		_act("Delete", _ask_delete, "zen_delete", true,
			"Move the scene file to the OS trash, after a confirmation that lists it."), {},
		_act("Export...", _open_export, "zen_export", true, _EXPORT_TIP, _queue_note(true)),
		_act("Queue", _queue_current, "zen_export_queue", true, _QUEUE_TIP, _queue_note())]


const _MOVE_TIP := "Move into a folder: type its name, or leave it empty for the top level. A new name creates the folder. Right-click a folder to move straight into it."
const _EXPORT_TIP := "Open the Export dialog to render video or frames. Several selected animations become one chain, played back to back."
const _QUEUE_TIP := "Add to the export queue without opening Export. Queued animations render back to back as one chain the next time you open Export. All need the same canvas size."


## The export queue as a note: what is on it, or that it is empty.
## `for_export`: only worth saying when there is a queue to open with.
func _queue_note(for_export := false) -> String:
	if _export_queue.is_empty(): return "" if for_export else "The queue is empty."
	var s := "Queued %d/%d: %s" % [_export_queue.size(), ZenExport.MAX_CHAIN, ", ".join(_export_queue)]
	return s + (" - Export opens with it." if for_export else "")


func _folder_actions(f: String) -> Array:
	var n := _entries.filter(func(e): return String(e.get("folder", "")) == f).size()
	return [_act("Close" if _open.has(f) else "Open", _toggle_folder.bind(f), "zen_play", true,
			"Show or hide the animations in %s. Remembered across runs." % f),
		_act("New animation here", _open_scene_editor.bind(true), "", true,
			"Start a new animation in the scene editor; it saves into %s." % f), {},
		_act("Rename", _ask_rename_folder.bind(f), "zen_rename", true,
			"Rename the folder. Its animations move with it."),
		_act("Delete", _ask_delete_folder.bind(f), "zen_delete", n == 0,
			"Move the empty folder to the OS trash.",
			"Holds %d animation%s - move or delete them first." % [n, "" if n == 1 else "s"] if n > 0 else "")]


func _multi_actions() -> Array:
	var n := _marked_anims().size()
	var over := "Only the first %d go in a chain." % ZenExport.MAX_CHAIN if n > ZenExport.MAX_CHAIN else ""
	return [_act("Export %d as a chain..." % n, _open_export, "zen_export", true,
			"Open the Export dialog with these as one chain, in list order. It replaces the queue.", over),
		_act("Queue %d" % n, _queue_current, "zen_export_queue", true, _QUEUE_TIP, _queue_note()), {},
		_act("Move %d..." % n, _ask_move, "zen_move", true, _MOVE_TIP),
		_act("Delete %d" % n, _ask_delete, "zen_delete", true,
			"Move their scene files to the OS trash, after a confirmation that lists them."), {},
		_act("Clear selection", _back, "zen_back", true, "Back to just the row under the cursor.")]


func _playing_actions() -> Array:
	var out: Array = []
	if _playing != null and _playing.held_pause >= 0:
		out.append(_act("Continue", _continue, "zen_continue", true,
			"Carry on past the pause marker it is holding at. A click on the stage does the same."))
	out.append(_act("Restart", _restart, "zen_restart", true, "Play it again from the start."))
	var bus: ZenSignalBus = _playing.bus() if _playing != null else null
	var names: Array = bus.names() if bus != null else []
	if not names.is_empty():
		out.append({})
		for i in mini(names.size(), 9):
			out.append(_act("fire %s" % String(names[i]), _fire.bind(i), "zen_signal_%d" % (i + 1), true,
				"Fire signal %s, as a game would from code. Signals never fire in an export." % String(names[i]),
				_signal_note(String(names[i]))))
	out.append_array([{}, _act("Edit", _open_scene_editor, "zen_edit_scene", true, "Open it in the scene editor."),
		_act("Export...", _open_export, "zen_export", true, _EXPORT_TIP, _queue_note(true)),
		_act("Queue", _queue_current, "zen_export_queue", true, _QUEUE_TIP, _queue_note()), {},
		_act("Stop", _back, "zen_back", true, "Stop playback and go back to its details.")])
	return out


## How the playing animation's signal `nm` is triggered, from its data.
func _signal_note(nm: String) -> String:
	for ch in _playing.get_children():
		if ch is ZenSignalBus:
			for sd in (ch as ZenSignalBus).signals_data:
				var d := ZenSignalData.normalize((sd as Dictionary).duplicate(true))
				if String(d["name"]) == nm: return _signal_label(d)
	return ""


func _asset_actions() -> Array:
	if _asset_sel.is_multi():
		var n := _marked_assets().size()
		return [_act("Delete %d" % n, _ask_delete, "zen_delete", true,
				"Move their files to the OS trash. An animation still drawing one shows the missing-shape box."), {},
			_act("Clear selection", _back, "zen_back", true, "Back to just the row under the cursor.")]
	if _sel_asset == 0:
		return [_act("Create", _open_shape_editor, "zen_play", true, "Draw a new pixel shape in the shape editor.")]
	var users: Array = _users_of(String(_assets[_sel_asset - 1]["name"])) if _sel_asset - 1 < _assets.size() else []
	return [_act("Edit", _open_shape_editor, "zen_play", true, "Open it in the shape editor."),
		_act("Delete", _ask_delete, "zen_delete", true, "Move the file to the OS trash, after a confirmation.",
			"Drawn by %s - it would show the missing-shape box." % ", ".join(users) if not users.is_empty() else "")]


## The top bar's right half: creating things, the viewer toggles, and the
## screens - there whatever is selected.
func _global_actions() -> Array:
	var out: Array = []
	if _view == View.GALLERY:
		if _section == Section.ANIMS:
			var here := _cur_folder()
			out.append_array([_act("New animation", _open_scene_editor.bind(true), "zen_new", true,
					"Start a new animation in the scene editor.",
					"It saves into %s, the folder under the cursor." % here if here != "" else ""),
				_act("New folder", _ask_new_folder, "zen_new_folder", true,
					"Make an empty folder to sort animations into.")])
		else:
			out.append(_act("New asset", _new_asset, "zen_new", true, "Draw a new pixel shape in the shape editor."))
		out.append({})
	var no_intro := _view == View.PLAYING and _playing != null and not _playing.has_intro()
	var intro := _act("Intro", _toggle.bind("intro"), "zen_toggle_intro", true,
		"Play the intro section before the body. A viewer setting: the scene is not changed.",
		("On" if ZenSettings.play_intro() else "Off") + (" - this animation has no intro." if no_intro else "."))
	intro.merge({"toggle": true, "on": ZenSettings.play_intro()})
	var loop := _act("Loop", _toggle.bind("loop"), "zen_toggle_loop", true,
		"Keep playing: loops repeat, and a one-shot replays after holding its last frame. A viewer setting: the scene is not changed.",
		"On." if ZenSettings.play_loop() else "Off - it stops on the last frame.")
	loop.merge({"toggle": true, "on": ZenSettings.play_loop()})
	out.append_array([intro, loop, {}])
	if _view == View.GALLERY:
		out.append_array([_act("Reload", _restart, "zen_restart", true,
				"Rescan the animation and asset folders, for files changed outside the app."),
			_act("Options", _open_options, "zen_options", true, "Settings: font, default canvas size and more.")])
	out.append(_act("Help", _show_help, "zen_help", true, "Every hotkey, a page per screen."))
	return out


func _refresh_bar() -> void:
	if _bar == null: return
	_bar.visible = _view in [View.GALLERY, View.PLAYING]
	if not _bar.visible: return
	ZenUI.fill_bar(_bar_context, _actions())
	ZenUI.fill_bar(_bar_global, _global_actions())


func _new_asset() -> void:
	_select_asset(0)
	_open_shape_editor()


func _continue() -> void:
	if _playing == null or _playing.held_pause < 0: return
	_playing.release_pause()
	_update_status()


## A right-click on list row `row`. On a row outside the selection it
## selects that row first, as usual - except for a move: with a folder
## selected, an animation offers to move into it; with animations selected,
## a folder offers to take them. The selection is what moves, so it stays.
func _on_row_context(at: Vector2, row: int) -> void:
	var items := _row_menu(row)
	if not items.is_empty(): ZenUI.popup_actions(_menu, items, at)


func _row_menu(row: int) -> Array:
	if row < 0 or row >= _rows.size(): return []
	var marked := _marked_anims()
	var e := _entry_at(row)
	if e.is_empty():
		var f := _folder_row(row)
		var moving := marked.filter(func(nm): return ZenSceneOps.folder_of(nm) != f)
		if row != _sel and not moving.is_empty():
			return [_act("Move %s into %s" % [_what(moving), f], _move_into.bind(f, moving)), {},
				_act("Select %s" % f, _select.bind(row))]
		_select(row)
		return _folder_actions(f)
	var nm := String(e["name"])
	if _anim_sel.is_multi() and marked.has(nm):
		return _multi_actions() + [{}, _move_menu(marked)]
	var cur := _folder_row(_sel)
	if cur != "" and String(e.get("folder", "")) != cur:
		return [_act("Move %s into %s" % [nm, cur], _move_into.bind(cur, [nm])), {},
			_act("Play %s" % nm, _play.bind(row)), _act("Select %s" % nm, _select.bind(row))]
	_select(row)
	return _anim_actions() + [{}, _move_menu([nm])]


## "Move to" with every other folder, the top level, and a typed new one.
func _move_menu(names: Array) -> Dictionary:
	var here := ""
	if names.size() == 1: here = ZenSceneOps.folder_of(String(names[0]))
	var sub: Array = []
	if names.size() > 1 or here != "": sub.append(_act("top level", _move_into.bind("", names)))
	for f in _folders:
		if String(f) != here: sub.append(_act(String(f), _move_into.bind(String(f), names)))
	sub.append_array([{}, _act("new folder...", _ask_move)])
	return {"label": "Move to", "sub": sub}


func _on_asset_context(at: Vector2, row: int) -> void:
	if not _asset_sel.shows(row): _select_asset(row)
	ZenUI.popup_actions(_menu, _asset_actions(), at)


# ---------------------------------------------------------------- views

func _show_gallery() -> void:
	_view = View.GALLERY
	_stage.visible = false
	_info.visible = true
	_asset_preview.visible = _section == Section.ASSETS
	_title.text = "Zen Animator"
	_hint.text = _gallery_hint()
	_refresh_bar()
	if _section == Section.ASSETS:
		_status.text = "%d assets%s" % [_assets.size(), _queue_suffix()]
		_refresh_status_tip()
		return
	_status.text = "%d animations%s" % [_entries.size(), _queue_suffix()]
	_status.text += "   " + _toggle_badges(null)
	_refresh_status_tip()


## The gallery footer. A multi-selection swaps in its own keys - what can be
## done with several rows - and ESC then clears it rather than quitting.
func _gallery_hint() -> String:
	if _section == Section.ASSETS:
		if _asset_sel.is_multi():
			return ZenHotkeyHelp.footer([["zen_delete", "delete %d" % _asset_sel.marks.size()],
					["zen_help", "help"], ["zen_back", "clear selection"]])
		return ZenHotkeyHelp.footer([["zen_play", "edit"], ["zen_tab", "animations"],
				["zen_help", "help"], ["zen_back", "quit"]])
	if _anim_sel.is_multi():
		var n := _anim_sel.marks.size()
		return ZenHotkeyHelp.footer([["zen_export", "export %d" % n], ["zen_move", "move %d" % n],
				["zen_delete", "delete %d" % n], ["zen_help", "help"], ["zen_back", "clear selection"]])
	if _cur_entry().is_empty():
		return ZenHotkeyHelp.footer([["zen_play", "open / close"], ["zen_rename", "rename"],
				["zen_search", "search"], ["zen_help", "help"], ["zen_back", "quit"]])
	return ZenHotkeyHelp.footer([["zen_play", "play"], ["zen_edit_scene", "edit"], ["zen_new", "new"],
			["zen_search", "search"], ["zen_tab", "assets"], ["zen_help", "help"], ["zen_back", "quit"]])


## Whether the playing footer currently advertises "continue".
var _hint_paused := false


func _show_playing(nm: String) -> void:
	_view = View.PLAYING
	_stage.visible = true
	_info.visible = false
	_asset_preview.visible = false
	_title.text = nm
	# Only advertise the signal keys when there is something to fire.
	var n := _signal_count()
	var pairs: Array = []
	_hint_paused = _playing != null and _playing.held_pause >= 0
	if _hint_paused: pairs.append(["zen_continue", "continue"])
	pairs.append(["zen_restart", "restart"])
	if n == 1: pairs.append(["1", "fire signal"])
	elif n > 1: pairs.append(["1-%d" % n, "fire signal"])
	pairs.append_array([["zen_help", "help"], ["zen_back", "back"]])
	_hint.text = ZenHotkeyHelp.footer(pairs)
	_refresh_bar()


func _signal_count() -> int:
	if _playing == null or _playing.bus() == null: return 0
	return _playing.bus().names().size()


## Every hotkey of the gallery, for the H sheet: a page per screen, opening
## on the one showing now.
func _show_help() -> void:
	var playing: Array = [["zen_continue", "continue from a pause marker"],
		["zen_restart", "restart the animation"]]
	var n := _signal_count() if _view == View.PLAYING else 0
	if n > 0: playing.append(["1" if n == 1 else "1-%d" % n, "fire signal (%s)" % ", ".join(_playing.bus().names())])
	playing.append_array([["click a row", "switch to that animation"],
		["right-click the stage", "the playback actions"],
		["zen_toggle_intro", "intro on / off"], ["zen_toggle_loop", "loop on / off"],
		["zen_tab", "switch to assets (stops playback)"],
		["zen_export", "export..."], ["zen_export_queue", "add to the export queue"],
		["zen_back", "back to the gallery"]])
	var multi: Array = [["Shift+click, Shift+Up/Down", "select a range"],
		["Ctrl+click", "add / remove one row"], ["right-click", "what can be done with that row"]]
	var anims: Array = [["zen_play", "play"], ["double-click", "play"],
		["zen_edit_scene", "edit in the scene editor"], ["zen_new", "new animation"],
		["zen_rename", "rename"], ["zen_duplicate", "duplicate"],
		["zen_prev", "previous"], ["zen_next", "next"],
		["zen_search", "search (ESC clears, ENTER plays)"],
		["zen_fold", "close the folder"], ["zen_unfold", "open the folder"],
		["zen_move", "move the selection to a folder"], ["zen_new_folder", "new folder"],
		["right-click a folder", "move the selected animations into it"],
		["right-click an animation", "with a folder selected: move it into that folder"]]
	anims.append_array(multi)
	anims.append_array([["zen_delete", "delete the selected animations"],
		["zen_tab", "switch to assets"],
		["zen_restart", "reload the lists"],
		["zen_toggle_intro", "intro on / off (now %s)" % ("on" if ZenSettings.play_intro() else "off")],
		["zen_toggle_loop", "loop on / off (now %s)" % ("on" if ZenSettings.play_loop() else "off")],
		["zen_options", "options"], ["zen_export", "export... (the selection, as a chain)"],
		["zen_export_queue", "add the selection to the export queue"],
		["zen_back", "clear the selection, then quit"]])
	var assets: Array = [["zen_play", "edit the asset (row 1: new asset)"], ["double-click", "edit the asset"],
		["zen_prev", "previous"], ["zen_next", "next"]]
	assets.append_array(multi)
	assets.append_array([["zen_delete", "delete the selected assets"],
		["zen_tab", "switch to animations"],
		["zen_restart", "reload the lists"], ["zen_options", "options"],
		["zen_back", "clear the selection, then quit"]])
	var start := 0 if _view == View.PLAYING else (2 if _section == Section.ASSETS else 1)
	_help.show_pages("Gallery", [{"name": "Playing", "rows": playing},
		{"name": "Animations", "rows": anims}, {"name": "Assets", "rows": assets}], start)


## The I / L state as a compact badge pair. With a canvas, a toggle that does
## not apply to it says so instead of claiming an effect it cannot have.
func _toggle_badges(c: ZenCanvas) -> String:
	var intro := "INTRO %s" % ("on" if ZenSettings.play_intro() else "off")
	var loop := "LOOP %s" % ("on" if ZenSettings.play_loop() else "off")
	if c != null:
		if not c.has_intro(): intro = "INTRO n/a"
		if not c.loop_play and ZenSettings.play_loop(): loop = "LOOP replay"
	return "[%s]  [%s]" % [intro, loop]


## The status line's tooltip: what its badges mean, and the queue.
func _refresh_status_tip() -> void:
	var t := {"title": "Status",
		"text": "While playing: the time and the play range, then [signal] / [paused] states. "
			+ "INTRO and LOOP are the viewer toggles (n/a: this animation has no intro; replay: a "
			+ "one-shot restarts after it ends). [queued: N] counts the export queue.",
		"note": _queue_note()}
	if _status.tip != t: _status.tip = t


func _queue_suffix() -> String:
	return "   [queued: %d]" % _export_queue.size() if not _export_queue.is_empty() else ""


# ---------------------------------------------------------------- playing

## Instantiate and run the selected animation inside a SubViewport.
##
## The viewport is sized to the animation's own design canvas and shown through
## a TextureRect with nearest-neighbour filtering, so the pixel grid stays
## honest at any window size. Stretching it with a Control layout instead would
## reposition every element, because Zen geometry is fractional.
func _play(row: int) -> void:
	var e := _entry_at(row)
	if e.is_empty(): return            # a folder row
	_play_entry(e)


func _play_entry(e: Dictionary) -> void:
	_stop()
	if _section != Section.ANIMS: _set_section(Section.ANIMS)
	if not bool(e.get("ok", false)): return
	_playing_entry = e
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
		_play_entry(_playing_entry)
	else:
		var sec := _section
		_reselect(String(_cur_entry().get("name", "")), _folder_row(_sel))
		_set_section(sec)
		_status.text = "%d animations, %d assets  [reloaded]" % [_entries.size(), _assets.size()]


## ESC backs out one level, then quits - the usual nesting, so it is never a
## surprise which one happens.
func _back() -> void:
	if _view == View.SHAPE_EDITOR or _view == View.SCENE_EDITOR:
		return          # the editor owns ESC (it may have unsaved changes)
	elif _view == View.OPTIONS:
		_close_options()
	elif _view == View.EXPORT:
		_close_export()
	elif _view == View.PLAYING:
		_stop()
		_show_gallery()
		_refresh_anim_selection()
	elif _section == Section.ANIMS and _anim_sel.is_multi():
		_select(_sel)
	elif _section == Section.ASSETS and _asset_sel.is_multi():
		_select_asset(_sel_asset)
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
	_refresh_bar()


func _close_options() -> void:
	if _options != null:
		_options.queue_free()
		_options = null
	_view = View.GALLERY
	_show_gallery()


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
	_refresh_bar()


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
	_asset_sel.resize(_assets.size() + 1)
	_asset_sel.pick(row)
	# Animations may now draw a changed shape; their usage lists still hold.
	_set_section(Section.ASSETS)


## The scene editor, on the selected animation (`new_scene`: a fresh one).
## Closing it rescans - it may have saved, renamed or deleted - and selects
## what it last had open.
func _open_scene_editor(new_scene := false) -> void:
	if _scene_editor != null: return
	_stop()
	if _section != Section.ANIMS: _set_section(Section.ANIMS)
	_scene_editor = (load(SCENE_EDITOR_SCENE) as PackedScene).instantiate()
	_scene_editor.closed.connect(_close_scene_editor)
	add_child(_scene_editor)
	var path := "" if new_scene else String(_cur_entry().get("path", ""))
	if path.is_empty() and not new_scene: new_scene = true
	# A new scene saves into the folder the cursor is in.
	_scene_editor.open(path, _cur_folder() if new_scene else "")
	_view = View.SCENE_EDITOR
	_refresh_bar()


func _close_scene_editor() -> void:
	var nm := ""
	if _scene_editor != null:
		nm = _scene_editor.current_name()
		_scene_editor.queue_free()
		_scene_editor = null
	_view = View.GALLERY
	_reselect(nm)


## Rescan everything and put the cursor on animation `nm`, opening its
## folder so a scene just saved or moved is in view - or on folder `folder`,
## or near where it was.
func _reselect(nm: String, folder := "") -> void:
	var keep := _sel
	_scan()
	for e in _entries:
		var f := String(e.get("folder", ""))
		if String(e["name"]) == nm and f != "" and not _open.has(f):
			_open[f] = true
			ZenSettings.set_open_folders(_open.keys())
	_build_list()
	_scan_assets()
	_build_asset_list()
	_set_section(Section.ANIMS)
	var row := _row_of(nm)
	if row < 0 and folder != "": row = _row_of_folder(folder)
	if row < 0: row = mini(keep, _rows.size() - 1)
	_select(maxi(row, 0))


func _build_name_dialog() -> void:
	_name_dialog = ConfirmationDialog.new()
	var col := VBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(280, 0)
	_name_edit.text_changed.connect(func(_t): _validate_name())
	_name_edit.text_submitted.connect(func(_t): _on_name_ok())
	col.add_child(_name_edit)
	_name_error = ZenUI.label("", ZenUI.WARN)
	col.add_child(_name_error)
	_name_dialog.add_child(col)
	_name_dialog.confirmed.connect(_on_name_ok)
	add_child(_name_dialog)


func _ask_name(title: String, initial: String, fn: Callable, check := _scene_name_check) -> void:
	_name_dialog.title = title
	_name_edit.text = initial
	_name_action = fn
	_name_check = check
	_validate_name()
	_name_dialog.popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _validate_name() -> bool:
	var r: Array = _name_check.call(_name_edit.text)
	_name_error.text = String(r[1])
	_name_dialog.get_ok_button().disabled = not bool(r[0])
	return bool(r[0])


func _scene_name_check(raw: String) -> Array:
	var n := ZenSceneOps.clean_name(raw)
	if n.is_empty(): return [false, "type a name"]
	if not ZenSceneOps.is_name_free(n): return [false, "an animation called %s already exists" % n]
	return [true, "will be named %s" % n if n != raw.strip_edges() else ""]


## A folder to move into: "" is the top level, an existing folder is fine,
## a new name creates it.
func _move_folder_check(raw: String) -> Array:
	var n := ZenSceneOps.clean_name(raw)
	if n.is_empty(): return [true, "moves to the top level"]
	if _folders.has(n): return [true, "into %s" % n]
	return [true, "creates folder %s" % n]


## A name for a new folder, or a renamed one (`old` may keep its name).
func _new_folder_check(raw: String, old := "") -> Array:
	var n := ZenSceneOps.clean_name(raw)
	if n.is_empty(): return [false, "type a folder name"]
	if n != old and _folders.has(n): return [false, "a folder called %s already exists" % n]
	return [true, "will be named %s" % n if n != raw.strip_edges() else ""]


func _on_name_ok() -> void:
	if not _validate_name(): return
	_name_dialog.hide()
	if _name_action.is_valid(): _name_action.call(ZenSceneOps.clean_name(_name_edit.text))


## F2: rename the animation's scene file.
func _ask_rename() -> void:
	if _cur_entry().is_empty():
		_ask_rename_folder(_folder_row(_sel))
		return
	var old := String(_cur_entry()["name"])
	_ask_name("Rename animation", old, func(n):
		var err := ZenSceneOps.rename(old, n)
		_reselect(n if err == OK else old)
		_status.text = "renamed %s -> %s" % [old, n] if err == OK else "could not rename %s" % old)


## Ctrl+D: copy the animation to a new scene.
func _ask_duplicate() -> void:
	if _cur_entry().is_empty(): return
	var src := String(_cur_entry()["name"])
	_ask_name("Duplicate animation", ZenSceneOps.unique_name(src + "_copy"), func(n):
		var err := ZenSceneOps.duplicate_scene(src, n)
		_reselect(n if err == OK else src)
		_status.text = "duplicated %s as %s" % [src, n] if err == OK else "could not duplicate %s" % src)


func _ask_rename_folder(old: String) -> void:
	if old.is_empty(): return
	var fn := func(n: String) -> void:
		if n == old: return
		var err := ZenSceneOps.rename_folder(old, n)
		if err == OK and _open.has(old):
			_open.erase(old)
			_open[n] = true
			ZenSettings.set_open_folders(_open.keys())
		_reselect("", n if err == OK else old)
		_status.text = "renamed folder %s -> %s" % [old, n] if err == OK \
					   else "could not rename folder %s" % old
	_ask_name("Rename folder", old, fn, _new_folder_check.bind(old))


## Ctrl+Shift+N: a new, empty folder.
func _ask_new_folder() -> void:
	var fn := func(n: String) -> void:
		var err := ZenSceneOps.make_folder(n)
		_open[n] = true
		ZenSettings.set_open_folders(_open.keys())
		_reselect("", n)
		_status.text = "new folder %s" % n if err == OK else "could not create folder %s" % n
	_ask_name("New folder", "", fn, _new_folder_check)


## M: move the selected animations (or the one under the cursor) into a
## folder - typed, so a new name makes the folder; empty is the top level.
func _ask_move() -> void:
	var names := _marked_anims()
	if names.is_empty(): return
	_ask_name("Move %s to folder" % _what(names), _cur_folder(), _move_into.bind(names), _move_folder_check)


## Move animations `names` into folder `f` ("" = the top level), shared by
## M, the bar and the right-click menus. The folder opens so they stay in view.
func _move_into(f: String, names: Array) -> void:
	if names.is_empty(): return
	var failed: Array = []
	for nm in names:
		if ZenSceneOps.move(String(nm), f) != OK: failed.append(nm)
	if f != "" and not _open.has(f):
		_open[f] = true
		ZenSettings.set_open_folders(_open.keys())
	_reselect(String(names[0]))
	_status.text = "moved %s to %s" % [_what(names), f if f != "" else "the top level"]
	if not failed.is_empty(): _status.text = "could not move %s" % ", ".join(failed)


## "name" for one animation, "N animations" for several.
static func _what(names: Array) -> String:
	return String(names[0]) if names.size() == 1 else "%d animations" % names.size()


## Export is the same overlay-child pattern as Options - opening it from
## PLAYING leaves playback running underneath, so closing it returns there
## rather than always falling back to the gallery.
func _open_export() -> void:
	if _export_dialog != null: return
	_export_dialog = (load(EXPORT_SCENE) as PackedScene).instantiate()
	_export_dialog.closed.connect(_close_export)
	add_child(_export_dialog)
	var chain: Array = _export_queue.duplicate()
	if _anim_sel.is_multi():
		# A multi-selection is an explicit "these" - it replaces the queue.
		chain = _marked_anims().slice(0, ZenExport.MAX_CHAIN)
	elif chain.is_empty():
		var current := _playing.scene_file_path.get_file().get_basename() \
					   if _playing != null else String(_cur_entry().get("name", ""))
		if current != "": chain = [current]
	_prev_view = _view if _view in [View.GALLERY, View.PLAYING] else View.GALLERY
	_export_dialog.open(_entries, chain)
	_view = View.EXPORT
	_refresh_bar()


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
	_queue_selection()
	_refresh_bar()
	_refresh_status_tip()


func _queue_selection() -> void:
	if _view == View.GALLERY and _anim_sel.is_multi():
		for nm in _marked_anims():
			if not _queue_name(nm): return
		return
	var nm := _playing.scene_file_path.get_file().get_basename() \
			  if _view == View.PLAYING and _playing != null \
			  else String(_cur_entry().get("name", ""))
	if nm != "": _queue_name(nm)


## Append one animation to the queue; false (with the reason in the status)
## when it cannot go on.
func _queue_name(nm: String) -> bool:
	var entry := {}
	for e in _entries:
		if String(e.get("name", "")) == nm: entry = e; break
	if entry.is_empty() or not bool(entry.get("ok", false)): return false

	if _export_queue.size() >= ZenExport.MAX_CHAIN:
		_status.text = "queue is full (%d max)" % ZenExport.MAX_CHAIN
		return false
	if not _export_queue.is_empty():
		var first := {}
		for e in _entries:
			if String(e.get("name", "")) == _export_queue[0]: first = e; break
		var fd: Vector2 = first.get("design", Vector2.ZERO)
		var d: Vector2 = entry["design"]
		if d != fd:
			_status.text = "cannot queue %s: %dx%d canvas, queue is %dx%d" % [
				nm, int(d.x), int(d.y), int(fd.x), int(fd.y)]
			return false

	_export_queue.append(nm)
	_status.text = "queued %s  [queued: %d]" % [nm, _export_queue.size()]
	return true


# ---------------------------------------------------------------- delete

## DEL: move the selected rows' files to the trash, after a confirmation that
## lists every file. An asset still drawn by an animation is named, since that
## animation then draws the missing-shape box.
func _ask_delete() -> void:
	var files: Array[String] = []
	var L: Array = []
	if _section == Section.ANIMS:
		var names := _marked_anims()
		if names.is_empty():
			_ask_delete_folder(_folder_row(_sel))
			return
		for nm in names:
			files.append(ZenSceneOps.path_of(nm))
		L.append("Move %s to the trash?" % ("animation %s" % names[0] if names.size() == 1
				 else "%d animations" % names.size()))
	else:
		var names := _marked_assets()
		if names.is_empty(): return
		var paths := ZenAssets.shape_paths()
		var used: Array = []
		for nm in names:
			files.append(String(paths[nm]))
			if not _users_of(nm).is_empty(): used.append(nm)
		L.append("Move %s to the trash?" % ("asset %s" % names[0] if names.size() == 1
				 else "%d assets" % names.size()))
		if not used.is_empty():
			L.append("Still drawn by an animation (it will show the missing-shape box): %s"
					 % ", ".join(used))
	L.append("")
	for f in files: L.append("  " + f)
	_confirm.dialog_text = "\n".join(L)
	_confirm_action = _delete_files.bind(files)
	_confirm.popup_centered()


## A folder is only trashed once it is empty: deleting the animations inside
## is a separate, listed choice, never a side effect of removing a folder.
func _ask_delete_folder(f: String) -> void:
	if f.is_empty(): return
	if not ZenSceneOps.scenes_in(f).is_empty():
		_status.text = "folder %s is not empty - move or delete its animations first" % f
		return
	_confirm.dialog_text = "Move the empty folder %s to the trash?" % f
	_confirm_action = func():
		var err := ZenSceneOps.delete_folder(f)
		_open.erase(f)
		ZenSettings.set_open_folders(_open.keys())
		_reselect("")
		_status.text = "deleted folder %s" % f if err == OK else "could not delete folder %s" % f
	_confirm.popup_centered()


func _delete_files(files: Array[String]) -> void:
	var failed: Array = []
	for f in files:
		if ZenAssets.trash(f) != OK: failed.append(f.get_file())
	var anims := _section == Section.ANIMS
	var first := (_anim_sel.rows() if anims else _asset_sel.rows())[0]
	_scan()
	_build_list()
	_scan_assets()
	_build_asset_list()
	var left := _entries.map(func(e): return String(e["name"]))
	_export_queue = _export_queue.filter(func(nm): return left.has(nm))
	_set_section(_section)
	if anims: _select(first)
	else: _select_asset(mini(first, _assets.size()))
	_status.text = "moved %d file%s to the trash" % [files.size() - failed.size(),
				   "" if files.size() - failed.size() == 1 else "s"]
	if not failed.is_empty(): _status.text += "   could not delete: %s" % ", ".join(failed)


## A click continues a held pause marker; otherwise the pointer reaches the
## playing canvas, so press / release / follow signals work as in a game.
func _on_screen_input(ev: InputEvent) -> void:
	if _view != View.PLAYING or _playing == null or not (ev is InputEventMouse): return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			ZenUI.popup_actions(_menu, _playing_actions(), _screen.get_screen_transform() * mb.position)
		_screen.accept_event()
		return
	if mb != null and mb.button_index != MOUSE_BUTTON_LEFT: return
	if mb != null and mb.pressed and _playing.held_pause >= 0:
		_playing.release_pause()
		_update_status()
		_screen.accept_event()
		return
	var frac := _screen_frac((ev as InputEventMouse).position)
	var kind := "move" if mb == null else ("press" if mb.pressed else "release")
	if _playing.pointer(kind, frac):
		_status.text = "fired  %s" % _playing.bus().running_name
	if mb != null: _screen.accept_event()


## A point on the stage in canvas fractions: the texture is drawn
## aspect-fit and centred (stretch_mode keep-aspect-centred).
func _screen_frac(p: Vector2) -> Vector2:
	var ts := _playing.design_size
	var k := minf(_screen.size.x / ts.x, _screen.size.y / ts.y)
	return (p - (_screen.size - ts * k) * 0.5) / k / ts


## "name" plus how it is triggered when that is not code alone.
static func _signal_label(sd: Dictionary) -> String:
	var tags: Array = []
	if String(sd["trigger"]) != "code": tags.append("on " + String(sd["trigger"]))
	if String(sd["point"]) != "none": tags.append(String(sd["point"]))
	return String(sd["name"]) + ("" if tags.is_empty() else " (%s)" % ", ".join(tags))


## Fire a signal by number while playing. With a click on the stage this is
## the interactive way to see one: an export never fires a signal, by design.
func _fire(n: int) -> void:
	if _playing == null: return
	var bus := _playing.bus()
	if bus == null: return
	var names: Array = bus.names()
	if n < 0 or n >= names.size(): return
	# A point signal reads the pointer itself (ZenSignalBus._start).
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
	elif bus != null and bus.is_following(): extra = "   [following]"
	elif bus != null and bus.is_holding(): extra = "   [signal end]"
	elif _playing.held_pause >= 0: extra = "   [paused - SPACE or click to continue]"
	if _view == View.PLAYING and _hint_paused != (_playing.held_pause >= 0):
		_show_playing(_title.text)

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
			_play_entry(_playing_entry)
			return
	else:
		_replay_hold = 0.0
	_status.text = "t %.2f / %.2fs%s   %s%s" % [t, tot, extra, _toggle_badges(_playing), _queue_suffix()]
	_refresh_status_tip()


## I / L: flip a viewer toggle, persist it, and restart what is playing so
## the change shows at once instead of on the next cycle.
func _toggle(which: String) -> void:
	if which == "intro": ZenSettings.set_play_intro(not ZenSettings.play_intro())
	else: ZenSettings.set_play_loop(not ZenSettings.play_loop())
	if _view == View.PLAYING: _play_entry(_playing_entry)
	else: _show_gallery()


func _unhandled_input(ev: InputEvent) -> void:
	if _confirm.visible or _name_dialog.visible: return
	if _help.handle_key(ev):
		get_viewport().set_input_as_handled()
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
	elif ev.is_action_pressed("zen_delete"):
		if _view == View.GALLERY:
			_ask_delete()
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
	elif ev.is_action_pressed("zen_continue") and _view == View.PLAYING \
			and _playing != null and _playing.held_pause >= 0:
		# Before zen_play: SPACE is bound to both, and plays from the list.
		_playing.release_pause()
		_update_status()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_edit_scene"):
		# Before zen_play: Ctrl+ENTER also satisfies the plain ENTER action.
		if _view in [View.GALLERY, View.PLAYING] and _section == Section.ANIMS:
			_open_scene_editor()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_duplicate"):
		if _view == View.GALLERY and _section == Section.ANIMS:
			_ask_duplicate()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_search"):
		if _view in [View.GALLERY, View.PLAYING]:
			_focus_search()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_new_folder"):
		# Before zen_new: Ctrl+Shift+N also satisfies the plain N action.
		if _view == View.GALLERY and _section == Section.ANIMS:
			_ask_new_folder()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_move"):
		if _view == View.GALLERY and _section == Section.ANIMS:
			_ask_move()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_fold") or ev.is_action_pressed("zen_unfold"):
		if _view == View.GALLERY and _section == Section.ANIMS:
			_fold_cursor(ev.is_action_pressed("zen_unfold"))
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_new"):
		if _view == View.GALLERY:
			if _section == Section.ASSETS:
				_select_asset(0)
				_open_shape_editor()
			else: _open_scene_editor(true)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_rename"):
		if _view == View.GALLERY and _section == Section.ANIMS:
			_ask_rename()
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_play"):
		if _view == View.GALLERY:
			if _section == Section.ASSETS: _open_shape_editor()
			elif _cur_entry().is_empty(): _toggle_folder(_folder_row(_sel))
			else: _play(_sel)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_prev"):
		if _view == View.GALLERY:
			var shift := (ev as InputEventKey).shift_pressed if ev is InputEventKey else false
			if _section == Section.ASSETS: _select_asset(_sel_asset - 1, shift)
			else: _select(_sel - 1, shift)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("zen_next"):
		if _view == View.GALLERY:
			var shift := (ev as InputEventKey).shift_pressed if ev is InputEventKey else false
			if _section == Section.ASSETS: _select_asset(_sel_asset + 1, shift)
			else: _select(_sel + 1, shift)
			get_viewport().set_input_as_handled()
	else:
		# zen_signal_1..9 fire the nth signal of the playing document.
		for i in range(9):
			if ev.is_action_pressed("zen_signal_%d" % (i + 1)):
				if _view == View.PLAYING:
					_fire(i)
					get_viewport().set_input_as_handled()
				break
