class_name ZenSceneEditor
extends Control
##
## The scene editor: create, edit and save a Zen animation scene. Opened from
## the gallery (Ctrl+ENTER on an animation, N for a new one).
##
## THREE RULES, each of which keeps it from growing a second copy of the data:
##   - The timeline is the canvas's own AnimationPlayer. Lanes, keys, length
##     and markers are read from the "zen" Animation; scrubbing seeks that
##     player (ZenCanvas.scrub); every key edit lands in that Animation
##     through ZenKeyOps. Nothing here stores a key.
##   - The Elements panel is the canvas's node tree. Adding, deleting,
##     reordering and renaming are node operations (ZenElemOps), and Save
##     packs that same tree.
##   - Panels are summoned (ZenEditorPanel): hidden until opened from the top
##     bar, the View menu or 1-4; unpinned they float and auto-hide, pinned
##     they stay and make room.
##
## Undo is snapshot-based like the shape editor and the C original: each
## action stores the scene before and after as a PackedScene of a DETACHED
## copy (ZenSceneOps.detach - a plain pack would share the Animations with
## the live canvas and the snapshot would change along with it). A continuous
## gesture - a drag, a spin box being scrubbed - is one action, committed when
## it goes quiet.
##
## Auto-key (K) is the C editor's: ON, every edit writes a key at the playhead
## (the first key of a prop also pins its base pose at 0); OFF, keyed props are
## read-only and edits change the base pose of untracked props only.
##

signal closed

const LIVE_QUIET := 0.6                 ## a gesture commits after this much quiet
const SAMPLES := 96                     ## sparkline resolution per lane
const FRAME := 1.0 / 60.0

## Props the inspector offers per kind, in the C editor's order. A text's
## `string` is the pool entry it shows (ZenStrings), keyed like any stepped prop.
const PROPS := {
    "shape": ["pos_x", "pos_y", "w", "h", "scale", "rot", "alpha", "color",
              "outline", "outline_alpha", "outline_color"],
    "text": ["pos_x", "pos_y", "size", "rot", "alpha", "color", "string", "crumble",
             "crumble_dir", "crumble_spread", "crumble_dist", "crumble_spin"],
    "global": ["fade", "color", "bg_alpha", "bg_color"],
}
## [min, max, step] per prop for the spin boxes; both ends are soft.
const RANGES := {
    "pos_x": [-1.0, 2.0, 0.001], "pos_y": [-1.0, 2.0, 0.001],
    "w": [0.0, 4.0, 0.001], "h": [0.0, 4.0, 0.001], "size": [0.0, 1.0, 0.001],
    "scale": [0.0, 20.0, 0.01], "rot": [-3600.0, 3600.0, 0.5],
    "alpha": [0.0, 1.0, 0.01], "outline": [0.0, 0.5, 0.001], "outline_alpha": [0.0, 1.0, 0.01],
    "fade": [0.0, 1.0, 0.01], "bg_alpha": [0.0, 1.0, 0.01],
    "crumble": [0.0, 1.0, 0.01], "crumble_dir": [-360.0, 360.0, 1.0],
    "crumble_spread": [0.0, 360.0, 1.0], "crumble_dist": [0.0, 4.0, 0.01],
    "crumble_spin": [-3600.0, 3600.0, 1.0], "shape_id": [-2.0, 64.0, 1.0],
    "string": [0.0, 255.0, 1.0],
}

var _canvas: ZenCanvas = null
var _name := ""                         ## the scene's name; "" until first saved
## The gallery folder a first save (or Save As) lands in; "" = top level.
var _folder := ""
var _undo := UndoRedo.new()
var _saved_version := 0
var _sel: Array[String] = []            ## selected elem_names, in pick order
var _t := 0.0                           ## the playhead
var _playing := false
var _autokey := false
## "node|prop|idx" -> true. Not lane-based: keying a new prop inserts a lane
## and would shift every lane index below it.
var _key_sel: Dictionary = {}
var _keys_dismissed := false            ## Keys panel closed while keys stay picked
var _lanes: Array = []                  ## [{elem, prop}] parallel to the timeline's lanes
var _live_before: PackedScene = null
var _live_label := ""
var _live_timer: Timer
var _drag_from: Dictionary = {}         ## elem_name -> pos_frac at drag start
var _key_drag: Array = []               ## [[lane_id, idx, t0]]
var _slide := 0.0                       ## 0 panels shown .. 1 slid away (playback)
var _slide_tween: Tween
var _syncing := false

var _menu: MenuBar
var _title: Label
var _status: Label
var _time: Label
var _play_btn: Button
var _autokey_btn: Button
var _panel_btns: Dictionary = {}
var _work: Control
var _stage: ZenEditorStage
var _panels: Array[ZenEditorPanel] = []
var _p_elems: ZenEditorPanel
var _p_insp: ZenEditorPanel
var _p_doc: ZenEditorPanel
var _p_tl: ZenEditorPanel
var _p_str: ZenEditorPanel
var _p_keys: ZenEditorPanel
var _keys: ZenKeyPanel
var _p_sig: ZenEditorPanel
var _sigs: ZenSignalPanel
var _sig_pick := ""                     ## the signal the Signals panel shows
## The signal whose keys the timeline edits ("" = the document). While set,
## _t is seconds into the signal and _doc_t holds the document playhead the
## signal is previewed from.
var _sig_edit := ""
var _doc_t := 0.0
var _str_list: ItemList
var _str_edit: TextEdit
var _str_info: Label
var _str_btns: Dictionary = {}          ## "add" | "assign" | "delete" | "clean" -> Button
var _str_sel := -1                      ## the pool entry the Strings panel edits
var _tree: Tree
var _insp: VBoxContainer
var _insp_rows: Array = []              ## [{prop, node, editor, key}]
var _doc_rows: Dictionary = {}
var _tl: ZenTimelineView
var _ctx: PopupMenu
var _ctx_ease: PopupMenu
var _ctx_items: Dictionary = {}         ## id -> Callable
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label
var _name_fn := Callable()
var _confirm: ConfirmationDialog
var _confirm_fn := Callable()
var _open_dialog: ConfirmationDialog
var _open_list: ItemList
var _leave_dialog: ConfirmationDialog
var _help := ZenHotkeyHelp.new()


func _ready() -> void:
    ZenEasingSet.load_project()
    var st := ZenSettings.editor_state()
    _autokey = bool(st.get("autokey", false))
    _build_ui()
    var panels: Dictionary = st.get("panels", {})
    for p in _panels:
        p.apply_state(panels.get(p.panel_id, {}))
    _live_timer = Timer.new()
    _live_timer.one_shot = true
    _live_timer.timeout.connect(_commit_live)
    add_child(_live_timer)
    _sync_autokey()
    _layout()


func _exit_tree() -> void:
    _undo.free()


# ---------------------------------------------------------------- open / state

## Edit the scene at `path`, or a new one when "" (saved into `folder`).
func open(path: String, folder := "") -> void:
    var c: ZenCanvas = null
    _folder = folder
    if path != "":
        c = ZenSceneOps.open(path)
        _name = path.get_file().get_basename()
        _folder = ZenSceneOps.folder_of_path(path)
    if c == null:
        _name = ""
        c = ZenSceneOps.new_canvas("untitled")
    _t = 0.0
    _sig_edit = ""
    _sig_pick = ""
    _set_canvas(c)
    _sel.clear()
    var rows := ZenElemOps.rows(_canvas)
    if not rows.is_empty(): _sel.append((rows[0] as ZenElement).elem_name)
    _undo.clear_history()
    _saved_version = _undo.get_version()
    _key_sel.clear()
    _refresh_all()
    _set_status("editing %s" % _name if _name != "" else "new scene - Ctrl+S saves it under a name")
    # Show the timeline and the elements on a first visit: an empty screen
    # does not say where anything is.
    if not ZenSettings.editor_state().has("panels"):
        _p_elems.set_open(true)
        _p_tl.set_open(true)


func current_name() -> String:
    return _name


func _dirty() -> bool:
    return _undo.get_version() != _saved_version or _name == "" or _live_before != null


func _set_canvas(c: ZenCanvas) -> void:
    _stop()
    var old := _canvas
    c.live_playback = false             # the editor drives the clock
    _canvas = c
    _stage.set_canvas(c)
    if old != null and old != c: old.queue_free()
    _canvas.edit_begin()
    # Signal key mode survives an undo only while its signal does.
    if _sig_edit != "" and ZenSignalOps.anim(c, _sig_edit) == null:
        _sig_edit = ""
        _t = _doc_t
    c.edit_anim = _sig_edit
    _pose()


func _selected_nodes() -> Array:
    var out: Array = []
    for nm in _sel:
        var el := ZenElemOps.find(_canvas, nm)
        if el != null: out.append(el)
    return out


func _primary() -> ZenElement:
    var ns := _selected_nodes()
    return ns[ns.size() - 1] if not ns.is_empty() else null


# ---------------------------------------------------------------- undo

func _snapshot() -> PackedScene:
    return ZenSceneOps.snapshot(_canvas)


func _restore(ps: PackedScene) -> void:
    _set_canvas(ZenSceneOps.restore(ps))
    _sel.assign(_sel.filter(func(n): return ZenElemOps.find(_canvas, n) != null))
    _key_sel.clear()
    _refresh_all()


func _record(label: String, before: PackedScene) -> void:
    var after := _snapshot()
    _undo.create_action(label)
    _undo.add_do_method(_restore.bind(after))
    _undo.add_undo_method(_restore.bind(before))
    _undo.commit_action(false)          # already applied
    _sync_title()


## One undoable step.
func _command(label: String, fn: Callable) -> void:
    _stop()
    _commit_live()
    var before := _snapshot()
    fn.call()
    _sync_signal()
    _record(label, before)
    _after_edit()
    _set_status(label)


## One step of a continuous gesture: the first call snapshots, later calls of
## the same gesture just apply, and the gesture commits once it goes quiet.
func _live(label: String, fn: Callable) -> void:
    _stop()
    if _live_before != null and _live_label != label: _commit_live()
    if _live_before == null:
        _live_before = _snapshot()
        _live_label = label
    fn.call()
    _sync_signal()
    _live_timer.start(LIVE_QUIET)
    _after_edit(false)


func _commit_live() -> void:
    if _live_before == null: return
    var before := _live_before
    _live_before = null
    _live_timer.stop()
    _record(_live_label, before)
    _set_status(_live_label)


func _do_undo() -> void:
    _commit_live()
    if _undo.undo(): _set_status("undo: %s" % _undo.get_current_action_name())
    _sync_title()


func _do_redo() -> void:
    _commit_live()
    if _undo.redo(): _set_status("redo: %s" % _undo.get_current_action_name())
    _sync_title()


## Re-pose and refresh what an edit can change. `rebuild` false keeps the
## inspector's controls (a spin box being dragged must not be replaced
## under the cursor) and only refreshes their values.
func _after_edit(rebuild := true) -> void:
    if _sig_edit != "" and ZenSignalOps.anim(_canvas, _sig_edit) == null:
        _sig_edit = ""                  # its signal was deleted or undone
        _canvas.edit_anim = ""
        _t = _doc_t
    _pose()
    _stage.refresh_backdrop()
    _stage.selected = _selected_nodes()
    _stage.time = _pose_t()
    if rebuild:
        # Deferred: the edit may have come from a control inside the very
        # tree or inspector being rebuilt, mid-signal.
        _refresh_tree.call_deferred()
        _build_inspector.call_deferred()
    else:
        _refresh_inspector_values()
    _refresh_timeline()
    _refresh_doc()
    _refresh_strings(not rebuild)
    _refresh_signals()
    _sync_title()


func _refresh_all() -> void:
    _after_edit(true)


# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
    var rows := ZenUI.build_shell(self, 4)

    var bar := HBoxContainer.new()
    bar.add_theme_constant_override("separation", 6)
    rows.add_child(bar)
    _menu = MenuBar.new()
    _menu.flat = true
    bar.add_child(_menu)
    _build_menus()
    for spec in [["elements", "1"], ["inspector", "2"], ["document", "3"], ["timeline", "4"],
                 ["strings", "5"], ["keys", "6"], ["signals", "7"]]:
        var b := ZenEditorPanel._tool_button(spec[0], "Show / hide the %s panel (%s)" % spec)
        b.flat = false
        b.toggle_mode = true
        b.pressed.connect(_toggle_panel.bind(spec[0]))
        bar.add_child(b)
        _panel_btns[spec[0]] = b
    bar.add_child(VSeparator.new())
    _play_btn = ZenEditorPanel._tool_button("play", "Play / pause (SPACE)")
    _play_btn.flat = false
    _play_btn.pressed.connect(_toggle_play)
    bar.add_child(_play_btn)
    _autokey_btn = ZenEditorPanel._tool_button("auto-key", "Auto-key (K): edits write keys at the playhead")
    _autokey_btn.flat = false
    _autokey_btn.toggle_mode = true
    _autokey_btn.toggled.connect(func(on): _set_autokey(on))
    bar.add_child(_autokey_btn)
    _time = ZenUI.label("", ZenUI.TITLE)
    bar.add_child(_time)
    _title = ZenUI.label("", ZenUI.TITLE, 18)
    _title.size_flags_horizontal = SIZE_EXPAND_FILL
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _title.clip_text = true
    bar.add_child(_title)

    _work = Control.new()
    _work.size_flags_vertical = SIZE_EXPAND_FILL
    _work.clip_contents = true
    _work.resized.connect(_layout)
    rows.add_child(_work)
    _stage = ZenEditorStage.new()
    _stage.picked.connect(_on_pick)
    _stage.empty_clicked.connect(_on_stage_empty)
    _stage.drag_started.connect(_on_drag_start)
    _stage.dragged.connect(_on_drag)
    _stage.drag_ended.connect(_commit_live)
    _stage.play_pointer.connect(_on_play_pointer)
    _work.add_child(_stage)

    _p_elems = _add_panel("elements", "Elements", ZenEditorPanel.Edge.LEFT, 230)
    _build_elements(_p_elems.body)
    _p_insp = _add_panel("inspector", "Inspector", ZenEditorPanel.Edge.RIGHT, 310)
    var sc := ScrollContainer.new()
    sc.size_flags_vertical = SIZE_EXPAND_FILL
    sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _p_insp.body.add_child(sc)
    _insp = VBoxContainer.new()
    _insp.size_flags_horizontal = SIZE_EXPAND_FILL
    sc.add_child(_insp)
    _p_doc = _add_panel("document", "Document", ZenEditorPanel.Edge.RIGHT, 310)
    _build_doc(_p_doc.body)
    _p_tl = _add_panel("timeline", "Timeline", ZenEditorPanel.Edge.BOTTOM, 230)
    _build_timeline(_p_tl.body)
    _p_str = _add_panel("strings", "Strings", ZenEditorPanel.Edge.LEFT, 260)
    _build_strings(_p_str.body)
    _p_keys = _add_panel("keys", "Keys", ZenEditorPanel.Edge.RIGHT, 330)
    _build_keys(_p_keys.body)
    _p_sig = _add_panel("signals", "Signals", ZenEditorPanel.Edge.RIGHT, 330)
    _build_signals(_p_sig.body)

    _status = ZenUI.label("", ZenUI.TEXT)
    _status.clip_text = true
    rows.add_child(_status)
    var hint := ZenUI.label(ZenHotkeyHelp.footer([["zen_play", "play"], ["zen_edit_autokey", "auto-key"],
        ["zen_edit_save", "save"], ["zen_edit_undo", "undo"], ["zen_help", "help"],
        ["zen_back", "back"]]).strip_edges(), ZenUI.DIM)
    hint.clip_text = true
    rows.add_child(hint)
    add_child(_help)
    _build_dialogs()


func _add_panel(id: String, title: String, side: int, ext: float) -> ZenEditorPanel:
    var p := ZenEditorPanel.new(id, title, side, ext)
    p.state_changed.connect(_on_panel_state.bind(p))
    _work.add_child(p)
    _panels.append(p)
    return p


func _build_menus() -> void:
    var file := _popup("File", [
        ["New", _ask_new], ["Open...", _ask_open], ["Save", _save],
        ["Save as...", _ask_save_as], ["Rename...", _ask_rename], ["Delete...", _ask_delete_scene],
        [], ["Back to gallery", _request_leave]])
    _menu.add_child(file)
    _menu.add_child(_popup("Edit", [
        ["Undo", _do_undo], ["Redo", _do_redo], [],
        ["Toggle auto-key", func(): _set_autokey(not _autokey)],
        ["Delete selection", _delete_selection]]))
    _menu.add_child(_popup("Element", [
        ["Add text", _add_element.bind("text")], ["Add shape", _add_element.bind("shape")],
        ["Add global", _add_element.bind("global")], [],
        ["Duplicate", _duplicate_elements], ["Delete", _delete_elements], [],
        ["Move back (up the list)", _move_selected.bind(-1)],
        ["Move forward (down the list)", _move_selected.bind(1)]]))
    _menu.add_child(_popup("View", [
        ["Elements", _toggle_panel.bind("elements")], ["Inspector", _toggle_panel.bind("inspector")],
        ["Document", _toggle_panel.bind("document")], ["Timeline", _toggle_panel.bind("timeline")],
        ["Strings", _toggle_panel.bind("strings")], ["Keys", _toggle_panel.bind("keys")],
        ["Signals", _toggle_panel.bind("signals")],
        [], ["Fit timeline", func(): _tl.fit()], ["Unpin all panels", _unpin_all]]))


## A PopupMenu for the MenuBar: entries are [label, Callable], [] separates.
func _popup(title: String, entries: Array) -> PopupMenu:
    var pm := PopupMenu.new()
    pm.name = title
    var fns: Array = []
    for e in entries:
        if (e as Array).is_empty():
            pm.add_separator()
            fns.append(Callable())
            continue
        pm.add_item(String(e[0]), fns.size())
        fns.append(e[1])
    pm.id_pressed.connect(func(id): if (fns[id] as Callable).is_valid(): (fns[id] as Callable).call())
    return pm


func _build_elements(p: VBoxContainer) -> void:
    _tree = Tree.new()
    _tree.size_flags_vertical = SIZE_EXPAND_FILL
    _tree.hide_root = true
    _tree.select_mode = Tree.SELECT_MULTI
    _tree.allow_reselect = true
    _tree.multi_selected.connect(func(_i, _c, _s): _tree_selection_changed.call_deferred())
    _tree.item_activated.connect(_tree_begin_rename)
    _tree.item_edited.connect(_tree_renamed)
    _tree.set_drag_forwarding(_tree_get_drag, _tree_can_drop, _tree_drop)
    p.add_child(_tree)
    var g := HFlowContainer.new()
    p.add_child(g)
    for spec in [["+text", _add_element.bind("text")], ["+shape", _add_element.bind("shape")],
                 ["+global", _add_element.bind("global")], ["dup", _duplicate_elements],
                 ["delete", _delete_elements], ["up", _move_selected.bind(-1)],
                 ["down", _move_selected.bind(1)]]:
        var b := ZenEditorPanel._tool_button(spec[0], "")
        b.flat = false
        b.pressed.connect(spec[1])
        g.add_child(b)
    p.add_child(ZenUI.label("list order is draw order: last is in front", ZenUI.DIM, 11))


func _build_doc(p: VBoxContainer) -> void:
    var g := GridContainer.new()
    g.columns = 2
    p.add_child(g)
    _doc_rows["duration"] = _doc_spin(g, "duration", 0.1, 600.0, 0.01,
        func(v): _live("duration", func(): ZenDocOps.set_duration(_canvas, v)))
    _doc_rows["intro_end"] = _doc_spin(g, "intro_end", 0.0, 600.0, 0.01,
        func(v): _live("intro_end", func(): ZenDocOps.set_intro_end(_canvas, v)))
    _doc_rows["outro_start"] = _doc_spin(g, "outro_start", 0.0, 600.0, 0.01,
        func(v): _live("outro_start", func(): ZenDocOps.set_outro_start(_canvas, v)))
    _doc_rows["loop_blend"] = _doc_spin(g, "loop_blend", 0.0, 10.0, 0.01,
        func(v): _live("loop_blend", func(): _canvas.loop_blend = v))
    _doc_rows["loop_smooth"] = _doc_check(g, "loop_smooth", "blend the loop seam",
        func(on): _command("loop_smooth", func(): _canvas.loop_smooth = on))
    _doc_rows["loop_play"] = _doc_check(g, "loop_play", "playback wraps",
        func(on): _command("loop_play", func(): _canvas.loop_play = on))
    g.add_child(ZenUI.label("clear_color", ZenUI.TEXT))
    var cp := ColorPickerButton.new()
    cp.custom_minimum_size = Vector2(110, 24)
    cp.color_changed.connect(func(c): if not _syncing: _live("clear_color", func(): _canvas.clear_color = c))
    g.add_child(cp)
    _doc_rows["clear_color"] = cp
    g.add_child(ZenUI.label("canvas", ZenUI.TEXT))
    var cs := OptionButton.new()
    cs.tooltip_text = "Pixel grid the scene is drawn on. Fractional geometry keeps its place;\n" \
        + "absolute-unit elements and pixel shapes keep their pixel size."
    for preset in ZenCanvas.SIZE_PRESETS: cs.add_item(String(preset["label"]))
    cs.add_item("custom")            # only shown selected, for a size not offered
    cs.set_item_disabled(cs.item_count - 1, true)
    cs.item_selected.connect(_on_canvas_size_selected)
    g.add_child(cs)
    _doc_rows["design"] = cs
    g.add_child(ZenUI.label("pauses", ZenUI.TEXT))
    _doc_rows["pauses"] = ZenUI.label("", ZenUI.DIM)
    g.add_child(_doc_rows["pauses"])
    var note := ZenUI.label("Markers are also dragged on the timeline ruler; right-click it to add a pause.",
        ZenUI.DIM, 11)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD
    p.add_child(note)


func _doc_spin(g: GridContainer, text: String, lo: float, hi: float, step: float,
               fn: Callable) -> SpinBox:
    g.add_child(ZenUI.label(text, ZenUI.TEXT))
    var s := SpinBox.new()
    s.min_value = lo
    s.max_value = hi
    s.step = step
    s.custom_minimum_size = Vector2(110, 0)
    s.value_changed.connect(func(v): if not _syncing: fn.call(v))
    g.add_child(s)
    return s


func _doc_check(g: GridContainer, text: String, tip: String, fn: Callable) -> CheckBox:
    g.add_child(ZenUI.label(text, ZenUI.TEXT))
    var c := CheckBox.new()
    c.tooltip_text = tip
    c.focus_mode = FOCUS_NONE
    c.toggled.connect(func(on): if not _syncing: fn.call(on))
    g.add_child(c)
    return c


func _build_timeline(p: VBoxContainer) -> void:
    var bar := HBoxContainer.new()
    p.add_child(bar)
    for spec in [["|<", "Playhead to start (Home)", func(): _scrub_to(0.0)],
                 ["<", "Back one frame (Left)", func(): _scrub_to(_t - FRAME)],
                 [">", "Forward one frame (Right)", func(): _scrub_to(_t + FRAME)],
                 ["key", "Key the selected element's keyed props at the playhead", _key_all_here],
                 ["del key", "Delete the selected keys (DEL)", _delete_keys],
                 ["fit", "Fit the whole timeline (F)", func(): _tl.fit()]]:
        var b := ZenEditorPanel._tool_button(spec[0], spec[1])
        b.flat = false
        b.pressed.connect(spec[2])
        bar.add_child(b)
    bar.add_child(ZenUI.label("  drag keys (Ctrl snaps)   double-click: edit   Alt+click: column   "
        + "label: whole lane   Up/Down: next key   Ctrl+wheel zoom", ZenUI.DIM, 11))
    _tl = ZenTimelineView.new()
    _tl.size_flags_vertical = SIZE_EXPAND_FILL
    _tl.scrubbed.connect(_scrub_to)
    _tl.key_pressed.connect(_on_key_pressed)
    _tl.keys_drag_started.connect(_on_keys_drag_start)
    _tl.keys_dragged.connect(_on_keys_dragged)
    _tl.keys_drag_ended.connect(_commit_live)
    _tl.marker_dragged.connect(_on_marker_dragged)
    _tl.marker_drag_ended.connect(_commit_live)
    _tl.box_selected.connect(_on_box_selected)
    _tl.context_key.connect(_on_context_key)
    _tl.lane_selected.connect(_on_lane_selected)
    _tl.column_selected.connect(_on_column_selected)
    _tl.key_activated.connect(_on_key_activated)
    _tl.context_lane.connect(_on_context_lane)
    _tl.context_ruler.connect(_on_context_ruler)
    p.add_child(_tl)


func _build_dialogs() -> void:
    _ctx = PopupMenu.new()
    _ctx.id_pressed.connect(func(id): if _ctx_items.has(id): (_ctx_items[id] as Callable).call())
    add_child(_ctx)
    _ctx_ease = PopupMenu.new()
    _ctx_ease.name = "ease"
    _ctx.add_child(_ctx_ease)

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

    _confirm = ConfirmationDialog.new()
    _confirm.confirmed.connect(func(): if _confirm_fn.is_valid(): _confirm_fn.call())
    add_child(_confirm)

    _open_dialog = ConfirmationDialog.new()
    _open_dialog.title = "Open scene"
    _open_list = ItemList.new()
    _open_list.custom_minimum_size = Vector2(320, 320)
    _open_list.item_activated.connect(func(_i): _open_dialog.hide(); _on_open_ok())
    _open_dialog.add_child(_open_list)
    _open_dialog.confirmed.connect(_on_open_ok)
    add_child(_open_dialog)

    _leave_dialog = ConfirmationDialog.new()
    _leave_dialog.title = "Unsaved changes"
    _leave_dialog.ok_button_text = "Discard"
    _leave_dialog.add_button("Save", true, "save")
    _leave_dialog.custom_action.connect(_on_leave_action)
    _leave_dialog.confirmed.connect(func(): closed.emit())
    add_child(_leave_dialog)


# ---------------------------------------------------------------- string pool

func _build_strings(p: VBoxContainer) -> void:
    _str_list = ItemList.new()
    _str_list.size_flags_vertical = SIZE_EXPAND_FILL
    _str_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _str_list.item_selected.connect(func(ix):
        _str_sel = _str_list.get_item_metadata(ix)
        _refresh_strings())
    p.add_child(_str_list)
    _str_edit = TextEdit.new()
    _str_edit.custom_minimum_size = Vector2(0, 64)
    _str_edit.text_changed.connect(func():
        if _syncing or not ZenStringOps.pool(_canvas).has_index(_str_sel): return
        var i := _str_sel
        _live("words #%d" % i, func(): ZenStringOps.set_text(_canvas, i, _str_edit.text)))
    p.add_child(_str_edit)
    var g := HFlowContainer.new()
    p.add_child(g)
    for spec in [["add", "Add a new pool entry", _add_string],
                 ["assign", "Point the selected text elements at this entry (a key at the playhead when auto-key is on or they key `string`)", _assign_string],
                 ["delete", "Delete this entry - only when nothing uses it; it leaves a hole", _delete_string],
                 ["clean", "Remove every hole and renumber the pool, rewriting every reference", _clean_strings]]:
        var b := ZenEditorPanel._tool_button(spec[0], spec[1])
        b.flat = false
        b.pressed.connect(spec[2])
        g.add_child(b)
        _str_btns[spec[0]] = b
    _str_info = ZenUI.label("", ZenUI.DIM, 11)
    _str_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    p.add_child(_str_info)


## "#3  Just like a tree…  ×2" - an entry as the lists show it.
static func _string_label(i: int, words: String, users: int) -> String:
    var one := words.replace("\n", " / ").strip_edges()
    if one.length() > 34: one = one.substr(0, 33) + "…"
    if words.is_empty(): one = "(hole)" if users == 0 else "(empty)"
    return "#%d  %s  ×%d" % [i, one, users]


## Words for a new entry that no other entry already holds, so add() cannot
## fold it into an existing one.
func _fresh_words(base: String) -> String:
    var pool := ZenStringOps.pool(_canvas)
    if base.is_empty(): base = "TEXT"
    var w := base
    var n := 2
    while pool.find_text(w) >= 0:
        w = "%s %d" % [base, n]
        n += 1
    return w


## Rebuild the pool list. `keep_edit`: an edit is being typed, so the edit box
## is left alone (replacing its text would move the caret).
func _refresh_strings(keep_edit := false) -> void:
    if _str_list == null or _canvas == null: return
    var pool := ZenStringOps.pool(_canvas)
    var use := ZenStringOps.usage(_canvas)
    var holes := ZenStringOps.holes(_canvas)
    if not pool.has_index(_str_sel): _str_sel = -1
    _str_list.clear()
    for i in pool.entries.size():
        var ix := _str_list.add_item(_string_label(i, pool.at(i), int(use.get(i, 0))))
        _str_list.set_item_metadata(ix, i)
        _str_list.set_item_tooltip(ix, pool.at(i))
        if holes.has(i): _str_list.set_item_custom_fg_color(ix, ZenUI.DIM)
        if i == _str_sel: _str_list.select(ix)
    var has := _str_sel >= 0
    var users := int(use.get(_str_sel, 0)) if has else 0
    if not keep_edit:
        _syncing = true
        _str_edit.text = pool.at(_str_sel) if has else ""
        _syncing = false
    _str_edit.editable = has
    _str_btns["assign"].disabled = not has or _selected_texts().is_empty()
    _str_btns["delete"].disabled = not has or users > 0 or holes.has(_str_sel)
    _str_btns["clean"].text = "clean up holes (%d)" % holes.size()
    _str_btns["clean"].disabled = holes.is_empty()
    _str_info.text = "%d entries, %d holes. Text elements always show a pool entry; an edit changes it for everyone using it." % [
        pool.entries.size() - holes.size(), holes.size()]
    if has: _str_info.text = "#%d used by %d.  " % [_str_sel, users] + _str_info.text


func _selected_texts() -> Array:
    return _selected_nodes().filter(func(e): return e is ZenText)


func _add_string() -> void:
    var made := [-1]                    # a lambda captures locals by value
    _command("add words", func(): made[0] = ZenStringOps.add(_canvas, _fresh_words("new words")))
    _str_sel = made[0]
    _refresh_strings()


func _assign_string() -> void:
    var ts := _selected_texts()
    if ts.is_empty() or _str_sel < 0: return
    var i := _str_sel
    _command("words #%d" % i, func():
        for t in ts: ZenStringOps.assign(_canvas, t, i, _t, _autokey))


func _delete_string() -> void:
    var i := _str_sel
    if i < 0: return
    if ZenStringOps.users(_canvas, i) > 0:
        _set_status("#%d is still in use" % i)
        return
    _command("delete words #%d" % i, func(): ZenStringOps.remove(_canvas, i))


func _clean_strings() -> void:
    if ZenStringOps.holes(_canvas).is_empty(): return
    _str_sel = -1
    _command("clean up string holes", func(): ZenStringOps.compact(_canvas))


# ---------------------------------------------------------------- panels

func _panel(id: String) -> ZenEditorPanel:
    for p in _panels:
        if p.panel_id == id: return p
    return null


## Opening an unpinned panel closes the other unpinned panels on its side.
func _toggle_panel(id: String) -> void:
    var p := _panel(id)
    if p == null: return
    if not p.is_open and not p.pinned:
        for o in _panels:
            if o != p and o.side == p.side and o.is_open and not o.pinned: o.set_open(false)
    p.toggle()


func _unpin_all() -> void:
    for p in _panels: p.set_pinned(false)


func _close_unpinned() -> bool:
    var any := false
    for p in _panels:
        if p.is_open and not p.pinned:
            p.set_open(false)
            any = true
    return any


func _on_panel_state(p: ZenEditorPanel) -> void:
    if p == _p_keys and not p.is_open and not _key_sel.is_empty(): _keys_dismissed = true
    var b: Button = _panel_btns.get(p.panel_id)
    if b != null: b.set_pressed_no_signal(p.is_open)
    var st := ZenSettings.editor_state()
    var ps: Dictionary = st.get("panels", {})
    ps[p.panel_id] = p.state()
    st["panels"] = ps
    ZenSettings.set_editor_state(st)
    _layout()


## Place the panels and the canvas. Pinned panels reserve their edge; open
## panels on one side stack. While playing, the UNPINNED panels slide out by
## `_slide`; pinned ones stay, so a pinned timeline can be watched playing.
func _layout() -> void:
    if _work == null: return
    var w := _work.size.x
    var h := _work.size.y
    var bottom := _open_on(ZenEditorPanel.Edge.BOTTOM)
    var bot_h := 0.0
    var bot_shown := 0.0                # how much of the bottom edge is covered now
    for p in bottom:
        bot_h = maxf(bot_h, p.extent)
    bot_h = minf(bot_h, h * 0.6)
    for p in bottom:
        bot_shown = maxf(bot_shown, bot_h * (1.0 - _slide_of(p)))
    var reserve := {"l": 0.0, "r": 0.0, "b": 0.0}
    for p in _panels:
        if not (p.is_open and p.pinned): continue
        if p.side == ZenEditorPanel.Edge.LEFT: reserve["l"] = maxf(reserve["l"], p.extent)
        elif p.side == ZenEditorPanel.Edge.RIGHT: reserve["r"] = maxf(reserve["r"], p.extent)
        else: reserve["b"] = bot_h
    var side_h := h - bot_shown
    for s in [ZenEditorPanel.Edge.LEFT, ZenEditorPanel.Edge.RIGHT]:
        var ps := _open_on(s)
        for i in ps.size():
            var p: ZenEditorPanel = ps[i]
            var ph := side_h / ps.size()
            var out := _slide_of(p)
            var x := -p.extent * out if s == ZenEditorPanel.Edge.LEFT \
                else w - p.extent * (1.0 - out)
            p.position = Vector2(x, ph * i)
            p.size = Vector2(p.extent, ph)
    for p in bottom:
        p.position = Vector2(0, h - bot_h * (1.0 - _slide_of(p)))
        p.size = Vector2(w, bot_h)
    _stage.position = Vector2(reserve["l"], 0)
    _stage.size = Vector2(w - reserve["l"] - reserve["r"], h - reserve["b"])
    for p in _panels:
        # Above the stage in draw order, and gone once fully slid away.
        _work.move_child(p, -1)
        p.visible = p.is_open and _slide_of(p) < 0.999


## How far `p` is slid out for playback: never, once it is pinned.
func _slide_of(p: ZenEditorPanel) -> float:
    return 0.0 if p.pinned else _slide


func _open_on(s: int) -> Array:
    var out: Array = []
    for p in _panels:
        if p.side == s and p.is_open: out.append(p)
    return out


func _slide_to(v: float) -> void:
    if _slide_tween != null: _slide_tween.kill()
    _slide_tween = create_tween()
    _slide_tween.tween_method(func(x): _slide = x; _layout(), _slide, v, 0.25)


# ---------------------------------------------------------------- elements panel

func _refresh_tree() -> void:
    _tree.clear()
    var root := _tree.create_item()
    for e in ZenElemOps.rows(_canvas):
        var el := e as ZenElement
        var it := _tree.create_item(root)
        it.set_text(0, "%s  %s" % [el.zen_kind().substr(0, 1).to_upper(), el.elem_name])
        it.set_metadata(0, el.elem_name)
        it.set_tooltip_text(0, "%s %s (node %s, z %d)" % [el.zen_kind(), el.elem_name, el.name, el.z_index])
        if _sel.has(el.elem_name): it.select(0)


func _tree_selection_changed() -> void:
    var names: Array[String] = []
    var it := _tree.get_next_selected(null)
    while it != null:
        names.append(String(it.get_metadata(0)))
        it = _tree.get_next_selected(it)
    # Keep the pick order for what stays selected; the newest goes last.
    var keep: Array[String] = []
    for n in _sel:
        if names.has(n): keep.append(n)
    for n in names:
        if not keep.has(n): keep.append(n)
    if keep == _sel: return
    _sel = keep
    _on_selection_changed(false)


func _tree_begin_rename() -> void:
    var it := _tree.get_selected()
    if it == null: return
    it.set_text(0, String(it.get_metadata(0)))
    it.set_editable(0, true)
    _tree.edit_selected(true)


func _tree_renamed() -> void:
    var it := _tree.get_edited()
    if it == null: return
    it.set_editable(0, false)
    var old := String(it.get_metadata(0))
    var nm := it.get_text(0).strip_edges()
    var el := ZenElemOps.find(_canvas, old)
    if el == null or nm == old or nm.is_empty():
        _refresh_tree.call_deferred()
        return
    if not ZenElemOps.is_name_free(_canvas, nm):
        _set_status("an element called %s already exists" % nm)
        _refresh_tree.call_deferred()
        return
    _rename_element.call_deferred(el, nm)


func _rename_element(el: ZenElement, nm: String) -> void:
    var old := el.elem_name
    _command("rename %s -> %s" % [old, nm], func():
        ZenElemOps.rename(_canvas, el, nm)
        var i := _sel.find(old)
        if i >= 0: _sel[i] = nm)


func _tree_get_drag(at: Vector2) -> Variant:
    var it := _tree.get_item_at_position(at)
    if it == null: return null
    _tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
    var l := ZenUI.label(String(it.get_metadata(0)), ZenUI.TITLE)
    _tree.set_drag_preview(l)
    return {"zen_elem": String(it.get_metadata(0))}


func _tree_can_drop(_at: Vector2, data: Variant) -> bool:
    return data is Dictionary and (data as Dictionary).has("zen_elem")


func _tree_drop(at: Vector2, data: Variant) -> void:
    _tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
    var el := ZenElemOps.find(_canvas, String(data["zen_elem"]))
    if el == null: return
    var it := _tree.get_item_at_position(at)
    var rows := ZenElemOps.rows(_canvas)
    var to := rows.size() - 1
    if it != null:
        var target := ZenElemOps.find(_canvas, String(it.get_metadata(0)))
        to = rows.find(target)
        var from := rows.find(el)
        # Dropped below an item lands after it.
        if _tree.get_drop_section_at_position(at) > 0: to += 1
        if from < to: to -= 1
    _command("reorder %s" % el.elem_name, func(): ZenElemOps.move(_canvas, el, to))


func _add_element(kind: String) -> void:
    var made: Array = [null]
    _command("add %s" % kind, func():
        made[0] = ZenElemOps.add(_canvas, kind)
        _sel.assign([(made[0] as ZenElement).elem_name]))
    _key_sel.clear()
    _on_selection_changed(true)


func _duplicate_elements() -> void:
    var ns := _selected_nodes()
    if ns.is_empty(): return
    _command("duplicate", func():
        var out: Array[String] = []
        for el in ns: out.append(ZenElemOps.duplicate_elem(_canvas, el).elem_name)
        _sel = out)
    _on_selection_changed(true)


func _delete_elements() -> void:
    var ns := _selected_nodes()
    if ns.is_empty(): return
    _command("delete %s" % ", ".join(_sel), func():
        for el in ns: ZenElemOps.remove(_canvas, el)
        _sel.clear())
    _key_sel.clear()
    _on_selection_changed(true)


func _move_selected(dir: int) -> void:
    var el := _primary()
    if el == null: return
    var rows := ZenElemOps.rows(_canvas)
    var to := rows.find(ZenElemOps.row_of(_canvas, el)) + dir
    if to < 0 or to >= rows.size(): return
    _command("move %s" % el.elem_name, func(): ZenElemOps.move(_canvas, el, to))


func _on_selection_changed(rebuild_tree: bool) -> void:
    if rebuild_tree: _refresh_tree.call_deferred()
    _key_sel.clear()
    _build_inspector.call_deferred()
    _refresh_timeline()
    _refresh_strings()
    _stage.selected = _selected_nodes()


# ---------------------------------------------------------------- stage

func _on_pick(el: ZenElement, additive: bool) -> void:
    var nm := ZenElemOps.row_of(_canvas, el).elem_name
    if additive:
        if _sel.has(nm): _sel.erase(nm)
        else: _sel.append(nm)
    else:
        _sel.assign([nm])
    _on_selection_changed(true)


func _on_stage_empty() -> void:
    if _close_unpinned(): return
    if _sel.is_empty(): return
    _sel.clear()
    _on_selection_changed(true)


func _on_drag_start() -> void:
    _drag_from.clear()
    for el in _selected_nodes():
        var e := el as ZenElement
        _drag_from[e.elem_name] = Vector2(float(_value_at(_owner_of(e, "pos_x"), "pos_x", _t)),
                                          float(_value_at(_owner_of(e, "pos_y"), "pos_y", _t)))


func _on_drag(delta: Vector2) -> void:
    _live("move", func():
        for nm in _drag_from:
            var el := ZenElemOps.find(_canvas, nm)
            if el == null: continue
            var p: Vector2 = _drag_from[nm] + delta
            _write_prop(el, "pos_x", p.x)
            _write_prop(el, "pos_y", p.y))


## Write one prop the way auto-key says: a key at the playhead, or the base
## pose. Returns false when the write is refused (keyed, auto-key off).
func _write_prop(el: ZenElement, prop: String, v: Variant) -> bool:
    var node := _owner_of(el, prop)
    # A signal has no base pose to write: its edits are always keys.
    if _autokey or _sig_edit != "":
        if _sig_edit != "" and ZenProps.is_stepped(prop):
            _set_status("signals never drive %s" % prop)
            return false
        ZenKeyOps.key_at_playhead(_canvas, node, prop, _t, v)
        return true
    if ZenKeyOps.has_track(_canvas, node, prop):
        _set_status("%s is keyed - turn on auto-key (K) to change it at the playhead" % prop)
        return false
    if v is Color: node.set_base_color(prop, v)
    else: node.set_base_scalar(prop, float(v))
    return true


## The node of `el`'s element that owns `prop` (a global's two halves split
## its props).
func _owner_of(el: ZenElement, prop: String) -> ZenElement:
    for h in ZenElemOps.halves(_canvas, el):
        if (h as ZenElement).owns(prop): return h
    return el


# ---------------------------------------------------------------- inspector

func _build_inspector() -> void:
    for c in _insp.get_children():
        _insp.remove_child(c)
        c.queue_free()
    _insp_rows.clear()
    var el := _primary()
    if el == null:
        _insp.add_child(ZenUI.label("nothing selected", ZenUI.DIM))
        return
    if _sel.size() > 1:
        _insp.add_child(ZenUI.label("%d selected - showing %s" % [_sel.size(), el.elem_name], ZenUI.DIM, 11))
    var g := GridContainer.new()
    g.columns = 2
    g.add_theme_constant_override("h_separation", 6)
    _insp.add_child(g)
    g.add_child(ZenUI.label("name", ZenUI.LABEL))
    var ne := LineEdit.new()
    ne.text = el.elem_name
    ne.size_flags_horizontal = SIZE_EXPAND_FILL
    ne.text_submitted.connect(func(t): _rename_from_field(el, t))
    ne.focus_exited.connect(func(): _rename_from_field(el, ne.text))
    g.add_child(ne)
    g.add_child(ZenUI.label("kind", ZenUI.LABEL))
    g.add_child(ZenUI.label(el.zen_kind(), ZenUI.TEXT))

    if el is ZenShape: _inspect_shape(g, el as ZenShape)
    elif el is ZenText: _inspect_text(el as ZenText)

    _insp.add_child(HSeparator.new())
    _insp.add_child(ZenUI.label("◆ key here   ◈ keyed   ◇ not keyed  (click to key / unkey)", ZenUI.DIM, 11))
    var pg := GridContainer.new()
    pg.columns = 3
    pg.add_theme_constant_override("h_separation", 4)
    _insp.add_child(pg)
    var props: Array = PROPS.get(el.zen_kind(), [])
    if el is ZenShape and (el as ZenShape).shape_kind == ZenShape.Kind.CUSTOM:
        props = props + ["shape_id"]
    for prop in props:
        _prop_row(pg, el, String(prop))
    _refresh_inspector_values()


func _rename_from_field(el: ZenElement, t: String) -> void:
    t = t.strip_edges()
    if not is_instance_valid(el) or t == el.elem_name or t.is_empty(): return
    if not ZenElemOps.is_name_free(_canvas, t):
        _set_status("an element called %s already exists" % t)
        return
    _rename_element.call_deferred(el, t)


func _inspect_shape(g: GridContainer, s: ZenShape) -> void:
    g.add_child(ZenUI.label("shape", ZenUI.LABEL))
    var ob := OptionButton.new()
    for k in ZenShape.KIND_NAMES: ob.add_item(k)
    ob.selected = s.shape_kind
    ob.item_selected.connect(func(i): _command("shape kind", func():
        s.shape_kind = i as ZenShape.Kind
        s.queue_redraw()))
    g.add_child(ob)
    _base_check(g, "unit_abs", "sizes in canvas pixels, not fractions", s.unit_abs,
        func(on): _command("unit_abs", func(): s.unit_abs = on))
    if s.shape_kind == ZenShape.Kind.CIRCLE:
        _base_check(g, "outline_crisp", "circle rim as a smooth ring", s.outline_crisp,
            func(on): _command("outline_crisp", func(): s.outline_crisp = on))
    if s.shape_kind == ZenShape.Kind.CUSTOM:
        g.add_child(ZenUI.label("asset", ZenUI.LABEL))
        var ab := OptionButton.new()
        var names := ZenAssets.shape_names()
        ab.add_item("(none)")
        for n in names: ab.add_item(String(n))
        ab.selected = names.find(s.shape_name) + 1
        ab.item_selected.connect(func(i): _command("asset", func():
            s.shape_name = "" if i == 0 else String(names[i - 1])
            s.shape = null if i == 0 else ZenAssets.load_shape(s.shape_name)))
        g.add_child(ab)


## A text's words are ALWAYS a pool entry. The picker shows the entry on
## screen at the playhead; the box edits THAT entry in place, so every element
## and key sharing it follows (the count says how many); "new" gives this
## element an entry of its own.
func _inspect_text(t: ZenText) -> void:
    var pool := ZenStringOps.pool(_canvas)
    var use := ZenStringOps.usage(_canvas)
    var cur := t.string_index_at(_pose_t())
    var head := HBoxContainer.new()
    _insp.add_child(head)
    var wl := ZenUI.label("words", ZenUI.LABEL)
    wl.size_flags_horizontal = SIZE_EXPAND_FILL
    head.add_child(wl)
    var n := int(use.get(cur, 0))
    head.add_child(ZenUI.label("#%d  used by %d" % [cur, n], ZenUI.TITLE if n > 1 else ZenUI.DIM, 11))
    var row := HBoxContainer.new()
    _insp.add_child(row)
    var ob := OptionButton.new()
    ob.size_flags_horizontal = SIZE_EXPAND_FILL
    ob.clip_text = true
    ob.fit_to_longest_item = false
    var holes := ZenStringOps.holes(_canvas)
    for i in pool.entries.size():
        if holes.has(i) and i != cur: continue
        ob.add_item(_string_label(i, pool.at(i), int(use.get(i, 0))), i)
    ob.select(ob.get_item_index(cur))
    ob.item_selected.connect(func(ix): _command("%s words #%d" % [t.elem_name, ob.get_item_id(ix)],
        func(): ZenStringOps.assign(_canvas, t, ob.get_item_id(ix), _t, _autokey)))
    row.add_child(ob)
    var nb := ZenEditorPanel._tool_button("new", "Give this element a new pool entry of its own")
    nb.flat = false
    nb.pressed.connect(func(): _command("%s new words" % t.elem_name, func():
        ZenStringOps.assign(_canvas, t, ZenStringOps.add(_canvas, _fresh_words(pool.at(cur))),
            _t, _autokey)))
    row.add_child(nb)
    var te := TextEdit.new()
    te.text = pool.at(cur)
    te.custom_minimum_size = Vector2(0, 54)
    te.tooltip_text = "Edits pool entry #%d in place - every element and key using it follows" % cur
    te.text_changed.connect(func(): _live("words #%d" % cur, func():
        ZenStringOps.set_text(_canvas, cur, te.text)))
    _insp.add_child(te)
    var g := GridContainer.new()
    g.columns = 2
    _insp.add_child(g)
    _base_check(g, "unit_abs", "size in canvas pixels, not a fraction of height", t.unit_abs,
        func(on): _command("unit_abs", func(): t.unit_abs = on))


func _base_check(g: GridContainer, text: String, tip: String, on: bool, fn: Callable) -> void:
    g.add_child(ZenUI.label(text, ZenUI.LABEL))
    var c := CheckBox.new()
    c.button_pressed = on
    c.tooltip_text = tip
    c.focus_mode = FOCUS_NONE
    c.toggled.connect(fn)
    g.add_child(c)


func _prop_row(g: GridContainer, el: ZenElement, prop: String) -> void:
    var node := _owner_of(el, prop)
    var key := ZenEditorPanel._tool_button("◇", "Key %s at the playhead / remove its key here" % prop)
    key.pressed.connect(_toggle_key.bind(node, prop))
    g.add_child(key)
    g.add_child(ZenUI.label(prop, ZenUI.TEXT))
    var editor: Control
    if ZenProps.is_color(prop):
        var cp := ColorPickerButton.new()
        cp.edit_alpha = false
        cp.custom_minimum_size = Vector2(120, 24)
        cp.color_changed.connect(func(c): if not _syncing: _live("%s %s" % [el.elem_name, prop],
            func(): _write_prop(node, prop, Color(c.r, c.g, c.b, 1.0))))
        editor = cp
    else:
        var r: Array = RANGES.get(prop, [-1000.0, 1000.0, 0.01])
        var s := SpinBox.new()
        s.min_value = r[0]
        s.max_value = r[1]
        s.step = r[2]
        s.allow_greater = true
        s.allow_lesser = true
        s.custom_minimum_size = Vector2(120, 0)
        s.value_changed.connect(func(v): if not _syncing: _live("%s %s" % [el.elem_name, prop],
            func(): _write_prop(node, prop, v)))
        editor = s
    g.add_child(editor)
    _insp_rows.append({"prop": prop, "node": node, "editor": editor, "key": key})


## Values at the playhead into the inspector's controls, without rebuilding.
func _refresh_inspector_values() -> void:
    _syncing = true
    for r in _insp_rows:
        var node: ZenElement = r["node"]
        if not is_instance_valid(node): continue
        var prop := String(r["prop"])
        var keyed := ZenKeyOps.has_track(_canvas, node, prop)
        var here := keyed and ZenKeyOps.key_at(_canvas, node, prop, _t) >= 0
        var kb: Button = r["key"]
        kb.text = "◆" if here else ("◈" if keyed else "◇")
        kb.modulate = ZenUI.TITLE if keyed else ZenUI.DIM
        var ed: Control = r["editor"]
        var free := not keyed or _autokey or _sig_edit != ""
        if ed is ColorPickerButton:
            (ed as ColorPickerButton).color = _value_at(node, prop, _t)
            (ed as ColorPickerButton).disabled = not free
        else:
            (ed as SpinBox).set_value_no_signal(float(_value_at(node, prop, _t)))
            (ed as SpinBox).editable = free
    _syncing = false


func _toggle_key(node: ZenElement, prop: String) -> void:
    if not is_instance_valid(node): return
    var i := ZenKeyOps.key_at(_canvas, node, prop, _t)
    if i >= 0:
        _command("unkey %s" % prop, func(): ZenKeyOps.remove(_canvas, node, prop, i))
        return
    var v: Variant = _value_at(node, prop, _t)
    _command("key %s" % prop, func(): ZenKeyOps.key_at_playhead(_canvas, node, prop, _t, v))


## Key every keyed prop of the selection at the playhead with its current value.
func _key_all_here() -> void:
    var ns := _selected_nodes()
    if ns.is_empty(): return
    _command("key at %.2fs" % _t, func():
        for el in ns:
            for h in ZenElemOps.halves(_canvas, el):
                for prop in ZenKeyOps.keyed_props(_canvas, h):
                    var node := h as ZenElement
                    ZenKeyOps.insert(_canvas, node, prop, _t, _value_at(node, prop, _t)))


func _set_autokey(on: bool) -> void:
    _autokey = on
    var st := ZenSettings.editor_state()
    st["autokey"] = on
    ZenSettings.set_editor_state(st)
    _sync_autokey()
    _refresh_inspector_values()
    _set_status("auto-key %s" % ("ON - edits write keys at the playhead" if on else "off - edits change the base pose"))


func _sync_autokey() -> void:
    if _autokey_btn == null: return
    _autokey_btn.set_pressed_no_signal(_autokey)
    _autokey_btn.modulate = ZenUI.WARN if _autokey else Color.WHITE


# ---------------------------------------------------------------- document

func _refresh_doc() -> void:
    if _canvas == null: return
    _syncing = true
    (_doc_rows["duration"] as SpinBox).set_value_no_signal(_canvas.duration)
    (_doc_rows["intro_end"] as SpinBox).set_value_no_signal(_canvas.intro_end)
    (_doc_rows["outro_start"] as SpinBox).set_value_no_signal(_canvas.outro_start)
    (_doc_rows["loop_blend"] as SpinBox).set_value_no_signal(_canvas.loop_blend)
    (_doc_rows["loop_smooth"] as CheckBox).set_pressed_no_signal(_canvas.loop_smooth)
    (_doc_rows["loop_play"] as CheckBox).set_pressed_no_signal(_canvas.loop_play)
    (_doc_rows["clear_color"] as ColorPickerButton).color = _canvas.clear_color
    var cs := _doc_rows["design"] as OptionButton
    var pi := ZenCanvas.preset_index(_canvas.design_size)
    cs.set_item_text(cs.item_count - 1, "%d x %d  custom" % [int(_canvas.design_size.x), int(_canvas.design_size.y)])
    cs.select(pi if pi >= 0 else cs.item_count - 1)
    (_doc_rows["pauses"] as Label).text = "%d" % _canvas.pauses.size()
    _syncing = false


## Resize the canvas to a preset. Geometry is stored as fractions of the
## canvas, so nothing is rewritten: at the same aspect the composition is
## unchanged, but a new aspect stretches shapes, and absolute-unit elements and
## pixel shapes keep their pixel size - which the status line says.
func _on_canvas_size_selected(idx: int) -> void:
    if _syncing or idx >= ZenCanvas.SIZE_PRESETS.size(): return
    var size: Vector2 = ZenCanvas.SIZE_PRESETS[idx]["size"]
    var old := _canvas.design_size
    if size == old: return
    _command("canvas %d x %d" % [int(size.x), int(size.y)], func(): _canvas.design_size = size)
    if not is_equal_approx(size.x / size.y, old.x / old.y):
        _set_status("canvas %d x %d - new aspect: shapes stretch, absolute-unit sizes stay in pixels"
            % [int(size.x), int(size.y)])
    else:
        _set_status("canvas %d x %d - absolute-unit sizes and pixel shapes stay in pixels"
            % [int(size.x), int(size.y)])


# ---------------------------------------------------------------- timeline

## The lanes: one per keyed prop of each selected element (both halves of a
## global), each with its authored keys and a sampled sparkline.
func _refresh_timeline() -> void:
    if _canvas == null: return
    var lanes: Array = []
    _lanes.clear()
    var shown := _selected_nodes()
    # A signal's keys show for every element it animates, picked or not.
    if _sig_edit != "":
        for el in ZenElemOps.rows(_canvas):
            if shown.has(el): continue
            for h in ZenElemOps.halves(_canvas, el):
                if not ZenKeyOps.keyed_props(_canvas, h).is_empty():
                    shown.append(el)
                    break
    var multi := shown.size() > 1
    for el in shown:
        for h in ZenElemOps.halves(_canvas, el):
            var node := h as ZenElement
            for prop in ZenKeyOps.keyed_props(_canvas, node):
                lanes.append({"label": ("%s.%s" % [node.elem_name, prop]) if multi else prop,
                    "keys": ZenKeyOps.keys(_canvas, node, prop),
                    "samples": _samples(node, prop),
                    "lane_color": ZenUI.LABEL})
                _lanes.append({"node": String(node.name), "prop": prop})
    # Drop selected keys that no longer exist.
    for id in _key_sel.keys():
        var p := ZenKeyPanel.split_id(id)
        var li := _lane_index(p[0])
        if li < 0 or p[1] >= (lanes[li]["keys"] as Array).size(): _key_sel.erase(id)
    if _key_sel.is_empty(): _keys_dismissed = false
    _tl.selection = _view_selection()
    _tl.playhead = _t
    var span := ZenKeyOps.anim_of(_canvas).length
    if _sig_edit != "":
        _tl.set_model(lanes, span, 0.0, span, [])      # a signal has no markers
    else:
        _tl.set_model(lanes, span, _canvas.intro_end, _canvas.outro_start, _canvas.pauses)
    _sync_time()
    _refresh_keys()


func _samples(node: ZenElement, prop: String) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var span_t := ZenKeyOps.anim_of(_canvas).length
    var lo := INF
    var hi := -INF
    for i in SAMPLES:
        var t := span_t * float(i) / float(SAMPLES - 1)
        var x: Variant = _value_at(node, prop, t)
        var v: float = (x as Color).get_luminance() if x is Color else float(x)
        out.append(v)
        lo = minf(lo, v)
        hi = maxf(hi, v)
    var span := hi - lo
    for i in out.size():
        out[i] = 0.5 if span < 1e-6 else (out[i] - lo) / span
    return out


func _lane_node(lane: int) -> ZenElement:
    if lane < 0 or lane >= _lanes.size(): return null
    return _canvas.get_node_or_null(NodePath(String(_lanes[lane]["node"]))) as ZenElement


func _lane_prop(lane: int) -> String:
    return String(_lanes[lane]["prop"])


func _scrub_to(t: float) -> void:
    _stop()
    _t = clampf(t, 0.0, ZenKeyOps.anim_of(_canvas).length)
    _pose()
    _stage.time = _pose_t()
    _tl.playhead = _t
    _tl.queue_redraw()
    _refresh_inspector_values()
    _sync_time()
    _refresh_keys()


func _sync_time() -> void:
    if _time == null or _canvas == null: return
    if _sig_edit != "":
        _time.text = "signal %s  %.2f / %.2fs" % [_sig_edit, _t, ZenKeyOps.anim_of(_canvas).length]
    else:
        _time.text = "%.2f / %.2fs" % [_t, _canvas.duration]


# ---------------------------------------------------------------- key selection
#
# A selected key is "node|prop|idx" (ZenKeyPanel.split_id splits it); a lane
# id is "node|prop". The timeline view still speaks "lane:idx", translated by
# _view_selection().

func _lane_id(lane: int) -> String:
    return "%s|%s" % [_lanes[lane]["node"], _lanes[lane]["prop"]]


func _sel_id(lane: int, idx: int) -> String:
    return "%s|%d" % [_lane_id(lane), idx]


func _lane_index(lane_id: String) -> int:
    for i in _lanes.size():
        if _lane_id(i) == lane_id: return i
    return -1


func _id_node(lane_id: String) -> ZenElement:
    return _canvas.get_node_or_null(NodePath(lane_id.rsplit("|", true, 1)[0])) as ZenElement


static func _id_prop(lane_id: String) -> String:
    return lane_id.rsplit("|", true, 1)[1]


func _view_selection() -> Dictionary:
    var out := {}
    for id in _key_sel:
        var p := ZenKeyPanel.split_id(id)
        var li := _lane_index(p[0])
        if li >= 0: out["%d:%d" % [li, p[1]]] = true
    return out


## Selected keys grouped by lane: lane_id -> [idx ascending].
func _selected_keys() -> Dictionary:
    var out := {}
    for id in _key_sel:
        var p := ZenKeyPanel.split_id(id)
        if not out.has(p[0]): out[p[0]] = []
        (out[p[0]] as Array).append(p[1])
    for lane_id in out: (out[lane_id] as Array).sort()
    return out


## Pick `ids`. Additive adds them - or, for one id already picked, drops it.
func _select_ids(ids: Array, additive: bool) -> void:
    if not additive: _key_sel.clear()
    if additive and ids.size() == 1 and _key_sel.has(ids[0]): _key_sel.erase(ids[0])
    else:
        for id in ids: _key_sel[id] = true
    _after_key_sel()


## The selection changed: show it, and summon the Keys panel for it unless
## it was closed while these keys were picked.
func _after_key_sel() -> void:
    if _key_sel.is_empty(): _keys_dismissed = false
    elif not _p_keys.is_open and not _keys_dismissed: _toggle_panel("keys")
    _tl.selection = _view_selection()
    _tl.queue_redraw()
    _refresh_keys()


func _on_key_pressed(lane: int, idx: int, additive: bool) -> void:
    var id := _sel_id(lane, idx)
    if additive or not _key_sel.has(id): _select_ids([id], additive)
    var k: Dictionary = (_tl.lanes[lane]["keys"] as Array)[idx]
    _set_status("%s  key %d  t %.3f  ease %s" % [_lane_prop(lane), idx, float(k["t"]), String(k["ease"])])


func _on_box_selected(keys: Array, additive: bool) -> void:
    var ids: Array = []
    for k in keys: ids.append(_sel_id(k[0], k[1]))
    if not additive: _key_sel.clear()
    for id in ids: _key_sel[id] = true
    _after_key_sel()


func _lane_ids(lane: int) -> Array:
    var ids: Array = []
    for j in (_tl.lanes[lane]["keys"] as Array).size(): ids.append(_sel_id(lane, j))
    return ids


func _on_lane_selected(lane: int, additive: bool) -> void:
    if not additive: _key_sel.clear()
    for id in _lane_ids(lane): _key_sel[id] = true
    _after_key_sel()


## Every visible key at `t`.
func _column_ids(t: float) -> Array:
    var ids: Array = []
    for i in _tl.lanes.size():
        var ks: Array = _tl.lanes[i]["keys"]
        for j in ks.size():
            if absf(float(ks[j]["t"]) - t) < 1e-4: ids.append(_sel_id(i, j))
    return ids


func _on_column_selected(t: float, additive: bool) -> void:
    if not additive: _key_sel.clear()
    for id in _column_ids(t): _key_sel[id] = true
    _after_key_sel()


func _on_key_activated(lane: int, idx: int) -> void:
    _keys_dismissed = false
    _select_ids([_sel_id(lane, idx)], false)
    if not _p_keys.is_open: _toggle_panel("keys")
    _scrub_to(float((_tl.lanes[lane]["keys"] as Array)[idx]["t"]))


func _select_all_keys() -> void:
    _key_sel.clear()
    for i in _tl.lanes.size():
        for id in _lane_ids(i): _key_sel[id] = true
    _after_key_sel()


func _clear_keys() -> void:
    _key_sel.clear()
    _after_key_sel()


## Playhead to the previous / next key time of any visible lane, picking the
## keys there - stepping through keys without aiming at a diamond.
func _jump_key(dir: int) -> void:
    var best := INF if dir > 0 else -INF
    for ln in _tl.lanes:
        for k in ln["keys"]:
            var t := float(k["t"])
            if dir > 0 and t > _t + 1e-4: best = minf(best, t)
            elif dir < 0 and t < _t - 1e-4: best = maxf(best, t)
    if is_inf(best): return
    _scrub_to(best)
    _key_sel.clear()
    for id in _column_ids(best): _key_sel[id] = true
    _after_key_sel()


# ---------------------------------------------------------------- Keys panel

func _build_keys(p: VBoxContainer) -> void:
    _keys = ZenKeyPanel.new()
    _keys.select_requested.connect(_select_ids)
    _keys.seek_requested.connect(_scrub_to)
    _keys.time_shift.connect(_shift_keys)
    _keys.time_stretch.connect(_stretch_keys)
    _keys.value_set.connect(_set_key_values)
    _keys.ease_set.connect(_set_ease)
    _keys.delete_requested.connect(_delete_keys)
    _keys.duplicate_requested.connect(_copy_keys_to_playhead)
    _keys.key_here_requested.connect(_key_lanes_here)
    _keys.step_requested.connect(_step_keys)
    p.add_child(_keys)


func _refresh_keys() -> void:
    if _keys == null or _canvas == null: return
    var lanes: Array = []
    var strings: Array = []
    for i in _lanes.size():
        var prop := _lane_prop(i)
        var ln := {"id": _lane_id(i), "label": _tl.lanes[i]["label"], "prop": prop,
                   "keys": _tl.lanes[i]["keys"], "range": RANGES.get(prop, [-1000.0, 1000.0, 0.01])}
        if prop == "string":
            if strings.is_empty(): strings = _string_choices()
            ln["strings"] = strings
        lanes.append(ln)
    _keys.set_model(lanes, _key_sel, _t, _key_preview())


## [[idx, label]] for every pool entry a key can switch to (holes skipped).
func _string_choices() -> Array:
    var pool := ZenStringOps.pool(_canvas)
    var use := ZenStringOps.usage(_canvas)
    var holes := ZenStringOps.holes(_canvas)
    var out: Array = []
    for i in pool.entries.size():
        if not holes.has(i): out.append([i, _string_label(i, pool.at(i), int(use.get(i, 0)))])
    return out


## One selected key: its real incoming segment, 0 at the previous key's value
## and 1 at its own, sampled from what plays. Colours follow the channel that
## changes most.
func _key_preview() -> Dictionary:
    if _key_sel.size() != 1: return {}
    var p := ZenKeyPanel.split_id(_key_sel.keys()[0])
    var node := _id_node(p[0])
    var prop := _id_prop(p[0])
    if node == null or p[1] == 0 or ZenProps.is_stepped(prop): return {}
    var ks := ZenKeyOps.keys(_canvas, node, prop)
    if p[1] >= ks.size(): return {}
    var t0 := float(ks[p[1] - 1]["t"])
    var t1 := float(ks[p[1]]["t"])
    var ch := 0
    if ZenProps.is_color(prop):
        var a: Color = ks[p[1] - 1]["v"]
        var b: Color = ks[p[1]]["v"]
        var d := [absf(b.r - a.r), absf(b.g - a.g), absf(b.b - a.b)]
        ch = d.find(d.max())
    var at := func(t: float) -> float:
        var x: Variant = _value_at(node, prop, t)
        return (x as Color)[ch] if x is Color else float(x)
    var v0: float = at.call(t0)
    var v1: float = at.call(t1)
    if absf(v1 - v0) < 1e-6: return {}
    var out := PackedFloat32Array()
    for i in 41:
        out.append((float(at.call(lerpf(t0, t1, float(i) / 40.0))) - v0) / (v1 - v0))
    return {"samples": out}


## Move every selected key to fn(its time), one set_times per prop.
func _retime_keys(fn: Callable) -> void:
    var by_lane := _selected_keys()
    if by_lane.is_empty(): return
    _live("move keys", func():
        for lane_id in by_lane:
            var node := _id_node(lane_id)
            if node == null: continue
            var prop := _id_prop(lane_id)
            var ks := ZenKeyOps.keys(_canvas, node, prop)
            var idxs: Array = by_lane[lane_id]
            var times: Array = idxs.map(func(i): return fn.call(float(ks[i]["t"])))
            ZenKeyOps.set_times(_canvas, node, prop, idxs, times))


func _shift_keys(dt: float) -> void:
    _retime_keys(func(t): return t + dt)


func _stretch_keys(f: float) -> void:
    var t0 := INF
    for lane_id in _selected_keys():
        var node := _id_node(lane_id)
        if node == null: continue
        var ks := ZenKeyOps.keys(_canvas, node, _id_prop(lane_id))
        for i in _selected_keys()[lane_id]: t0 = minf(t0, float(ks[i]["t"]))
    if is_inf(t0): return
    _retime_keys(func(t): return t0 + (t - t0) * f)


## One value for every selected key of `lane_id`. Stepped values (a pool
## entry, a shape) are a pick, not a drag: one undo step each.
func _set_key_values(lane_id: String, v: Variant) -> void:
    var node := _id_node(lane_id)
    var idxs: Array = _selected_keys().get(lane_id, [])
    if node == null or idxs.is_empty(): return
    var prop := _id_prop(lane_id)
    var fn := func():
        for i in idxs: ZenKeyOps.set_value(_canvas, node, prop, i, v)
    if prop == "string": _command("%s key value" % prop, fn)
    else: _live("%s %s key value" % [node.elem_name, prop], fn)


## Key each selected prop at the playhead with what plays there, and pick the
## new keys.
func _key_lanes_here() -> void:
    var by_lane := _selected_keys()
    if by_lane.is_empty(): return
    var picked: Array = []
    _command("key at %.2fs" % _t, func():
        for lane_id in by_lane:
            var node := _id_node(lane_id)
            if node == null: continue
            var prop := _id_prop(lane_id)
            if ZenKeyOps.key_at(_canvas, node, prop, _t) >= 0: continue
            var v: Variant = node.plain_prop_color(prop, _t, node.base_color(prop), 1.0) \
                if ZenProps.is_color(prop) else node.plain_prop(prop, _t, node.base_scalar(prop))
            picked.append("%s|%d" % [lane_id, ZenKeyOps.insert(_canvas, node, prop, _t, v)]))
    if not picked.is_empty(): _select_ids(picked, false)


## Each selected key hands its place to its neighbour along its lane.
func _step_keys(dir: int) -> void:
    var by_lane := _selected_keys()
    var ids: Array = []
    var first := INF
    for lane_id in by_lane:
        var li := _lane_index(lane_id)
        if li < 0: continue
        var ks: Array = _tl.lanes[li]["keys"]
        for i in by_lane[lane_id]:
            var j := clampi(int(i) + dir, 0, ks.size() - 1)
            var id := "%s|%d" % [lane_id, j]
            if not ids.has(id): ids.append(id)
            first = minf(first, float(ks[j]["t"]))
    if ids.is_empty(): return
    _select_ids(ids, false)
    _scrub_to(first)


func _on_keys_drag_start() -> void:
    _key_drag.clear()
    for id in _key_sel:
        var p := ZenKeyPanel.split_id(id)
        var li := _lane_index(p[0])
        if li < 0: continue
        _key_drag.append([p[0], p[1], float((_tl.lanes[li]["keys"] as Array)[p[1]]["t"])])


func _on_keys_dragged(dt: float, snap: bool) -> void:
    if _key_drag.is_empty(): return
    var by_lane := {}                   # lane_id -> [[idx], [t]]
    for d in _key_drag:
        var t: float = d[2] + dt
        if snap: t = roundf(t / ZenTimelineView.SNAP) * ZenTimelineView.SNAP
        if not by_lane.has(d[0]): by_lane[d[0]] = [[], []]
        by_lane[d[0]][0].append(d[1])
        by_lane[d[0]][1].append(t)
    _live("move keys", func():
        for lane_id in by_lane:
            var node := _id_node(lane_id)
            if node == null: continue
            ZenKeyOps.set_times(_canvas, node, _id_prop(lane_id), by_lane[lane_id][0], by_lane[lane_id][1]))


func _delete_keys() -> void:
    var by_lane := _selected_keys()
    if by_lane.is_empty(): return
    _command("delete %d key%s" % [_key_sel.size(), "" if _key_sel.size() == 1 else "s"], func():
        for lane_id in by_lane:
            var node := _id_node(lane_id)
            if node == null: continue
            var idxs: Array = by_lane[lane_id]
            for j in range(idxs.size() - 1, -1, -1):
                ZenKeyOps.remove(_canvas, node, _id_prop(lane_id), idxs[j]))
    _key_sel.clear()
    _refresh_timeline()


func _on_marker_dragged(kind: String, idx: int, t: float) -> void:
    if _sig_edit != "": return
    _live("move %s" % kind, _move_marker.bind(kind, idx, t))


func _move_marker(kind: String, idx: int, t: float) -> void:
    match kind:
        "intro": ZenDocOps.set_intro_end(_canvas, t)
        "outro": ZenDocOps.set_outro_start(_canvas, t)
        "pause": ZenDocOps.move_pause(_canvas, idx, t)


func _ctx_begin() -> void:
    _ctx.clear()
    _ctx_items.clear()


func _ctx_add(label: String, fn: Callable) -> void:
    var id := _ctx_items.size()
    _ctx.add_item(label, id)
    _ctx_items[id] = fn


func _ctx_show(at: Vector2) -> void:
    _ctx.reset_size()
    _ctx.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_context_key(lane: int, idx: int, at: Vector2) -> void:
    var id := _sel_id(lane, idx)
    if not _key_sel.has(id): _select_ids([id], false)
    _ctx_begin()
    _ctx_ease.clear()
    var names: Array = ZenEasing.all_names().duplicate()
    names.append(ZenAnimBuilder.EASE_RAW)
    for i in names.size(): _ctx_ease.add_item(String(names[i]), i)
    for c in _ctx_ease.id_pressed.get_connections(): _ctx_ease.id_pressed.disconnect(c["callable"])
    _ctx_ease.id_pressed.connect(func(i): _set_ease(String(names[i])))
    _ctx.add_submenu_node_item("ease (incoming)", _ctx_ease)
    _ctx_add("edit in Keys panel", func():
        _keys_dismissed = false
        if not _p_keys.is_open: _toggle_panel("keys"))
    _ctx_add("select all at this time", func():
        _on_column_selected(float((_tl.lanes[lane]["keys"] as Array)[idx]["t"]), false))
    _ctx_add("select lane", _on_lane_selected.bind(lane, false))
    _ctx_add("delete key", _delete_keys)
    _ctx_add("copy key to playhead", _copy_keys_to_playhead)
    _ctx_add("playhead to key", func():
        _scrub_to(float((_tl.lanes[lane]["keys"] as Array)[idx]["t"])))
    _ctx_show(at)


func _set_ease(ease: String) -> void:
    var by_lane := _selected_keys()
    _command("ease %s" % ease, func():
        for lane_id in by_lane:
            var node := _id_node(lane_id)
            if node == null: continue
            for j in by_lane[lane_id]:
                ZenKeyOps.set_ease(_canvas, node, _id_prop(lane_id), j, ease))


## The C editor's "clone key to playhead": each selected key's value, keyed
## again at the playhead with its ease.
func _copy_keys_to_playhead() -> void:
    var by_lane := _selected_keys()
    _command("copy keys to %.2fs" % _t, func():
        for lane_id in by_lane:
            var node := _id_node(lane_id)
            if node == null: continue
            var prop := _id_prop(lane_id)
            var ks := ZenKeyOps.keys(_canvas, node, prop)
            var idxs: Array = by_lane[lane_id]
            var k: Dictionary = ks[idxs[0]]
            ZenKeyOps.insert(_canvas, node, prop, _t, k["v"], String(k["ease"])))


func _on_context_lane(lane: int, t: float, at: Vector2) -> void:
    var node := _lane_node(lane)
    var prop := _lane_prop(lane)
    if node == null: return
    _ctx_begin()
    _ctx_add("add key here (%.2fs)" % t, func():
        var v: Variant = _value_at(node, prop, t)
        _command("key %s" % prop, func(): ZenKeyOps.insert(_canvas, node, prop, t, v)))
    _ctx_add("remove track %s" % prop, func():
        _command("remove track %s" % prop, func(): ZenKeyOps.remove_track(_canvas, node, prop)))
    _ctx_show(at)


func _on_context_ruler(t: float, at: Vector2) -> void:
    _ctx_begin()
    _ctx_add("playhead here", _scrub_to.bind(t))
    if _sig_edit != "":
        _ctx_show(at)
        return
    _ctx_add("add pause here", func(): _command("add pause", func(): ZenDocOps.add_pause(_canvas, t)))
    _ctx_add("add pause (once) here", func(): _command("add pause", func(): ZenDocOps.add_pause(_canvas, t, true)))
    _ctx_add("intro ends here", func(): _command("intro_end", func(): ZenDocOps.set_intro_end(_canvas, t)))
    _ctx_add("outro starts here", func(): _command("outro_start", func(): ZenDocOps.set_outro_start(_canvas, t)))
    if _canvas.intro_end > 0.0:
        _ctx_add("clear intro", func(): _command("clear intro", func(): ZenDocOps.set_intro_end(_canvas, 0.0)))
    if _canvas.outro_start > 0.0 and _canvas.outro_start < _canvas.duration:
        _ctx_add("clear outro", func(): _command("clear outro", func(): ZenDocOps.set_outro_start(_canvas, _canvas.duration)))
    var near := -1
    for i in _canvas.pauses.size():
        if absf(float(_canvas.pauses[i]["t"]) - t) * _tl._pps < 8.0: near = i
    if near >= 0:
        _ctx_add("remove pause", func(): _command("remove pause", func(): ZenDocOps.remove_pause(_canvas, near)))
    _ctx_show(at)


# ---------------------------------------------------------------- playback

func _toggle_play() -> void:
    if _playing and _canvas.held_pause >= 0: _continue()
    elif _playing: _stop()
    else: _play()


## Release playback held at a pause marker (SPACE, or a click on the canvas).
func _continue() -> void:
    if not _playing or _canvas.held_pause < 0: return
    _canvas.release_pause()
    _set_status("continued")


## Play from the playhead - or, at (or past) the end, from the start, the
## same as Home then play.
func _play() -> void:
    _commit_live()
    if _sig_edit != "":
        _play_signal()
        return
    var t := _t if _t < _canvas.play_end() - 0.01 else 0.0
    if t == 0.0: _scrub_to(0.0)
    _canvas.release_signal()
    _canvas.play_from(t)
    _playing = true
    _stage.playing = true
    _play_btn.text = "pause"
    _slide_to(1.0)


func _stop() -> void:
    if not _playing: return
    _playing = false
    _stage.playing = false
    var bus := _canvas.bus()
    if _sig_edit != "":
        if bus != null: _t = minf(bus.player.clock, ZenKeyOps.anim_of(_canvas).length)
    else:
        _canvas.stop_timeline()
        _t = _canvas.pose_time
    if bus != null: bus.release_signal()
    _pose()
    _play_btn.text = "play"
    _slide_to(0.0)
    _refresh_inspector_values()


func _process(_dt: float) -> void:
    if not _playing or _canvas == null: return
    if _sig_edit != "":
        var bus := _canvas.bus()
        _t = bus.player.clock if bus != null else _t
        _tl.playhead = _t
        _tl.queue_redraw()
        _sync_time()
        if bus == null or not bus.is_running(): _stop()
        return
    _t = _canvas.pose_time
    _stage.time = _t
    _tl.playhead = _t
    _tl.queue_redraw()
    _sync_time()
    if _p_insp.is_open and _p_insp.pinned: _refresh_inspector_values()
    if _canvas.held_pause >= 0: _set_status("paused at a marker - click the canvas or SPACE to continue")
    # A signal still shaping the pose - running, held at a terminal end, or
    # following the pointer - keeps playback up until SPACE stops it.
    var bus := _canvas.bus()
    if bus != null and bus.is_overriding():
        if _canvas.is_finished():
            _set_status("signal %s - SPACE stops" % ("following" if bus.is_following() else "holding"
                if not bus.is_running() else bus.running_name))
        return
    if _canvas.is_finished(): _stop()


# ---------------------------------------------------------------- signals

func _build_signals(p: VBoxContainer) -> void:
    _sigs = ZenSignalPanel.new()
    _sigs.pick_requested.connect(func(nm):
        _sig_pick = nm
        _refresh_signals())
    _sigs.add_requested.connect(func(): _command("add signal", func():
        _sig_pick = ZenSignalOps.add(_canvas)))
    _sigs.delete_requested.connect(func(nm): _command("delete signal %s" % nm, func():
        ZenSignalOps.remove(_canvas, nm)
        if _sig_pick == nm: _sig_pick = ""))
    _sigs.rename_requested.connect(_rename_signal)
    _sigs.fire_requested.connect(_fire_signal)
    _sigs.field_set.connect(func(nm, key, v):
        var fn := func(): ZenSignalOps.set_field(_canvas, nm, key, v)
        if key == "length": _live("signal length", fn)
        else: _command("signal %s %s" % [nm, key], fn))
    _sigs.bind_requested.connect(func(nm):
        if _sel.is_empty():
            _set_status("select the elements that react to the point first")
            return
        _command("bind %s" % ", ".join(_sel), func():
            for el in _sel: ZenSignalOps.bind_point(_canvas, nm, el)))
    _sigs.unbind_requested.connect(func(nm, el): _command("unbind %s" % el, func():
        ZenSignalOps.unbind_point(_canvas, nm, el)))
    _sigs.offset_set.connect(func(nm, el, off): _live("point offset", func():
        ZenSignalOps.bind_point(_canvas, nm, el, off)))
    _sigs.edit_keys_requested.connect(func(nm, on): _set_sig_edit(nm if on else ""))
    p.add_child(_sigs)


func _refresh_signals() -> void:
    if _sigs == null or _canvas == null: return
    var names := ZenSignalOps.names(_canvas)
    if not names.has(_sig_pick): _sig_pick = _sig_edit if names.has(_sig_edit) else \
        (String(names[0]) if not names.is_empty() else "")
    var bus := _canvas.bus()
    var targets: Array = []
    for tg in ZenSignalOps.data(_canvas, _sig_pick).get("targets", []):
        targets.append("%s.%s" % [tg["elem"], tg["prop"]])
    _sigs.set_model(bus.signals_data if bus != null else [], _sig_pick, _sig_edit,
        ZenSignalOps.trigger_clash(_canvas, _sig_pick), targets)


func _rename_signal(from: String, to: String) -> void:
    if not ZenSignalOps.is_name_free(_canvas, to):
        _set_status("a signal called %s already exists" % to)
        _refresh_signals()
        return
    _command("rename signal %s -> %s" % [from, to], func():
        ZenSignalOps.rename(_canvas, from, to)
        if _sig_pick == from: _sig_pick = to
        if _sig_edit == from: _sig_edit = to)


## Point the timeline at a signal's keys ("" = back to the document). The
## signal is previewed from the document pose at the playhead it left.
func _set_sig_edit(nm: String) -> void:
    if nm == _sig_edit: return
    _stop()
    _commit_live()
    if _sig_edit == "": _doc_t = _t
    var bus := _canvas.bus()
    if bus != null: bus.release_signal()
    _sig_edit = nm
    _canvas.edit_anim = nm
    _t = 0.0 if nm != "" else _doc_t
    _key_sel.clear()
    if nm != "":
        _sig_pick = nm
        if not _p_tl.is_open: _toggle_panel("timeline")
        _set_status("editing signal %s - keys and drags key the signal; its first key is the pose captured at fire. ESC returns" % nm)
    else:
        _set_status("editing the document timeline")
    _after_edit()


## Keep a signal's runtime data in step with key edits in signal key mode.
func _sync_signal() -> void:
    if _sig_edit != "": ZenSignalOps.sync(_canvas, _sig_edit)


## The time the canvas is posed at: the document playhead, which in signal
## key mode is the pose the signal is previewed from.
func _pose_t() -> float:
    return _doc_t if _sig_edit != "" else _t


## Pose the canvas for the playhead: the document at _t, or in signal key
## mode the signal _t seconds in, from the document pose at _doc_t. Editing
## (not playing) drops whatever a fired signal left behind.
func _pose() -> void:
    var bus := _canvas.bus()
    if _sig_edit == "":
        if bus != null and not _playing: bus.release_signal()
        _canvas.scrub(_t)
        return
    _canvas.scrub(_doc_t)
    if bus != null: bus.preview(_sig_edit, _t)


## The value of `prop` at `t` on the timeline being edited: the document's
## plain track, or the signal's curve eased from the document pose at _doc_t.
func _value_at(node: ZenElement, prop: String, t: float) -> Variant:
    var col := ZenProps.is_color(prop)
    var t0 := _doc_t if _sig_edit != "" else t
    var plain: Variant = node.plain_prop_color(prop, t0, node.base_color(prop), 1.0) if col \
        else node.plain_prop(prop, t0, node.base_scalar(prop))
    if _sig_edit == "" or ZenProps.is_stepped(prop): return plain
    var tl := _canvas.signal_timeline(_sig_edit)
    var path := node.track_path(prop)
    return tl.blend_color(path, t, plain) if col else tl.blend(path, t, float(plain))


## Fire a signal: live while the scene plays, else over the pose at the
## playhead (the editing pose comes back on the next scrub or edit).
func _fire_signal(nm: String) -> void:
    if _sig_edit != "":
        if nm != _sig_edit: _set_sig_edit(nm)
        _play_signal()
        return
    if not _playing:
        _commit_live()
        _pose()
    if not _canvas.fire(nm): _set_status("%s did not start - it animates nothing yet" % nm)


## Play the edited signal through, from the document pose.
func _play_signal() -> void:
    var bus := _canvas.bus()
    if bus == null: return
    _canvas.scrub(_doc_t)
    bus.preview(_sig_edit, 0.0)
    if not bus.is_running():
        _set_status("%s animates nothing yet - key something first" % _sig_edit)
        return
    bus.running_name = _sig_edit
    bus.set_process(true)
    _playing = true
    _stage.playing = true
    _play_btn.text = "stop"


## The pointer over the canvas. A press continues a held pause first; while
## the document plays the rest reaches the canvas, firing press / release
## triggers there as it would in a game.
func _on_play_pointer(kind: String, frac: Vector2) -> void:
    if _canvas == null: return
    if kind == "press" and _playing and _canvas.held_pause >= 0:
        _continue()
        return
    if kind != "move" and (not _playing or _sig_edit != ""): return
    if _canvas.pointer(kind, frac): _set_status("%s fired" % _canvas.bus().running_name)


## Keys 1-9 while playing fire the scene's signals in list order, at the
## pointer - the gallery's keys, and the C editor's.
func _fire_digit(ev: InputEvent) -> bool:
    var names := ZenSignalOps.names(_canvas)
    for i in mini(names.size(), 9):
        if ev.is_action_pressed("zen_signal_%d" % (i + 1)):
            _fire_signal(String(names[i]))
            return true
    return false


# ---------------------------------------------------------------- files

func _sync_title() -> void:
    if _title == null: return
    _title.text = "%s%s" % [_name if _name != "" else "untitled", "  *" if _dirty() else ""]


func _set_status(t: String) -> void:
    if _status != null: _status.text = t


func _save() -> void:
    _commit_live()
    if _name == "":
        _ask_save_as()
        return
    _stop()
    _canvas.name = ZenElemFactory.node_name(_name)
    var path := ZenSceneOps.save(_canvas, _name, _folder)
    if path.is_empty():
        _set_status("could not save %s" % _name)
        return
    _saved_version = _undo.get_version()
    _sync_title()
    _set_status("saved %s" % path)


func _ask_name(title: String, initial: String, fn: Callable) -> void:
    _name_dialog.title = title
    _name_edit.text = initial
    _name_fn = fn
    _validate_name()
    _name_dialog.popup_centered()
    _name_edit.grab_focus()
    _name_edit.select_all()


func _validate_name() -> bool:
    var n := ZenSceneOps.clean_name(_name_edit.text)
    var err := ""
    if n.is_empty(): err = "type a name"
    elif not ZenSceneOps.is_name_free(n) and n != _name: err = "an animation called %s already exists" % n
    elif n != _name_edit.text.strip_edges(): err = "will be saved as %s" % n
    _name_error.text = err
    _name_dialog.get_ok_button().disabled = n.is_empty() or (not ZenSceneOps.is_name_free(n) and n != _name)
    return not _name_dialog.get_ok_button().disabled


func _on_name_ok() -> void:
    if not _validate_name(): return
    _name_dialog.hide()
    if _name_fn.is_valid(): _name_fn.call(ZenSceneOps.clean_name(_name_edit.text))


func _ask_save_as() -> void:
    _ask_name("Save scene as", _name if _name != "" else "untitled", func(n):
        _name = n
        _save())


func _ask_rename() -> void:
    if _name == "" or ZenSceneOps.path_of(_name).is_empty():
        _ask_save_as()
        return
    _ask_name("Rename scene", _name, func(n):
        if n == _name: return
        var old := _name
        if ZenSceneOps.rename(old, n) != OK:
            _set_status("could not rename %s" % old)
            return
        _name = n
        _canvas.name = ZenElemFactory.node_name(n)
        _sync_title()
        _set_status("renamed %s -> %s (not yet saved under the new name)" % [old, n]
                    if _dirty() else "renamed %s -> %s" % [old, n]))


func _ask_delete_scene() -> void:
    if _name == "" or ZenSceneOps.path_of(_name).is_empty():
        _set_status("nothing saved to delete")
        return
    _ask_confirm("Move %s to the trash?\n  %s" % [_name, ZenSceneOps.path_of(_name)], func():
        var nm := _name
        if ZenSceneOps.delete(nm) != OK:
            _set_status("could not delete %s" % nm)
            return
        _name = ""
        closed.emit())


func _ask_new() -> void:
    _guard(func(): open(""))


func _ask_open() -> void:
    _open_list.clear()
    var paths := ZenSceneOps.scene_paths()
    var names := paths.keys()
    names.sort()
    for n in names:
        _open_list.add_item(String(n))
        _open_list.set_item_metadata(_open_list.item_count - 1, paths[n])
    _open_dialog.popup_centered()


func _on_open_ok() -> void:
    var sel := _open_list.get_selected_items()
    if sel.is_empty(): return
    var path := String(_open_list.get_item_metadata(sel[0]))
    _guard(func(): open(path))


## Run `fn` once unsaved changes are dealt with.
func _guard(fn: Callable) -> void:
    _commit_live()
    if _undo.get_version() == _saved_version:
        fn.call()
        return
    _ask_confirm("Discard unsaved changes to %s?" % (_name if _name != "" else "this new scene"), fn)


func _ask_confirm(text: String, fn: Callable) -> void:
    _confirm.dialog_text = text
    _confirm_fn = fn
    _confirm.popup_centered()


func _request_leave() -> void:
    _commit_live()
    if _undo.get_version() != _saved_version:
        _leave_dialog.dialog_text = "%s has unsaved changes." % (_name if _name != "" else "This new scene")
        _leave_dialog.popup_centered()
    else:
        closed.emit()


func _on_leave_action(action: StringName) -> void:
    if action != "save": return
    _leave_dialog.hide()
    _save()
    if not _dirty(): closed.emit()


func _delete_selection() -> void:
    if not _key_sel.is_empty(): _delete_keys()
    else: _delete_elements()


# ---------------------------------------------------------------- keys

## The hotkey sheet, in pages; it opens on the one for what the mouse is over.
func _show_help() -> void:
    var pages := [
        {"name": "Canvas", "rows": [
            ["click / Shift+click", "select / add an element"],
            ["click the same spot", "cycle down through what overlaps there"],
            ["drag", "move the selection (Shift: lock to an axis)"],
            ["wheel", "zoom the view about the cursor"],
            ["middle drag", "pan the view"],
            ["zen_edit_fit", "fit the view (mouse over the canvas)"],
            ["zen_delete", "delete the selected elements"],
            ["zen_duplicate", "duplicate the selected elements"],
            ["zen_rename", "rename the selected element"]]},
        {"name": "Timeline & keys", "rows": [
            ["zen_edit_key_prev", "playhead to the previous key (picks the keys there)"],
            ["zen_edit_key_next", "playhead to the next key (picks the keys there)"],
            ["zen_edit_select_all", "select every key on the timeline"],
            ["double-click a key", "edit it in the Keys panel"],
            ["Alt+click a key", "select every key at that time"],
            ["click a lane label", "select the lane's keys (Shift adds)"],
            ["zen_delete", "delete the selected keys"],
            ["zen_edit_fit", "fit the timeline (mouse off the canvas)"]]},
        {"name": "Playback", "rows": [
            ["zen_play", "play / pause"], ["zen_edit_home", "playhead to start"],
            ["zen_edit_frame_prev", "back one frame"], ["zen_edit_frame_next", "forward one frame"],
            ["zen_edit_autokey", "auto-key on / off"],
            ["click while playing", "continue from a pause marker, else a press / release signal"],
            ["1-9 while playing", "fire the scene's signals, in list order, at the pointer"]]},
        {"name": "Panels & file", "rows": [
            ["zen_edit_panel_1", "elements panel"], ["zen_edit_panel_2", "inspector"],
            ["zen_edit_panel_3", "document"], ["zen_edit_panel_4", "timeline"],
            ["zen_edit_panel_5", "string pool"], ["zen_edit_panel_6", "keys panel"],
            ["zen_edit_panel_7", "signals panel"],
            ["zen_edit_undo", "undo"], ["zen_edit_redo", "redo"],
            ["zen_edit_save", "save"], ["zen_edit_save_as", "save as"],
            ["zen_help", "this sheet on / off"],
            ["zen_back", "close a floating panel, then drop the key selection, then back"]]}]
    var start := 2
    if _over(_p_tl) or not _key_sel.is_empty(): start = 1
    elif _over_stage(): start = 0
    _help.show_pages("Scene editor", pages, start)


func _over(c: Control) -> bool:
    var hov := get_viewport().gui_get_hovered_control()
    return hov != null and c.visible and (hov == c or c.is_ancestor_of(hov))


## The mouse is over the canvas view, not a panel or the timeline on top of it.
func _over_stage() -> bool:
    return _over(_stage)


## Editor keys are named InputMap actions (tools/gen_input_map.gd), taken only
## when no text field or dialog has focus.
func _unhandled_input(ev: InputEvent) -> void:
    if not (ev is InputEventKey) or not ev.is_pressed(): return
    for d in [_name_dialog, _confirm, _open_dialog, _leave_dialog]:
        if (d as Window).visible: return
    if _help.handle_key(ev):
        get_viewport().set_input_as_handled()
        return
    var echo := ev.is_echo()
    if ev.is_action_pressed("zen_help"):
        if not echo: _show_help()
    elif ev.is_action_pressed("zen_back"):
        if echo or _close_unpinned(): pass
        elif not _key_sel.is_empty(): _clear_keys()
        elif _sig_edit != "": _set_sig_edit("")
        else: _request_leave()
    elif ev.is_action_pressed("zen_edit_redo", true): _do_redo()
    elif ev.is_action_pressed("zen_edit_undo", true): _do_undo()
    elif ev.is_action_pressed("zen_edit_save_as"):
        if not echo: _ask_save_as()
    elif ev.is_action_pressed("zen_edit_save"):
        if not echo: _save()
    elif ev.is_action_pressed("zen_duplicate"):
        if not echo: _duplicate_elements()
    elif ev.is_action_pressed("zen_edit_select_all"):
        if not echo: _select_all_keys()
    elif (ev as InputEventKey).ctrl_pressed: pass
    elif ev.is_action_pressed("zen_play"):
        if not echo: _toggle_play()
    elif ev.is_action_pressed("zen_delete"):
        if not echo: _delete_selection()
    elif ev.is_action_pressed("zen_rename"):
        if not echo:
            _p_elems.set_open(true)
            _tree_begin_rename()
    elif ev.is_action_pressed("zen_edit_autokey"):
        if not echo: _set_autokey(not _autokey)
    elif ev.is_action_pressed("zen_edit_home"): _scrub_to(0.0)
    elif ev.is_action_pressed("zen_edit_frame_prev", true): _scrub_to(_t - FRAME)
    elif ev.is_action_pressed("zen_edit_frame_next", true): _scrub_to(_t + FRAME)
    elif ev.is_action_pressed("zen_edit_fit"):
        if _over_stage(): _stage.fit_view()
        else: _tl.fit()
    elif ev.is_action_pressed("zen_edit_key_prev", true): _jump_key(-1)
    elif ev.is_action_pressed("zen_edit_key_next", true): _jump_key(1)
    elif _playing and _sig_edit == "" and _fire_digit(ev): pass
    else:
        var ids := ["elements", "inspector", "document", "timeline", "strings", "keys", "signals"]
        for i in ids.size():
            if ev.is_action_pressed("zen_edit_panel_%d" % (i + 1)):
                if not echo: _toggle_panel(ids[i])
    # Swallow every key: the gallery underneath must not react to its own.
    get_viewport().set_input_as_handled()
