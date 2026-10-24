class_name ZenSignalPanel
extends VBoxContainer
##
## The scene editor's Signals panel: the scene's signals, and the fields of
## the one picked - what it animates (its keys, edited on the timeline in
## signal key mode), when it fires (trigger) and how it reacts to a point.
##
## Like ZenKeyPanel it edits nothing. The editor hands it a model through
## set_model() and turns its signals into ZenSignalOps calls, so undo and
## refresh stay in one place.
##
## Model:
##   signals: [signals_data entries]   (read only)
##   picked:  the signal whose fields show, "" for none
##   editing: the signal whose keys the timeline edits, "" for the document
##   clash:   name of an earlier signal sharing picked's trigger, or ""
##   targets: ["elem.prop"] the picked signal keys
##

signal pick_requested(signal_name: String)
signal add_requested
signal delete_requested(signal_name: String)
signal rename_requested(from: String, to: String)
signal fire_requested(signal_name: String)
signal field_set(signal_name: String, key: String, value: Variant)
signal bind_requested(signal_name: String)
signal unbind_requested(signal_name: String, elem: String)
signal offset_set(signal_name: String, elem: String, off: Vector2)
signal edit_keys_requested(signal_name: String, on: bool)

const TRIGGER_TIPS := {
    "code": "only when fired - fire(), ZenSignals.emit(), keys 1-9 while playing",
    "press": "on a mouse press over the canvas, at the press position",
    "release": "on a mouse release over the canvas, at the release position",
    "end": "when the timeline ends - a one-shot's end, or a loop's wrap"}
const POINT_TIPS := {
    "none": "the signal ignores positions",
    "anchor": "bound elements play their path moved to start at the point",
    "seek": "bound elements ease to the point over the length",
    "follow": "bound elements ease to the pointer and keep following it"}

var _signals: Array = []
var _picked := ""
var _editing := ""
var _syncing := false
var _shape_sig := ""

var _list: ItemList
var _fields: VBoxContainer
var _rows: Dictionary = {}              ## field -> Control, rebuilt with the fields


func _init() -> void:
    size_flags_vertical = SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 4)
    _list = ItemList.new()
    _list.custom_minimum_size = Vector2(0, 90)
    _list.size_flags_vertical = SIZE_EXPAND_FILL
    _list.item_selected.connect(func(i): pick_requested.emit(String(_list.get_item_metadata(i))))
    _list.item_activated.connect(func(i): fire_requested.emit(String(_list.get_item_metadata(i))))
    add_child(_list)
    var bar := HFlowContainer.new()
    add_child(bar)
    for spec in [["+ signal", "Add a signal", func(): add_requested.emit()],
                 ["fire", "Fire the picked signal from the pose at the playhead (double-click a row)",
                  func(): if _picked != "": fire_requested.emit(_picked)],
                 ["delete", "Delete the picked signal", func(): if _picked != "": delete_requested.emit(_picked)]]:
        var b := ZenEditorPanel._tool_button(spec[0], spec[1])
        b.flat = false
        b.pressed.connect(spec[2])
        bar.add_child(b)
    var sc := ScrollContainer.new()
    sc.size_flags_vertical = SIZE_EXPAND_FILL
    sc.size_flags_stretch_ratio = 2.0
    sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(sc)
    _fields = VBoxContainer.new()
    _fields.size_flags_horizontal = SIZE_EXPAND_FILL
    _fields.add_theme_constant_override("separation", 4)
    sc.add_child(_fields)


func set_model(signals: Array, picked: String, editing: String, clash: String,
               targets: Array) -> void:
    _signals = signals
    _picked = picked
    _editing = editing
    _refresh_list()
    var sig := _sig()
    var shape := "%s|%s|%s|%s|%s|%s|%s" % [picked, editing, sig.get("trigger", ""),
        sig.get("point", ""), sig.get("terminal", false),
        ",".join((sig.get("point_elems", []) as Array).map(func(pe): return pe["elem"])),
        ",".join(_names())]
    if shape != _shape_sig:
        _shape_sig = shape
        _build_fields()
    _refresh_fields(clash, targets)


func _names() -> Array:
    return _signals.map(func(s): return String(s["name"]))


func _sig() -> Dictionary:
    for s in _signals:
        if String(s["name"]) == _picked: return s
    return {}


func _refresh_list() -> void:
    _list.clear()
    for s in _signals:
        var nm := String(s["name"])
        var tags: Array = [String(s.get("trigger", "code"))]
        if String(s.get("point", "none")) != "none": tags.append(String(s["point"]))
        if bool(s.get("terminal", false)): tags.append("terminal")
        if not String(s.get("then", "")).is_empty(): tags.append("then " + String(s["then"]))
        var i := _list.add_item("%s%s   [%s]" % ["✎ " if nm == _editing else "", nm, ", ".join(tags)])
        _list.set_item_metadata(i, nm)
        if nm == _picked: _list.select(i)
    if _signals.is_empty():
        _list.add_item("no signals - + signal adds one")
        _list.set_item_disabled(0, true)
        _list.set_item_metadata(0, "")


# ---------------------------------------------------------------- fields

func _build_fields() -> void:
    for c in _fields.get_children():
        _fields.remove_child(c)
        c.queue_free()
    _rows.clear()
    var sig := _sig()
    if sig.is_empty(): return
    var nm := _picked

    var keys := Button.new()
    keys.toggle_mode = true
    keys.button_pressed = _editing == nm
    keys.text = "editing keys - timeline shows this signal" if _editing == nm else "edit keys on the timeline"
    keys.tooltip_text = "Key what this signal animates: the timeline and auto-key edit the signal\n" \
        + "(0..length), not the document. Its first key is the pose captured at fire time."
    keys.toggled.connect(func(on): edit_keys_requested.emit(nm, on))
    _fields.add_child(keys)
    _rows["targets"] = ZenUI.label("", ZenUI.DIM, 11)
    (_rows["targets"] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD
    _fields.add_child(_rows["targets"])

    var g := GridContainer.new()
    g.columns = 2
    g.add_theme_constant_override("h_separation", 6)
    _fields.add_child(g)
    var ne := LineEdit.new()
    ne.size_flags_horizontal = SIZE_EXPAND_FILL
    ne.text_submitted.connect(func(t): _rename(nm, t))
    ne.focus_exited.connect(func(): _rename(nm, ne.text))
    _row(g, "name", ne)
    var ln := SpinBox.new()
    ln.min_value = 0.0
    ln.max_value = 60.0
    ln.step = 0.01
    ln.suffix = "s"
    ln.tooltip_text = "Seconds the transition takes; 0 lands on its final keys at once"
    ln.value_changed.connect(func(v): _emit_field(nm, "length", v))
    _row(g, "length", ln)
    _row(g, "terminal", _check("the scene ends on this signal, holding its end pose",
        func(on): _emit_field(nm, "terminal", on)))
    _row(g, "replay", _check("restart the timeline when this fires",
        func(on): _emit_field(nm, "replay", on)))

    _fields.add_child(HSeparator.new())
    var tg := GridContainer.new()
    tg.columns = 2
    tg.add_theme_constant_override("h_separation", 6)
    _fields.add_child(tg)
    _row(tg, "trigger", _options(ZenSignalData.TRIGGERS, TRIGGER_TIPS,
        func(v): _emit_field(nm, "trigger", v)))
    if String(sig["trigger"]) == "end":
        _row(tg, "every loop", _check("on a looping timeline fire on every wrap, not just the first",
            func(on): _emit_field(nm, "every_loop", on)))
    if ZenSignalData.chained({"terminal": sig["terminal"], "point": sig["point"], "then": "x"}) != "":
        var others: Array = [""]
        for o in _names():
            if o != nm: others.append(o)
        _row(tg, "then", _options(others, {}, func(v): _emit_field(nm, "then", v), "(nothing)"))
    _rows["clash"] = ZenUI.label("", ZenUI.WARN, 11)
    (_rows["clash"] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD
    _fields.add_child(_rows["clash"])

    _fields.add_child(HSeparator.new())
    var pg := GridContainer.new()
    pg.columns = 2
    pg.add_theme_constant_override("h_separation", 6)
    _fields.add_child(pg)
    _row(pg, "point", _options(ZenSignalData.POINTS, POINT_TIPS, func(v): _emit_field(nm, "point", v)))
    var mode := String(sig["point"])
    if mode == "none": return
    if mode != "anchor":
        _row(pg, "ease", _options(ZenEasing.all_names(), {}, func(v): _emit_field(nm, "point_ease", v)))
    for pe in sig["point_elems"]:
        var el := String(pe["elem"])
        var row := HBoxContainer.new()
        _fields.add_child(row)
        var l := ZenUI.label(el, ZenUI.TEXT)
        l.size_flags_horizontal = SIZE_EXPAND_FILL
        l.clip_text = true
        row.add_child(l)
        var sx := _off_spin()
        var sy := _off_spin()
        sx.tooltip_text = "offset from the point, x (canvas fraction)"
        sy.tooltip_text = "offset from the point, y (canvas fraction)"
        var push := func(_v): if not _syncing: offset_set.emit(nm, el, Vector2(sx.value, sy.value))
        sx.value_changed.connect(push)
        sy.value_changed.connect(push)
        row.add_child(sx)
        row.add_child(sy)
        var x := ZenEditorPanel._tool_button("x", "Unbind %s" % el)
        x.pressed.connect(func(): unbind_requested.emit(nm, el))
        row.add_child(x)
        _rows["off:" + el] = [sx, sy]
    var bind := ZenEditorPanel._tool_button("bind selected elements", "The selected elements react to the point")
    bind.flat = false
    bind.pressed.connect(func(): bind_requested.emit(nm))
    _fields.add_child(bind)


func _refresh_fields(clash: String, targets: Array) -> void:
    var sig := _sig()
    if sig.is_empty(): return
    _syncing = true
    for c in [["name", "name"], ["length", "length"], ["terminal", "terminal"],
              ["replay", "replay"], ["trigger", "trigger"], ["every loop", "every_loop"],
              ["then", "then"], ["point", "point"], ["ease", "point_ease"]]:
        var ctl: Control = _rows.get(c[0])
        if ctl == null: continue
        var v: Variant = sig.get(c[1])
        if ctl is LineEdit:
            if not ctl.has_focus(): (ctl as LineEdit).text = String(v)
        elif ctl is SpinBox: (ctl as SpinBox).set_value_no_signal(float(v))
        elif ctl is CheckBox: (ctl as CheckBox).set_pressed_no_signal(bool(v))
        elif ctl is OptionButton:
            var ob := ctl as OptionButton
            for i in ob.item_count:
                if String(ob.get_item_metadata(i)) == String(v): ob.select(i)
    for pe in sig["point_elems"]:
        var spins: Array = _rows.get("off:" + String(pe["elem"]), [])
        if spins.size() == 2:
            (spins[0] as SpinBox).set_value_no_signal((pe["off"] as Vector2).x)
            (spins[1] as SpinBox).set_value_no_signal((pe["off"] as Vector2).y)
    (_rows["clash"] as Label).text = "" if clash.is_empty() else \
        "%s fires first on this trigger - this one never will" % clash
    (_rows["targets"] as Label).text = "animates: " + (", ".join(targets) if not targets.is_empty()
        else "nothing keyed yet")
    _syncing = false


func _row(g: GridContainer, text: String, ctl: Control) -> void:
    g.add_child(ZenUI.label(text, ZenUI.LABEL))
    ctl.size_flags_horizontal = SIZE_EXPAND_FILL
    g.add_child(ctl)
    _rows[text] = ctl


func _check(tip: String, fn: Callable) -> CheckBox:
    var c := CheckBox.new()
    c.tooltip_text = tip
    c.focus_mode = FOCUS_NONE
    c.toggled.connect(func(on): if not _syncing: fn.call(on))
    return c


## An OptionButton over `values`, each item's metadata its value.
func _options(values: Array, tips: Dictionary, fn: Callable, empty_label := "") -> OptionButton:
    var ob := OptionButton.new()
    ob.fit_to_longest_item = false
    for v in values:
        ob.add_item(String(v) if not String(v).is_empty() else empty_label)
        ob.set_item_metadata(ob.item_count - 1, v)
        if tips.has(v): ob.set_item_tooltip(ob.item_count - 1, String(tips[v]))
    ob.item_selected.connect(func(i): if not _syncing: fn.call(ob.get_item_metadata(i)))
    return ob


func _off_spin() -> SpinBox:
    var s := SpinBox.new()
    s.min_value = -1.0
    s.max_value = 1.0
    s.step = 0.01
    s.allow_greater = true
    s.allow_lesser = true
    s.custom_minimum_size = Vector2(76, 0)
    return s


func _emit_field(nm: String, key: String, v: Variant) -> void:
    if not _syncing: field_set.emit(nm, key, v)


func _rename(nm: String, t: String) -> void:
    t = t.strip_edges()
    if _syncing or t.is_empty() or t == nm: return
    rename_requested.emit(nm, t)
