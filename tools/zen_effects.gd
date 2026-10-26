class_name ZenEffects
extends Node
##
## The scene editor's effect tools. An EFFECT is an ordinary animation (by
## convention in the gallery's `effects` folder); this is how one is made from
## the open scene and how one is laid into it:
##
##   - EXTRACT is a guide, not an operation: save the scene, duplicate it
##     under the effect's name (signals kept or cut), keep only some elements,
##     delete the keys that are not part of the effect on the timeline as
##     usual, then trim the empty time. Every step is plain scene editing on
##     the copy, so stopping half way leaves an ordinary scene.
##   - INSERT asks where (the playhead - movable from the dialog - or a given
##     second), how fast (a length ratio, the result shown) and whether to
##     prefix the inserted element names, then runs ZenClipOps.paste.
##   - LENGTH and TRIM (Edit > Options) change the open scene's own clock.
##
## It edits the editor's canvas through the editor's own undo steps
## (`_command`), so every action here is one undo step like any other.
##

const EPS := 0.005

var ed: ZenSceneEditor

## The Effects panel's list of animations (folder headers are not selectable).
var list: ItemList
var _guide: HBoxContainer               ## the extract guide strip (step 3)
var _guide_text: Label
var _step := 0                          ## extract step shown, 0 = no guide
var _effect_name := ""                  ## the effect the guide is making

var _len_dialog: ConfirmationDialog
var _len_spin: SpinBox
var _len_scale: CheckBox
var _len_info: Label

var _trim_dialog: ConfirmationDialog
var _trim_lead: CheckBox
var _trim_tail: CheckBox
var _trim_info: Label

var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label
var _name_folder: OptionButton
var _name_sigs: CheckBox
var _pre_sel: Array = []                ## the source's selection when extract began

var _elem_dialog: ConfirmationDialog
var _elem_box: VBoxContainer

var _ins_dialog: ConfirmationDialog
var _ins_pick: OptionButton
var _ins_about: Label
var _ins_at_head: CheckBox
var _ins_head: SpinBox
var _ins_at_sec: CheckBox
var _ins_sec: SpinBox
var _ins_ratio: SpinBox
var _ins_prefix_on: CheckBox
var _ins_prefix: LineEdit
var _ins_names: Label
var _ins_info: Label
var _ins_fx: ZenCanvas = null           ## the picked effect, opened for its numbers
var _ins_path := ""
var _syncing := false


func _init(editor: ZenSceneEditor) -> void:
    ed = editor
    name = "Effects"


func _exit_tree() -> void:
    _drop_fx()


## Is one of the dialogs up? The editor's keys stay off while one is.
func dialog_open() -> bool:
    for d in [_len_dialog, _trim_dialog, _name_dialog, _elem_dialog, _ins_dialog]:
        if d != null and (d as Window).visible: return true
    return false


# ---------------------------------------------------------------- the panel

## The Effects panel (8): every animation, effects first, and two actions.
func build_panel(p: VBoxContainer) -> void:
    list = ItemList.new()
    list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    list.item_activated.connect(func(_i): ask_insert())
    p.add_child(list)
    var g := HFlowContainer.new()
    p.add_child(g)
    for a in [
            {"label": "Insert...", "fn": ask_insert,
             "tip": "Place the selected animation into this one as an effect: choose where on "
                + "the timeline, how fast it plays and how its elements are named. Double-click "
                + "an animation does the same."},
            {"label": "Extract...", "fn": ask_extract,
             "tip": "Make a new effect animation from part of this one, step by step: save, "
                + "copy under the effect's name, keep only some elements, delete the keys you "
                + "do not need, trim the empty time."}]:
        var b := ZenUI.bar_button(a)
        b.flat = false
        g.add_child(b)
    var note := ZenUI.label("Effects are ordinary animations; extract saves them in %s/."
        % ZenSceneOps.EFFECTS_FOLDER, ZenUI.DIM, 11)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD
    p.add_child(note)
    refresh_list()


## Folders in list order: effects first, then the top level, then the rest.
static func folder_order() -> Array:
    var out: Array = [ZenSceneOps.EFFECTS_FOLDER, ""]
    for f in ZenSceneOps.folders():
        if not out.has(f): out.append(f)
    return out


## [[folder, [[name, path]...]]...] - every animation but the open one.
func grouped() -> Array:
    var by := {}
    var paths := ZenSceneOps.scene_paths()
    for nm in paths:
        if nm == ed._name: continue
        var f := ZenSceneOps.folder_of_path(String(paths[nm]))
        if not by.has(f): by[f] = []
        (by[f] as Array).append([String(nm), String(paths[nm])])
    var out: Array = []
    for f in folder_order():
        if not by.has(f): continue
        var rows: Array = by[f]
        rows.sort_custom(func(a, b): return String(a[0]).naturalnocasecmp_to(String(b[0])) < 0)
        out.append([f, rows])
    return out


func refresh_list() -> void:
    if list == null: return
    var keep := selected_path()
    list.clear()
    for grp in grouped():
        var hx := list.add_item("%s/" % grp[0] if grp[0] != "" else "(top level)")
        list.set_item_selectable(hx, false)
        list.set_item_custom_fg_color(hx, ZenUI.DIM)
        list.set_item_tooltip_enabled(hx, false)
        for row in grp[1]:
            var ix := list.add_item("   " + String(row[0]))
            list.set_item_metadata(ix, row[1])
            list.set_item_tooltip(ix, "%s\n%s\nDouble-click: insert into this animation" % [row[0], row[1]])
            if row[1] == keep: list.select(ix)


func selected_path() -> String:
    if list == null: return ""
    var s := list.get_selected_items()
    return String(list.get_item_metadata(s[0])) if not s.is_empty() else ""


# ---------------------------------------------------------------- dialogs

func build_dialogs() -> void:
    _build_length()
    _build_trim()
    _build_extract()
    _build_insert()


func _dialog(title: String, ok: String) -> ConfirmationDialog:
    var d := ConfirmationDialog.new()
    d.title = title
    d.ok_button_text = ok
    d.min_size = Vector2i(380, 0)
    add_child(d)
    return d


func _col(d: Window) -> VBoxContainer:
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    d.add_child(col)
    return col


func _spin(lo: float, hi: float, step: float, tip: String) -> SpinBox:
    var s := SpinBox.new()
    s.min_value = lo
    s.max_value = hi
    s.step = step
    s.suffix = "s"
    s.custom_minimum_size = Vector2(110, 0)
    s.tooltip_text = tip
    return s


func _check(text: String, tip: String) -> CheckBox:
    var c := CheckBox.new()
    c.text = text
    c.tooltip_text = tip
    return c


func _info(col: Container) -> Label:
    var l := ZenUI.label("", ZenUI.LABEL)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD
    l.custom_minimum_size.x = 360
    col.add_child(l)
    return l


# ---------------------------------------------------------------- length

func _build_length() -> void:
    _len_dialog = _dialog("Animation length", "Set length")
    var col := _col(_len_dialog)
    var row := HBoxContainer.new()
    col.add_child(row)
    row.add_child(ZenUI.label("new length", ZenUI.TEXT))
    _len_spin = _spin(0.1, 600.0, 0.01, "The animation's new length in seconds.")
    _len_spin.value_changed.connect(func(_v): _sync_length())
    row.add_child(_len_spin)
    _len_scale = _check("Scale keys to the new length",
        "On: every key, marker and pause is stretched or squeezed so the whole animation plays "
        + "faster or slower.\nOff: keys stay where they are; a longer animation gets empty time "
        + "at the end, a shorter one stops before its last keys (they are kept, just not played).")
    _len_scale.toggled.connect(func(_on): _sync_length())
    col.add_child(_len_scale)
    _len_info = _info(col)
    _len_dialog.confirmed.connect(_apply_length)


func ask_length() -> void:
    if not _doc_mode(): return
    _len_spin.set_value_no_signal(ed._canvas.duration)
    _len_scale.set_pressed_no_signal(false)
    _sync_length()
    _len_dialog.popup_centered()
    _len_spin.get_line_edit().grab_focus()


func _sync_length() -> void:
    var old := ed._canvas.duration
    var d := _len_spin.value
    var s := "%.2fs -> %.2fs  (x%.2f)" % [old, d, d / old]
    var span := ZenDocOps.key_span(ed._canvas)
    if _len_scale.button_pressed:
        s += "\nkeys, markers and pauses are scaled with it"
    elif d < old and span.y > d + EPS:
        s += "\nkeys up to %.2fs are kept but stop playing at %.2fs" % [span.y, d]
    _len_info.text = s


func _apply_length() -> void:
    var c := ed._canvas
    var d := _len_spin.value
    if absf(d - c.duration) < 0.0005: return
    var f := d / c.duration
    if _len_scale.button_pressed:
        ed._command("scale length to %.2fs" % d, func(): ZenDocOps.retime(c, f))
    else:
        ed._command("length %.2fs" % d, func(): ZenDocOps.set_duration(c, d))


# ---------------------------------------------------------------- trim

func _build_trim() -> void:
    _trim_dialog = _dialog("Trim empty time", "Trim")
    var col := _col(_trim_dialog)
    var note := ZenUI.label("Empty time is where nothing changes: no element moves, fades or "
        + "switches text.", ZenUI.TEXT, 12)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD
    note.custom_minimum_size.x = 360
    col.add_child(note)
    _trim_lead = _check("", "Move everything earlier so the first change starts at 0s. Keys, "
        + "intro/outro and pauses move with it; pauses inside the cut are removed.")
    _trim_lead.toggled.connect(func(_on): _sync_trim())
    col.add_child(_trim_lead)
    _trim_tail = _check("", "End the animation where the last change ends.")
    _trim_tail.toggled.connect(func(_on): _sync_trim())
    col.add_child(_trim_tail)
    _trim_info = _info(col)
    _trim_dialog.confirmed.connect(_apply_trim)
    _trim_dialog.canceled.connect(func(): if _step == 4: _show_guide(3))


func ask_trim() -> void:
    if not _doc_mode(): return
    var c := ed._canvas
    var span := ZenDocOps.key_span(c)
    var lead := span.x > EPS
    var tail := span.x >= 0.0 and span.y < c.duration - EPS
    _trim_dialog.title = "Extract effect (4/4): trim empty time" if _step >= 3 else "Trim empty time"
    _trim_lead.text = "Cut empty start  (0.00 - %.2fs)" % maxf(span.x, 0.0)
    _trim_tail.text = "Cut empty end  (%.2f - %.2fs)" % [maxf(span.y, 0.0), c.duration]
    _trim_lead.disabled = not lead
    _trim_tail.disabled = not tail
    _trim_lead.set_pressed_no_signal(lead)
    _trim_tail.set_pressed_no_signal(tail)
    if _step >= 3: _step = 4
    _sync_trim()
    if span.x < 0.0 and _step == 0:
        ed._set_status("nothing to trim: nothing changes over time")
        return
    _trim_dialog.popup_centered()


func _sync_trim() -> void:
    var c := ed._canvas
    var span := ZenDocOps.key_span(c)
    if span.x < 0.0:
        _trim_info.text = "Nothing changes over time: there is nothing to cut."
    elif _trim_lead.disabled and _trim_tail.disabled:
        _trim_info.text = "No empty time: changes start at 0s and run to the end."
    else:
        var a := span.x if _trim_lead.button_pressed else 0.0
        var b := span.y if _trim_tail.button_pressed else c.duration
        _trim_info.text = "length %.2fs -> %.2fs" % [c.duration, maxf(b - a, 0.1)]
    _trim_dialog.get_ok_button().text = "Trim and save" if _step == 4 else "Trim"


func _apply_trim() -> void:
    var c := ed._canvas
    var lead := _trim_lead.button_pressed and not _trim_lead.disabled
    var tail := _trim_tail.button_pressed and not _trim_tail.disabled
    if lead or tail:
        ed._command("trim", func(): ZenDocOps.trim(c, lead, tail))
    if _step == 4: _finish_extract()


# ---------------------------------------------------------------- extract

func _build_extract() -> void:
    _name_dialog = _dialog("Extract effect (1/4): copy", "Copy and continue")
    var col := _col(_name_dialog)
    var lead := ZenUI.label("The effect starts as a copy of this saved animation; the next "
        + "steps cut the copy down. This animation is not changed.", ZenUI.TEXT, 12)
    lead.autowrap_mode = TextServer.AUTOWRAP_WORD
    lead.custom_minimum_size.x = 360
    col.add_child(lead)
    var g := GridContainer.new()
    g.columns = 2
    col.add_child(g)
    g.add_child(ZenUI.label("effect name", ZenUI.TEXT))
    _name_edit = LineEdit.new()
    _name_edit.custom_minimum_size = Vector2(240, 0)
    _name_edit.tooltip_text = "The new animation's name; it shows in the gallery under this name."
    _name_edit.text_changed.connect(func(_t): _validate_name())
    _name_edit.text_submitted.connect(func(_t): _submit_name())
    g.add_child(_name_edit)
    g.add_child(ZenUI.label("folder", ZenUI.TEXT))
    _name_folder = OptionButton.new()
    _name_folder.tooltip_text = "The gallery folder the effect is saved in."
    g.add_child(_name_folder)
    _name_sigs = _check("Keep signals",
        "On: the copy keeps this animation's signals (clicks, follows, code triggers).\n"
        + "Off: they are cut off and the effect is a plain timeline - what Insert places "
        + "anyway, since inserting does not carry signals.")
    col.add_child(_name_sigs)
    _name_error = ZenUI.label("", ZenUI.WARN)
    col.add_child(_name_error)
    _name_dialog.confirmed.connect(_copy_for_extract)

    _elem_dialog = _dialog("Extract effect (2/4): elements", "Keep checked")
    var ecol := _col(_elem_dialog)
    var tip := ZenUI.label("Check the elements that belong to the effect; the others are removed "
        + "from the copy (one undo step).", ZenUI.TEXT, 12)
    tip.autowrap_mode = TextServer.AUTOWRAP_WORD
    tip.custom_minimum_size.x = 360
    ecol.add_child(tip)
    var sc := ScrollContainer.new()
    sc.custom_minimum_size = Vector2(360, 260)
    sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    ecol.add_child(sc)
    _elem_box = VBoxContainer.new()
    _elem_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sc.add_child(_elem_box)
    var row := HBoxContainer.new()
    ecol.add_child(row)
    for a in [{"label": "all", "fn": _check_all.bind(true), "tip": "Check every element."},
              {"label": "none", "fn": _check_all.bind(false), "tip": "Uncheck every element."}]:
        var b := ZenUI.bar_button(a)
        b.flat = false
        row.add_child(b)
    _elem_dialog.confirmed.connect(_keep_elements)
    _elem_dialog.canceled.connect(_stop_guide.bind(true))

    _guide = HBoxContainer.new()
    _guide.visible = false
    _guide_text = ZenUI.label("", ZenUI.LABEL)
    _guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD
    _guide.add_child(_guide_text)
    for a in [{"label": "Next: trim...", "fn": func(): _guide.hide(); ask_trim(),
               "tip": "Done with the keys: cut the empty time at the start and end, then save "
                  + "the effect."},
              {"label": "Stop guide", "fn": _stop_guide.bind(true),
               "tip": "Leave the guide. The copy stays as it is now - an ordinary animation you "
                  + "can keep editing, or delete from the File menu."}]:
        var b := ZenUI.bar_button(a)
        b.flat = false
        _guide.add_child(b)


## The guide strip, for the editor to place above its status line.
func guide_strip() -> Control:
    return _guide


## Extract, step 0: the source must be saved, since the effect is a copy of
## the saved file.
func ask_extract() -> void:
    if not _doc_mode(): return
    _stop_guide(false)
    _pre_sel = ed._sel.duplicate()
    if ed._name == "":
        ed._ask_name("Save this animation before extracting", "untitled", func(n):
            ed._name = n
            ed._save()
            if not ed._dirty(): _ask_effect_name())
    elif ed._dirty():
        ed._ask_confirm("Save %s before extracting an effect from it?\n\n" % ed._name
            + "The effect starts as a copy of the saved animation.", func():
            ed._save()
            if not ed._dirty(): _ask_effect_name())
    else:
        _ask_effect_name()


## Extract, step 1: name, folder, signals.
func _ask_effect_name() -> void:
    _name_edit.text = ZenSceneOps.unique_name("fx_" + ed._name.trim_prefix("fx_"))
    _name_folder.clear()
    for f in folder_order():
        _name_folder.add_item("%s/" % f if f != "" else "(top level)")
        _name_folder.set_item_metadata(_name_folder.item_count - 1, f)
    _name_folder.select(0)              # effects/
    var sigs := ZenSignalOps.names(ed._canvas).size()
    _name_sigs.disabled = sigs == 0
    _name_sigs.set_pressed_no_signal(false)
    _name_sigs.text = "Keep signals (%d)" % sigs if sigs > 0 else "Keep signals (this animation has none)"
    _validate_name()
    _name_dialog.popup_centered()
    _name_edit.grab_focus()
    _name_edit.select_all()


func _validate_name() -> bool:
    var n := ZenSceneOps.clean_name(_name_edit.text)
    var err := ""
    if n.is_empty(): err = "type a name"
    elif not ZenSceneOps.is_name_free(n): err = "an animation called %s already exists" % n
    elif n != _name_edit.text.strip_edges(): err = "will be saved as %s" % n
    _name_error.text = err
    var ok := not n.is_empty() and ZenSceneOps.is_name_free(n)
    _name_dialog.get_ok_button().disabled = not ok
    return ok


func _submit_name() -> void:
    if not _validate_name(): return
    _name_dialog.hide()
    _copy_for_extract()


## Extract, step 1 done: copy the saved source and open the copy.
func _copy_for_extract() -> void:
    if not _validate_name(): return
    var nm := ZenSceneOps.clean_name(_name_edit.text)
    var folder := String(_name_folder.get_item_metadata(maxi(_name_folder.selected, 0)))
    var src := ed._name
    if ZenSceneOps.duplicate_scene(src, nm, folder) != OK:
        ed._set_status("could not copy %s to %s" % [src, nm])
        return
    ed.open(ZenSceneOps.path_of(nm))
    if not _name_sigs.button_pressed and not ZenSignalOps.names(ed._canvas).is_empty():
        ZenSignalOps.remove_all(ed._canvas)
        ed._save()
        ed._refresh_all()
    _effect_name = nm
    _step = 2
    refresh_list()
    ed._set_status("extracting %s from %s" % [nm, src])
    _ask_elements()


## Extract, step 2: which elements stay.
func _ask_elements() -> void:
    for ch in _elem_box.get_children():
        _elem_box.remove_child(ch)
        ch.queue_free()
    for r in ZenElemOps.rows(ed._canvas):
        var el := r as ZenElement
        var c := _check("%s  (%s)" % [el.elem_name, el.zen_kind()],
            "Keep %s in the effect, with all its keys." % el.elem_name)
        c.set_meta("elem", el.elem_name)
        c.button_pressed = _pre_sel.is_empty() or _pre_sel.has(el.elem_name)
        _elem_box.add_child(c)
    _elem_dialog.popup_centered()


func _check_all(on: bool) -> void:
    for c in _elem_box.get_children(): (c as CheckBox).button_pressed = on


func _keep_elements() -> void:
    var drop: Array = []
    var keep: Array[String] = []
    for c in _elem_box.get_children():
        var nm := String(c.get_meta("elem"))
        if (c as CheckBox).button_pressed: keep.append(nm)
        else: drop.append(nm)
    if not drop.is_empty():
        var cv := ed._canvas
        ed._command("keep %d element(s)" % keep.size(), func():
            for nm in drop:
                var el := ZenElemOps.find(cv, nm)
                if el != null: ZenElemOps.remove(cv, el)
            ed._sel = keep)
        ed._key_sel.clear()
        ed._on_selection_changed(true)
    _show_guide(3)


## Extract, step 3: the strip that stays up while keys are cut on the timeline.
func _show_guide(step: int) -> void:
    _step = step
    _guide_text.text = ("Extract %s (3/4): delete the keys that are not part of the effect - " % _effect_name
        + "pick them on the timeline (drag a box, Alt+click a column, click a lane label) and press DEL.")
    _guide.show()
    ed._p_tl.set_open(true)


func _stop_guide(say: bool) -> void:
    if say and _step > 0:
        ed._set_status("guide stopped: %s is saved as an ordinary animation%s" % [
            _effect_name, " (unsaved changes)" if ed._dirty() else ""])
    _step = 0
    if _guide != null: _guide.hide()


## Extract, step 4 done: save the effect.
func _finish_extract() -> void:
    ed._save()
    var folder := ZenSceneOps.folder_of(ed._name)
    _stop_guide(false)
    refresh_list()
    ed._set_status("effect %s saved in %s - Insert places it into other animations" % [
        ed._name, "%s/" % folder if folder != "" else "the top level"])


## Opening a scene ends the guide (extract re-arms it after its own open).
func scene_opened() -> void:
    _stop_guide(false)
    refresh_list()


# ---------------------------------------------------------------- insert

func _build_insert() -> void:
    _ins_dialog = _dialog("Insert effect", "Insert")
    var col := _col(_ins_dialog)
    _ins_pick = OptionButton.new()
    _ins_pick.tooltip_text = "The animation to place into this one."
    _ins_pick.item_selected.connect(func(_i): _load_fx())
    col.add_child(_ins_pick)
    _ins_about = ZenUI.label("", ZenUI.TEXT, 12)
    col.add_child(_ins_about)

    col.add_child(ZenUI.label("Where it starts", ZenUI.TITLE))
    var bg := ButtonGroup.new()
    var g := GridContainer.new()
    g.columns = 2
    col.add_child(g)
    _ins_at_head = _check("at the playhead", "Start the effect where the playhead is. Moving the "
        + "value moves the playhead too, so the scene shows the moment it starts.")
    _ins_at_head.button_group = bg
    g.add_child(_ins_at_head)
    _ins_head = _spin(0.0, 600.0, 0.01, "The playhead; changing it scrubs the scene.")
    _ins_head.value_changed.connect(func(v):
        if _syncing: return
        _ins_at_head.button_pressed = true
        ed._scrub_to(v)
        _sync_insert())
    g.add_child(_ins_head)
    _ins_at_sec = _check("at second", "Start the effect at this time, wherever the playhead is.")
    _ins_at_sec.button_group = bg
    g.add_child(_ins_at_sec)
    _ins_sec = _spin(0.0, 600.0, 0.01, "Seconds from the start of this animation.")
    _ins_sec.value_changed.connect(func(_v):
        if _syncing: return
        _ins_at_sec.button_pressed = true
        _sync_insert())
    g.add_child(_ins_sec)
    _ins_at_head.toggled.connect(func(_on): _sync_insert())

    col.add_child(ZenUI.label("Length", ZenUI.TITLE))
    var lr := HBoxContainer.new()
    col.add_child(lr)
    lr.add_child(ZenUI.label("ratio", ZenUI.TEXT))
    _ins_ratio = SpinBox.new()
    _ins_ratio.min_value = 0.1
    _ins_ratio.max_value = 10.0
    _ins_ratio.step = 0.05
    _ins_ratio.value = 1.0
    _ins_ratio.prefix = "x"
    _ins_ratio.tooltip_text = "Multiplies the effect's length: 0.5 plays it twice as fast, 2 "
    _ins_ratio.tooltip_text += "half as fast. Its eases keep their shape."
    _ins_ratio.value_changed.connect(func(_v): _sync_insert())
    lr.add_child(_ins_ratio)

    col.add_child(ZenUI.label("Names", ZenUI.TITLE))
    var nr := HBoxContainer.new()
    col.add_child(nr)
    _ins_prefix_on = _check("prefix", "Put this in front of every inserted element's name, so "
        + "the effect's elements are easy to tell apart in the Elements panel.")
    _ins_prefix_on.toggled.connect(func(_on): _sync_insert())
    nr.add_child(_ins_prefix_on)
    _ins_prefix = LineEdit.new()
    _ins_prefix.custom_minimum_size = Vector2(160, 0)
    _ins_prefix.tooltip_text = _ins_prefix_on.tooltip_text
    _ins_prefix.text_changed.connect(func(_t):
        _ins_prefix_on.set_pressed_no_signal(true)
        _sync_insert())
    nr.add_child(_ins_prefix)
    _ins_names = ZenUI.label("", ZenUI.TEXT, 12)
    _ins_names.autowrap_mode = TextServer.AUTOWRAP_WORD
    _ins_names.custom_minimum_size.x = 360
    col.add_child(_ins_names)
    _ins_info = _info(col)
    _ins_dialog.confirmed.connect(_apply_insert)
    _ins_dialog.visibility_changed.connect(func(): if not _ins_dialog.visible: _drop_fx())


## Insert: the dialog, on the Effects panel's selection (or `path`).
func ask_insert(path := "") -> void:
    if not _doc_mode(): return
    if path == "": path = selected_path()
    _ins_pick.clear()
    var pick := -1
    var first := -1
    for grp in grouped():
        _ins_pick.add_separator("%s/" % grp[0] if grp[0] != "" else "(top level)")
        for row in grp[1]:
            _ins_pick.add_item(String(row[0]))
            var ix := _ins_pick.item_count - 1
            _ins_pick.set_item_metadata(ix, row[1])
            if first < 0: first = ix
            if row[1] == path: pick = ix
    if first < 0:
        ed._set_status("there is no other animation to insert")
        return
    _ins_pick.select(pick if pick >= 0 else first)
    _syncing = true
    _ins_head.value = ed._t
    _ins_sec.value = ed._t
    _ins_ratio.value = 1.0
    _syncing = false
    _ins_at_head.button_pressed = true
    _ins_prefix_on.set_pressed_no_signal(false)
    _load_fx()
    _ins_dialog.popup_centered()


func _load_fx() -> void:
    _drop_fx()
    var ix := _ins_pick.selected
    _ins_path = String(_ins_pick.get_item_metadata(ix)) if ix >= 0 else ""
    if _ins_path != "": _ins_fx = ZenSceneOps.open(_ins_path)
    var nm := _ins_path.get_file().get_basename()
    _ins_prefix.text = nm.trim_prefix("fx_") + "_"
    _sync_insert()


func _drop_fx() -> void:
    if _ins_fx != null and is_instance_valid(_ins_fx): _ins_fx.free()
    _ins_fx = null


func insert_at() -> float:
    return _ins_head.value if _ins_at_head.button_pressed else _ins_sec.value


func insert_prefix() -> String:
    return _ins_prefix.text.strip_edges() if _ins_prefix_on.button_pressed else ""


func _sync_insert() -> void:
    if _ins_fx == null:
        _ins_about.text = "could not open this animation"
        _ins_info.text = ""
        _ins_names.text = ""
        _ins_dialog.get_ok_button().disabled = true
        return
    _ins_dialog.get_ok_button().disabled = false
    var c := ed._canvas
    var rows := ZenElemOps.rows(_ins_fx).size()
    var sigs := ZenSignalOps.names(_ins_fx).size()
    _ins_about.text = "%.2fs, %d element(s)%s" % [_ins_fx.duration, rows,
        ", %d signal(s) - not inserted" % sigs if sigs > 0 else ""]
    var r := _ins_ratio.value
    var fx_len := _ins_fx.duration * r
    var at := insert_at()
    var s := "length %.2fs x %.2f = %.2fs, from %.2fs to %.2fs" % [_ins_fx.duration, r, fx_len, at, at + fx_len]
    if at + fx_len > c.duration + EPS:
        s += "\nthis animation grows from %.2fs to %.2fs" % [c.duration, at + fx_len]
    _ins_info.text = s
    var names := ZenClipOps.names_for(c, _ins_fx, insert_prefix())
    var shown := names.slice(0, 4)
    _ins_names.text = "adds: " + ", ".join(PackedStringArray(shown)) + (", ..." if names.size() > shown.size() else "")


func _apply_insert() -> void:
    if _ins_path == "": return
    var fx := ZenSceneOps.open(_ins_path)
    if fx == null:
        ed._set_status("could not open %s" % _ins_path)
        return
    ZenDocOps.retime(fx, _ins_ratio.value)
    var at := insert_at()
    var prefix := insert_prefix()
    var c := ed._canvas
    var made: Array = []
    # A lambda captures `made` by value: fill the array, do not reassign it.
    ed._command("insert %s" % _ins_path.get_file().get_basename(), func():
        made.assign(ZenClipOps.paste(c, fx, at, prefix)))
    fx.free()
    if made.is_empty(): return
    var out: Array[String] = []
    for el in made: out.append((el as ZenElement).elem_name)
    ed._sel = out
    ed._on_selection_changed(true)


# ---------------------------------------------------------------- helpers

## These tools work on the document timeline, not a signal's keys.
func _doc_mode() -> bool:
    if ed._sig_edit == "": return true
    ed._set_status("leave the signal's key mode first (Esc)")
    return false
