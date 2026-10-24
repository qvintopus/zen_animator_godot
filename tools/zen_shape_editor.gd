class_name ZenShapeEditor
extends Control
##
## Pixel-shape editor: create and edit the ZenPixelShape assets that custom
## shape elements draw. Opened from the gallery's "assets (visual)" section.
##
## Feature parity with the original (src/shape_editor/shape_editor.c) - ink
## brush with erase, brush size, resize keeping the top-left, clear, bulk ink,
## undo, save, and reference-image trace + convert - plus redo, line / rect /
## flood-fill tools, mirrored drawing, auto-outline, rename / duplicate,
## and a live preview tinted with pickable fill and outline
## colours (the asset itself carries no colour: the element tints it).
##
## Godot integration, rather than reimplemented machinery:
##   - the asset is a Resource saved with ResourceSaver (ZenAssets), and a
##     save updates the loaded instance, so open animations redraw at once;
##   - undo/redo is Godot's UndoRedo, one action per stroke or command;
##   - the reference image loads through a native FileDialog or by dropping
##     a file on the window, and decodes through Image.
##
## The editor works on a COPY of the asset: nothing the rest of the app sees
## changes until Save.
##
## The UI is built in code like the Export dialog: ~40 controls with live
## enable rules are less brittle as code than as a node-path tree.
##

signal closed

const NEW_SIZE := Vector2i(24, 16)
## Reference samples per cell axis for Convert: a box average over k*k.
const REF_SAMPLES := 3

var _shape: ZenPixelShape = null      # the working copy
var _name := ""                       # "" until first saved
var _undo := UndoRedo.new()
var _saved_version := 0
var _before: Dictionary = {}          # snapshot taken at stroke start

# Reference image
var _ref_src: Image = null            # full-size, RGBA8
var _ref_scale := 1.0                 # relative to the fitted size
var _ref_threshold := 0.5
var _ref_invert := false
var _ref_preview := false
var _mask_dirty := false

var _canvas: ZenPixelCanvas
var _title: Label
var _status: Label
var _hint: Label
var _cell_label: Label
var _size_w: SpinBox
var _size_h: SpinBox
var _brush_slider: HSlider
var _brush_label: Label
var _mirror: CheckBox
var _tool_btns: Array[Button] = []
var _ink_btns: Array[Button] = []
var _fill_pick: ColorPickerButton
var _line_pick: ColorPickerButton
var _preview_1x: ZenShapePreview
var _preview_big: ZenShapePreview
var _ref_controls: Array[Control] = []
var _ref_fade: HSlider
var _ref_thresh: HSlider
var _ref_scale_slider: HSlider
var _ref_x: SpinBox
var _ref_y: SpinBox
var _ref_name: Label
var _syncing := false

var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_w: SpinBox
var _name_h: SpinBox
var _name_size_row: Control
var _name_error: Label
var _name_mode := ""                  # "new" | "rename" | "duplicate" | "save"
var _confirm: ConfirmationDialog
var _confirm_action := Callable()
var _leave_dialog: ConfirmationDialog
var _ref_dialog: FileDialog
var _help := ZenHotkeyHelp.new()


func _ready() -> void:
    _build_ui()
    get_window().files_dropped.connect(_on_files_dropped)
    set_process(true)


func _exit_tree() -> void:
    if get_window().files_dropped.is_connected(_on_files_dropped):
        get_window().files_dropped.disconnect(_on_files_dropped)
    _undo.free()


## Open `name` for editing, or a blank shape when it is "".
func open(name: String) -> void:
    var src: ZenPixelShape = ZenAssets.load_shape(name) if name != "" else null
    if src != null:
        _set_shape(src.duplicate(true) as ZenPixelShape, name)
        _set_status("editing %s" % name)
    else:
        var s := ZenPixelShape.new()
        s.size = NEW_SIZE
        _set_shape(s, "")
        _set_status("new shape - Ctrl+S to save it under a name")
    # Fit once the canvas has its laid-out size.
    await get_tree().process_frame
    _canvas.fit()


## The asset's name, so the gallery can select it after closing.
func current_name() -> String:
    return _name


func _set_shape(s: ZenPixelShape, nm: String) -> void:
    _shape = s
    _name = nm
    _canvas.shape = s
    _preview_1x.shape = s
    _preview_big.shape = s
    _undo.clear_history()
    _saved_version = _undo.get_version()
    _sync_controls()


func _dirty() -> bool:
    return _undo.get_version() != _saved_version or _name == ""


# ---------------------------------------------------------------- undo

func _snapshot() -> Dictionary:
    return {"size": _shape.size, "cells": _shape.cells.duplicate()}


func _restore(snap: Dictionary) -> void:
    _shape.size = snap["size"]
    _shape.cells = (snap["cells"] as PackedByteArray).duplicate()
    _sync_controls()


## Record one undo step from `before` to the current state. Nothing is
## recorded when the action changed nothing (a click on same-ink cells).
func _record(label: String, before: Dictionary) -> void:
    var after := _snapshot()
    if after["size"] == before["size"] and after["cells"] == before["cells"]: return
    _undo.create_action(label)
    _undo.add_do_method(_restore.bind(after))
    _undo.add_undo_method(_restore.bind(before))
    _undo.commit_action(false)          # already applied
    _sync_title()


## Run `fn` as one undoable command.
func _command(label: String, fn: Callable) -> void:
    var before := _snapshot()
    fn.call()
    _record(label, before)
    _set_status(label)


func _do_undo() -> void:
    if _undo.undo(): _set_status("undo: %s" % _undo.get_current_action_name())
    _sync_title()


func _do_redo() -> void:
    if _undo.redo(): _set_status("redo: %s" % _undo.get_current_action_name())
    _sync_title()


# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
    # Created first: the panel's controls are wired straight to it.
    _canvas = ZenPixelCanvas.new()
    var rows := ZenUI.build_shell(self)

    var head := HBoxContainer.new()
    _title = Label.new()
    _title.size_flags_horizontal = SIZE_EXPAND_FILL
    _title.add_theme_color_override("font_color", ZenUI.TITLE)
    _title.add_theme_font_size_override("font_size", 22)
    head.add_child(_title)
    _cell_label = Label.new()
    _cell_label.add_theme_color_override("font_color", ZenUI.DIM)
    head.add_child(_cell_label)
    rows.add_child(head)
    rows.add_child(HSeparator.new())

    var body := HBoxContainer.new()
    body.size_flags_vertical = SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 14)
    rows.add_child(body)

    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(290, 0)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(scroll)
    var panel := VBoxContainer.new()
    panel.size_flags_horizontal = SIZE_EXPAND_FILL
    panel.add_theme_constant_override("separation", 6)
    scroll.add_child(panel)
    _build_panel(panel)

    _canvas.size_flags_horizontal = SIZE_EXPAND_FILL
    _canvas.size_flags_vertical = SIZE_EXPAND_FILL
    _canvas.stroke_begun.connect(func(): _before = _snapshot())
    _canvas.stroke_ended.connect(func(): _record("paint", _before))
    _canvas.hover_changed.connect(_on_hover)
    _canvas.reference_moved.connect(_on_ref_moved)
    body.add_child(_canvas)

    var side := VBoxContainer.new()
    side.custom_minimum_size = Vector2(200, 0)
    side.add_theme_constant_override("separation", 6)
    body.add_child(side)
    _build_preview(side)

    rows.add_child(HSeparator.new())
    _status = Label.new()
    _status.add_theme_color_override("font_color", ZenUI.TEXT)
    rows.add_child(_status)
    _hint = Label.new()
    _hint.add_theme_color_override("font_color", ZenUI.DIM)
    # Essentials only; the full list is the H sheet. A long legend here
    # would set the window's minimum width.
    _hint.text = "  LMB paint      RMB erase      " + ZenHotkeyHelp.footer([
        ["zen_edit_undo", "undo"], ["zen_edit_save", "save"],
        ["zen_help", "help"], ["zen_back", "back"]]).strip_edges()
    _hint.clip_text = true
    _hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    rows.add_child(_hint)
    add_child(_help)

    _build_dialogs()


func _section(parent: Control, text: String) -> void:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", ZenUI.LABEL)
    parent.add_child(l)


func _button(parent: Control, text: String, fn: Callable, tip := "") -> Button:
    var b := Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.tooltip_text = tip
    b.pressed.connect(fn)
    parent.add_child(b)
    return b


func _hrow(parent: Control) -> HBoxContainer:
    var r := HBoxContainer.new()
    r.add_theme_constant_override("separation", 4)
    parent.add_child(r)
    return r


func _grid(parent: Control, cols: int) -> GridContainer:
    var g := GridContainer.new()
    g.columns = cols
    g.add_theme_constant_override("h_separation", 4)
    g.add_theme_constant_override("v_separation", 4)
    parent.add_child(g)
    return g


## A labelled slider; `fn` gets the value.
func _slider(parent: Control, text: String, lo: float, hi: float, step: float,
             fn: Callable) -> HSlider:
    var r := _hrow(parent)
    var l := Label.new()
    l.text = text
    l.custom_minimum_size = Vector2(70, 0)
    l.add_theme_color_override("font_color", ZenUI.TEXT)
    r.add_child(l)
    var s := HSlider.new()
    s.min_value = lo
    s.max_value = hi
    s.step = step
    s.size_flags_horizontal = SIZE_EXPAND_FILL
    s.size_flags_vertical = SIZE_SHRINK_CENTER
    s.focus_mode = Control.FOCUS_NONE
    s.value_changed.connect(fn)
    r.add_child(s)
    return s


func _build_panel(p: VBoxContainer) -> void:
    _button(p, "< back to gallery", _request_leave)

    _section(p, "shape")
    var g := _grid(p, 3)
    _button(g, "new", _ask_name.bind("new"))
    _button(g, "duplicate", _ask_name.bind("duplicate"))
    _button(g, "rename", _ask_name.bind("rename"))
    _button(g, "delete", _ask_delete)
    _button(g, "save", _save, "Ctrl+S")

    _section(p, "tool")
    var tg := _grid(p, 4)
    var tool_names := ["pen", "line", "rect", "fill"]
    var tool_keys := ["P", "L", "R", "G"]
    for i in tool_names.size():
        var b := _button(tg, tool_names[i], _set_tool.bind(i), "%s" % tool_keys[i])
        b.toggle_mode = true
        _tool_btns.append(b)

    _section(p, "ink")
    var ig := _grid(p, 3)
    var ink_names := ["empty", "fill", "rim"]
    for i in 3:
        var b := _button(ig, ink_names[i], _set_ink.bind(i), str(i + 1))
        b.toggle_mode = true
        _ink_btns.append(b)
    _brush_slider = _slider(p, "brush", 1, 32, 1, func(v): _set_brush(int(v)))
    _brush_label = _brush_slider.get_parent().get_child(0)
    _mirror = CheckBox.new()
    _mirror.text = "mirror X (M)"
    _mirror.focus_mode = Control.FOCUS_NONE
    _mirror.toggled.connect(func(on): _canvas.mirror_x = on; _canvas.queue_redraw())
    p.add_child(_mirror)

    _section(p, "size")
    var sr := _hrow(p)
    _size_w = _spin(sr, 1, ZenPixelShape.GRID_MAX)
    var x := Label.new()
    x.text = "x"
    sr.add_child(x)
    _size_h = _spin(sr, 1, ZenPixelShape.GRID_MAX)
    _size_w.value_changed.connect(func(_v): _on_size_spin())
    _size_h.value_changed.connect(func(_v): _on_size_spin())
    _button(sr, "fit", func(): _canvas.fit(), "F")
    var eg := _grid(p, 2)
    _button(eg, "clear", func(): _command("clear", _shape.clear))
    _button(eg, "auto-outline", func(): _command("auto-outline", _shape.auto_outline),
            "Every fill cell touching empty becomes rim")
    _button(eg, "all -> fill", func(): _command("all ink -> fill", _shape.convert_ink.bind(ZenPixelShape.FILL)))
    _button(eg, "all -> rim", func(): _command("all ink -> rim", _shape.convert_ink.bind(ZenPixelShape.OUTLINE)))
    _button(eg, "undo", _do_undo, "Ctrl+Z")
    _button(eg, "redo", _do_redo, "Ctrl+Shift+Z / Ctrl+Y")

    _section(p, "reference image")
    var rr := _hrow(p)
    _button(rr, "load...", func(): _ref_dialog.popup_centered_ratio(0.7), "Or drop an image on the window")
    _ref_controls.append(_button(rr, "remove", _clear_ref))
    _ref_name = Label.new()
    _ref_name.add_theme_color_override("font_color", ZenUI.DIM)
    _ref_name.clip_text = true
    _ref_name.custom_minimum_size = Vector2(240, 0)
    p.add_child(_ref_name)
    _ref_fade = _slider(p, "fade", 0, 1, 0.01, func(v): _canvas.ref_fade = v; _canvas.queue_redraw())
    _ref_thresh = _slider(p, "threshold", 0.01, 1, 0.01, func(v): _ref_threshold = v; _mask_dirty = true)
    _ref_scale_slider = _slider(p, "scale", 0.1, 4, 0.01, _on_ref_scale)
    var orow := _hrow(p)
    var ol := Label.new()
    ol.text = "offset"
    ol.custom_minimum_size = Vector2(70, 0)
    orow.add_child(ol)
    _ref_x = _spin(orow, -512, 512, 0.5)
    _ref_y = _spin(orow, -512, 512, 0.5)
    _ref_x.value_changed.connect(func(_v): _on_ref_offset())
    _ref_y.value_changed.connect(func(_v): _on_ref_offset())
    var fg := _grid(p, 3)
    _ref_controls.append(_button(fg, "fit", _fit_ref))
    _ref_controls.append(_button(fg, "center", _center_ref))
    _ref_controls.append(_button(fg, "reset", _fit_ref))
    var cp := CheckBox.new()
    cp.text = "threshold preview"
    cp.focus_mode = Control.FOCUS_NONE
    cp.toggled.connect(func(on): _ref_preview = on; _mask_dirty = true)
    p.add_child(cp)
    var ci := CheckBox.new()
    ci.text = "invert (dark ink on light)"
    ci.focus_mode = Control.FOCUS_NONE
    ci.toggled.connect(func(on): _ref_invert = on; _mask_dirty = true)
    p.add_child(ci)
    _ref_controls.append_array([_ref_fade, _ref_thresh, _ref_scale_slider, _ref_x, _ref_y, cp, ci])
    _ref_controls.append(_button(p, "convert -> pixels", _convert_ref,
                                 "Replace the shape with the thresholded reference, outline derived"))
    _ref_fade.value = 0.5
    _ref_thresh.value = 0.5
    _ref_scale_slider.value = 1.0
    _sync_ref_controls()


func _spin(parent: Control, lo: float, hi: float, step := 1.0) -> SpinBox:
    var s := SpinBox.new()
    s.min_value = lo
    s.max_value = hi
    s.step = step
    s.allow_greater = false
    s.custom_minimum_size = Vector2(76, 0)
    parent.add_child(s)
    return s


func _build_preview(side: VBoxContainer) -> void:
    _section(side, "colors")
    var r1 := _hrow(side)
    var l1 := Label.new()
    l1.text = "fill"
    l1.custom_minimum_size = Vector2(60, 0)
    r1.add_child(l1)
    _fill_pick = ColorPickerButton.new()
    _fill_pick.color = Color(0.96, 0.96, 0.96, 1)
    _fill_pick.custom_minimum_size = Vector2(100, 26)
    _fill_pick.color_changed.connect(_on_colors)
    r1.add_child(_fill_pick)
    var r2 := _hrow(side)
    var l2 := Label.new()
    l2.text = "outline"
    l2.custom_minimum_size = Vector2(60, 0)
    r2.add_child(l2)
    _line_pick = ColorPickerButton.new()
    _line_pick.color = Color(0.38, 0.686, 0.937, 1)
    _line_pick.custom_minimum_size = Vector2(100, 26)
    _line_pick.color_changed.connect(_on_colors)
    r2.add_child(_line_pick)
    var note := Label.new()
    note.text = "Preview only: an animation tints the shape with its own color tracks."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD
    note.add_theme_color_override("font_color", ZenUI.DIM)
    note.custom_minimum_size = Vector2(190, 0)
    side.add_child(note)

    _section(side, "1x")
    _preview_1x = ZenShapePreview.new()
    _preview_1x.zoom = 1.0
    _preview_1x.custom_minimum_size = Vector2(190, 90)
    side.add_child(_preview_1x)
    _section(side, "preview")
    _preview_big = ZenShapePreview.new()
    _preview_big.size_flags_vertical = SIZE_EXPAND_FILL
    _preview_big.custom_minimum_size = Vector2(190, 100)
    side.add_child(_preview_big)
    _on_colors(Color())


func _build_dialogs() -> void:
    _name_dialog = ConfirmationDialog.new()
    var col := VBoxContainer.new()
    _name_edit = LineEdit.new()
    _name_edit.placeholder_text = "name"
    _name_edit.custom_minimum_size = Vector2(260, 0)
    _name_edit.text_changed.connect(func(_t): _validate_name())
    _name_edit.text_submitted.connect(func(_t): _on_name_confirmed())
    col.add_child(_name_edit)
    _name_size_row = _hrow(col)
    _name_w = _spin(_name_size_row, 1, ZenPixelShape.GRID_MAX)
    _name_h = _spin(_name_size_row, 1, ZenPixelShape.GRID_MAX)
    _name_error = Label.new()
    _name_error.add_theme_color_override("font_color", ZenUI.WARN)
    col.add_child(_name_error)
    _name_dialog.add_child(col)
    _name_dialog.confirmed.connect(_on_name_confirmed)
    _name_dialog.get_ok_button().disabled = true
    add_child(_name_dialog)

    _confirm = ConfirmationDialog.new()
    _confirm.confirmed.connect(func(): if _confirm_action.is_valid(): _confirm_action.call())
    add_child(_confirm)

    _leave_dialog = ConfirmationDialog.new()
    _leave_dialog.title = "Unsaved changes"
    _leave_dialog.dialog_text = "This shape has unsaved changes."
    _leave_dialog.ok_button_text = "Discard"
    _leave_dialog.add_button("Save", true, "save")
    _leave_dialog.confirmed.connect(func(): closed.emit())
    _leave_dialog.custom_action.connect(_on_leave_action)
    add_child(_leave_dialog)

    _ref_dialog = FileDialog.new()
    _ref_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _ref_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _ref_dialog.use_native_dialog = true
    _ref_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.bmp, *.tga, *.webp, *.svg ; Images"])
    _ref_dialog.file_selected.connect(_load_ref)
    add_child(_ref_dialog)



# ---------------------------------------------------------------- state -> UI

func _sync_controls() -> void:
    if _shape == null: return
    _syncing = true
    _size_w.value = _shape.size.x
    _size_h.value = _shape.size.y
    _syncing = false
    for i in _tool_btns.size(): _tool_btns[i].button_pressed = i == _canvas.tool
    for i in _ink_btns.size(): _ink_btns[i].button_pressed = i == _canvas.ink
    _brush_slider.set_value_no_signal(_canvas.brush)
    _brush_label.text = "brush %d" % _canvas.brush
    _mirror.set_pressed_no_signal(_canvas.mirror_x)
    _mask_dirty = true
    _sync_title()


func _sync_title() -> void:
    if _title == null: return
    var nm := _name if _name != "" else "untitled"
    _title.text = "Shape  %s%s" % [nm, "  *" if _dirty() else ""]


func _set_status(t: String) -> void:
    if _status != null: _status.text = t


func _on_hover(c: Vector2i, inside: bool) -> void:
    if _shape == null: return
    var dims := "%d x %d" % [_shape.size.x, _shape.size.y]
    _cell_label.text = ("cell %d, %d    %s    zoom %dx" % [c.x, c.y, dims, int(_canvas.zoom)]) if inside \
        else ("%s    zoom %dx" % [dims, int(_canvas.zoom)])


func _on_colors(_c: Color) -> void:
    for pv in [_preview_1x, _preview_big]:
        pv.fill_color = _fill_pick.color
        pv.outline_color = _line_pick.color
    _canvas.fill_color = _fill_pick.color
    _canvas.outline_color = _line_pick.color
    _canvas.queue_redraw()


func _set_tool(i: int) -> void:
    _canvas.tool = i as ZenPixelCanvas.Tool
    _sync_controls()


func _set_ink(i: int) -> void:
    _canvas.ink = i
    _sync_controls()


func _set_brush(n: int) -> void:
    _canvas.brush = clampi(n, 1, 32)
    _sync_controls()
    _canvas.queue_redraw()


func _on_size_spin() -> void:
    if _syncing or _shape == null: return
    var nv := Vector2i(int(_size_w.value), int(_size_h.value))
    if nv == _shape.size: return
    _command("resize to %d x %d" % [nv.x, nv.y], func(): _shape.size = nv)


# ---------------------------------------------------------------- files

func _save() -> void:
    if _name == "":
        _ask_name("save")
        return
    var written := ZenAssets.save_shape(_shape, _name)
    if written == null:
        _set_status("could not save %s" % _name)
        return
    # Keep editing a copy: the saved instance is now the one every animation
    # loads, so further edits must not leak into it until the next save. The
    # undo history survives the swap - its snapshots restore by value.
    _shape = written.duplicate(true) as ZenPixelShape
    _canvas.shape = _shape
    _preview_1x.shape = _shape
    _preview_big.shape = _shape
    _saved_version = _undo.get_version()
    _sync_title()
    _set_status("saved %s" % ZenAssets.save_path(_name))


func _ask_name(mode: String) -> void:
    _name_mode = mode
    _name_dialog.title = {"new": "New shape", "rename": "Rename shape",
                          "duplicate": "Duplicate shape", "save": "Save shape as"}[mode]
    _name_edit.text = "" if mode in ["new", "save"] else (_name + ("_copy" if mode == "duplicate" else ""))
    _name_size_row.visible = mode == "new"
    _name_w.value = NEW_SIZE.x
    _name_h.value = NEW_SIZE.y
    if mode == "rename" and _name == "":
        _ask_name("save")
        return
    _validate_name()
    _name_dialog.popup_centered()
    _name_edit.grab_focus()
    _name_edit.select_all()


func _validate_name() -> bool:
    var n := _name_edit.text.strip_edges()
    var err := ""
    if not ZenPixelShape.valid_name(n):
        err = "1-23 chars; no spaces, # / \\ . : and no leading _"
    elif ZenAssets.shape_paths().has(n) and not (_name_mode == "save" and n == _name):
        err = "a shape called %s already exists" % n
    _name_error.text = err
    _name_dialog.get_ok_button().disabled = err != ""
    return err == ""


func _on_name_confirmed() -> void:
    if not _validate_name(): return
    _name_dialog.hide()
    var n := _name_edit.text.strip_edges()
    match _name_mode:
        "new":
            var start := func():
                var s := ZenPixelShape.new()
                s.size = Vector2i(int(_name_w.value), int(_name_h.value))
                _set_shape(s, n)
                _save()
                _canvas.fit()
            if _dirty() and _name != "": _ask_confirm("Discard unsaved changes to %s?" % _name, start)
            else: start.call()
        "save":
            _name = n
            _save()
        "duplicate":
            _name = n
            _save()
            _set_status("duplicated as %s" % n)
        "rename":
            var old := _name
            _name = n
            _save()
            if ZenAssets.shape_paths().has(old): ZenAssets.delete_shape(old)
            _set_status("renamed %s -> %s  (animations referencing %s now draw the missing-shape box)"
                        % [old, n, old])


func _ask_delete() -> void:
    if _name == "" or not ZenAssets.shape_paths().has(_name):
        _set_status("nothing saved to delete")
        return
    _ask_confirm("Delete %s?\nAnimations that use it will draw the missing-shape box." % _name, func():
        var nm := _name
        if ZenAssets.delete_shape(nm) == OK:
            _set_status("deleted %s" % nm)
            var s := ZenPixelShape.new()
            s.size = NEW_SIZE
            _set_shape(s, "")
            _canvas.fit()
        else:
            _set_status("could not delete %s" % nm))


func _ask_confirm(text: String, fn: Callable) -> void:
    _confirm.dialog_text = text
    _confirm_action = fn
    _confirm.popup_centered()



func _request_leave() -> void:
    if _undo.get_version() != _saved_version:
        _leave_dialog.popup_centered()
    else:
        closed.emit()


func _on_leave_action(action: StringName) -> void:
    if action != "save": return
    _leave_dialog.hide()
    _save()
    if not _dirty(): closed.emit()


# ---------------------------------------------------------------- reference

func _on_files_dropped(files: PackedStringArray) -> void:
    if files.is_empty(): return
    _load_ref(files[0])



func _load_ref(path: String) -> void:
    var img := Image.load_from_file(path)
    if img == null or img.is_empty():
        _set_status("could not load image %s" % path)
        return
    img.convert(Image.FORMAT_RGBA8)
    _ref_src = img
    _canvas.ref_texture = ImageTexture.create_from_image(img)
    _ref_name.text = path.get_file()
    _fit_ref()
    _sync_ref_controls()
    _set_status("reference %s  %d x %d" % [path.get_file(), img.get_width(), img.get_height()])


func _clear_ref() -> void:
    _ref_src = null
    _canvas.ref_texture = null
    _canvas.ref_mask = null
    _ref_name.text = ""
    _sync_ref_controls()
    _canvas.queue_redraw()


func _sync_ref_controls() -> void:
    for c in _ref_controls:
        if c is BaseButton: (c as BaseButton).disabled = _ref_src == null
        elif c is Range: (c as Range).editable = _ref_src != null
    if _ref_src == null: _ref_name.text = "none - load or drop an image"


## The reference rect that fits the grid, preserving the image's aspect.
func _fit_rect() -> Rect2:
    var g := Vector2(_shape.size)
    var i := Vector2(_ref_src.get_width(), _ref_src.get_height())
    var k := minf(g.x / i.x, g.y / i.y)
    var sz := i * k
    return Rect2((g - sz) * 0.5, sz)


func _fit_ref() -> void:
    if _ref_src == null: return
    _canvas.ref_rect = _fit_rect()
    _ref_scale = 1.0
    _on_ref_moved()


func _center_ref() -> void:
    if _ref_src == null: return
    var r := _canvas.ref_rect
    r.position = (Vector2(_shape.size) - r.size) * 0.5
    _canvas.ref_rect = r
    _on_ref_moved()


func _on_ref_scale(v: float) -> void:
    if _syncing or _ref_src == null: return
    var r := _canvas.ref_rect
    var c := r.get_center()
    r.size = _fit_rect().size * v
    r.position = c - r.size * 0.5
    _canvas.ref_rect = r
    _on_ref_moved()


func _on_ref_offset() -> void:
    if _syncing or _ref_src == null: return
    _canvas.ref_rect.position = Vector2(_ref_x.value, _ref_y.value)
    _on_ref_moved()


## The rect changed (mouse or a control): reflect it back into the controls.
func _on_ref_moved() -> void:
    if _ref_src == null: return
    _syncing = true
    _ref_scale_slider.value = _canvas.ref_rect.size.x / maxf(_fit_rect().size.x, 0.0001)
    _ref_x.value = _canvas.ref_rect.position.x
    _ref_y.value = _canvas.ref_rect.position.y
    _syncing = false
    _mask_dirty = true
    _canvas.queue_redraw()


## Which cells the reference turns into ink: per cell, the mean of
## luminance x alpha (inverted for dark-on-light art) over a k x k sample of
## the reference, against the threshold. The image is first resampled to k
## pixels per cell, so the samples together cover the cell's area - a box
## average rather than a point sample (CellCoverage in shape_editor.c).
func _ref_ink() -> PackedByteArray:
    var w := _shape.size.x
    var h := _shape.size.y
    var out := PackedByteArray()
    out.resize(w * h)
    var r := _canvas.ref_rect
    var k := REF_SAMPLES
    var iw := maxi(int(roundf(r.size.x * k)), 1)
    var ih := maxi(int(roundf(r.size.y * k)), 1)
    var img := _ref_src.duplicate() as Image
    img.resize(iw, ih, Image.INTERPOLATE_LANCZOS if iw < img.get_width() else Image.INTERPOLATE_BILINEAR)
    var data := img.get_data()
    for y in h:
        for x in w:
            var sum := 0.0
            var n := 0
            for sy in k:
                for sx in k:
                    var px := int(floorf(((float(x) + (sx + 0.5) / k) - r.position.x) * k))
                    var py := int(floorf(((float(y) + (sy + 0.5) / k) - r.position.y) * k))
                    n += 1
                    if px < 0 or py < 0 or px >= iw or py >= ih: continue
                    var o := (py * iw + px) * 4
                    var lum := (0.299 * data[o] + 0.587 * data[o + 1] + 0.114 * data[o + 2]) / 255.0
                    var a := data[o + 3] / 255.0
                    sum += ((1.0 - lum) if _ref_invert else lum) * a
            if n > 0 and sum / n >= _ref_threshold: out[y * w + x] = ZenPixelShape.FILL
    return out


func _convert_ref() -> void:
    if _ref_src == null: return
    _command("converted from reference", func():
        _shape.cells = _ref_ink()
        _shape.auto_outline())


func _process(_dt: float) -> void:
    # The threshold preview is rebuilt at most once a frame, however many
    # slider ticks arrived in it.
    if not _mask_dirty: return
    _mask_dirty = false
    if _ref_src == null or not _ref_preview or _shape == null:
        _canvas.ref_mask = null
    else:
        var ink := _ref_ink()
        var data := PackedByteArray()
        data.resize(ink.size() * 2)
        for i in ink.size():
            data[i * 2] = 255
            data[i * 2 + 1] = 255 if ink[i] != 0 else 0
        var img := Image.create_from_data(_shape.size.x, _shape.size.y, false, Image.FORMAT_LA8, data)
        _canvas.ref_mask = ImageTexture.create_from_image(img)
    _canvas.queue_redraw()


# ---------------------------------------------------------------- keys

func _show_help() -> void:
    _help.show_pages("Shape editor", [{"name": "Paint", "rows": [
        ["LMB", "paint with the active tool and ink"],
        ["RMB", "erase with the active tool"],
        ["zen_edit_tool_pen", "pen"], ["zen_edit_tool_line", "line"],
        ["zen_edit_tool_rect", "rectangle"], ["zen_edit_tool_fill", "flood fill"],
        ["zen_edit_ink_empty", "ink: empty"], ["zen_edit_ink_fill", "ink: fill"],
        ["zen_edit_ink_outline", "ink: rim"],
        ["zen_edit_brush_down", "smaller brush"], ["zen_edit_brush_up", "bigger brush"],
        ["zen_edit_mirror", "mirror X on / off"],
        ["zen_edit_undo", "undo"], ["zen_edit_redo", "redo"]]},
        {"name": "View & file", "rows": [
        ["wheel", "zoom about the cursor"],
        ["MMB drag", "pan"],
        ["zen_edit_fit", "fit the shape in view"],
        ["drop an image", "load it as the reference"],
        ["Alt + drag", "move the reference image"],
        ["Alt + wheel", "scale the reference image"],
        ["zen_edit_save", "save"],
        ["zen_help", "this sheet on / off"],
        ["zen_back", "back to the gallery"]]}])


## Editor keys are named InputMap actions (tools/gen_input_map.gd). They are
## only taken when no text field or dialog has focus, so typing a name never
## switches tools.
func _unhandled_input(ev: InputEvent) -> void:
    if not (ev is InputEventKey) or not ev.is_pressed(): return
    if _name_dialog.visible or _confirm.visible or _leave_dialog.visible: return
    if _help.handle_key(ev):
        get_viewport().set_input_as_handled()
        return
    var handled := true
    if ev.is_action_pressed("zen_help"):
        if not ev.is_echo(): _show_help()
    elif ev.is_action_pressed("zen_back") and not ev.is_echo(): _request_leave()
    elif ev.is_action_pressed("zen_edit_redo", true): _do_redo()
    elif ev.is_action_pressed("zen_edit_undo", true): _do_undo()
    elif ev.is_action_pressed("zen_edit_save") and not ev.is_echo(): _save()
    elif (ev as InputEventKey).ctrl_pressed: handled = false
    elif ev.is_action_pressed("zen_edit_ink_empty"): _set_ink(ZenPixelShape.EMPTY)
    elif ev.is_action_pressed("zen_edit_ink_fill"): _set_ink(ZenPixelShape.FILL)
    elif ev.is_action_pressed("zen_edit_ink_outline"): _set_ink(ZenPixelShape.OUTLINE)
    elif ev.is_action_pressed("zen_edit_brush_down", true): _set_brush(_canvas.brush - 1)
    elif ev.is_action_pressed("zen_edit_brush_up", true): _set_brush(_canvas.brush + 1)
    elif ev.is_action_pressed("zen_edit_fit"): _canvas.fit()
    elif ev.is_action_pressed("zen_edit_tool_pen"): _set_tool(ZenPixelCanvas.Tool.PEN)
    elif ev.is_action_pressed("zen_edit_tool_line"): _set_tool(ZenPixelCanvas.Tool.LINE)
    elif ev.is_action_pressed("zen_edit_tool_rect"): _set_tool(ZenPixelCanvas.Tool.RECT)
    elif ev.is_action_pressed("zen_edit_tool_fill"): _set_tool(ZenPixelCanvas.Tool.FILL)
    elif ev.is_action_pressed("zen_edit_mirror"): _mirror.button_pressed = not _mirror.button_pressed
    else: handled = false
    # Swallow unbound keys too (`handled` only says whether one did
    # something): the gallery underneath must not react to its own keys
    # (I, L, E, digits) while the editor is open.
    get_viewport().set_input_as_handled()
    if handled: _canvas.queue_redraw()
