class_name ZenKeyPanel
extends VBoxContainer
##
## The scene editor's Keys panel: what the picked keys are, and fields to
## change them. Where the timeline shows keys as diamonds, this shows them as
## numbers - and lists EVERY key of the timeline's lanes, so a key that is hard
## to hit on the timeline can be picked here instead.
##
## Like ZenTimelineView it edits nothing. The editor hands it a model through
## set_model() and turns its signals into ZenKeyOps calls, so undo and refresh
## stay in one place.
##
## Several keys edit live: a field shows the value they share, or "mixed", and
## an edit writes to every selected key at once. Time moves the selection as a
## block (its earliest key lands where the field says); stretch scales it about
## that earliest key.
##
## Model:
##   lanes: [{id: "node|prop", label, prop, keys: [{t, v, ease}],
##            range: [lo, hi, step], strings: [[idx, label]] (string only)}]
##   sel:   {"node|prop|idx": true}
##   preview: {samples: PackedFloat32Array} - the single selected key's real
##            incoming segment, or {} to plot the ease alone
##

signal select_requested(ids: Array, additive: bool)
signal seek_requested(t: float)
signal time_shift(dt: float)
signal time_stretch(factor: float)
signal value_set(lane_id: String, v: Variant)
signal ease_set(ease: String)
signal delete_requested
signal duplicate_requested
signal key_here_requested
signal step_requested(dir: int)

const FRAME := 1.0 / 60.0
const T_EPS := 1e-4
const DOUBLE_CLICK := 0.4

var _lanes: Array = []
var _sel: Dictionary = {}
var _playhead := 0.0
var _preview: Dictionary = {}
var _syncing := false
var _tree_sig := ""
var _field_sig := ""
var _scroll_sig := ""                    # the selection the list last scrolled to
var _stretch_last := 100.0
var _last_click := ["", 0]               # [id, msec] for double-click on a row

var _badge: Label
var _tree: Tree
var _fields: VBoxContainer
var _time: SpinBox
var _stretch: SpinBox
var _value_rows: Dictionary = {}         ## lane id -> {editor, mixed: Label}
var _ease_btn: Button
var _ease_note: Label
var _ease_pop: PopupPanel
var _graph: ZenEaseGraph
var _btns: Dictionary = {}


func _init() -> void:
    size_flags_vertical = SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 4)
    _badge = ZenUI.label("", ZenUI.TITLE)
    add_child(_badge)
    _tree = Tree.new()
    _tree.hide_root = true
    _tree.columns = 3
    _tree.select_mode = Tree.SELECT_SINGLE
    _tree.size_flags_vertical = SIZE_EXPAND_FILL
    _tree.custom_minimum_size = Vector2(0, 72)
    _tree.set_column_expand(0, true)
    _tree.set_column_expand(1, true)
    _tree.set_column_expand(2, true)
    _tree.item_mouse_selected.connect(func(_p, _b): _on_row_clicked())
    add_child(_tree)
    # The fields scroll rather than push the panel past its edge: a side
    # panel shares its height with the others on that side.
    var sc := ScrollContainer.new()
    sc.size_flags_vertical = SIZE_EXPAND_FILL
    sc.size_flags_stretch_ratio = 1.6
    sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(sc)
    _fields = VBoxContainer.new()
    _fields.size_flags_horizontal = SIZE_EXPAND_FILL
    _fields.add_theme_constant_override("separation", 4)
    sc.add_child(_fields)
    _ease_pop = PopupPanel.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = ZenUI.BG
    sb.border_color = ZenUI.DIM
    sb.set_border_width_all(1)
    sb.set_content_margin_all(6)
    _ease_pop.add_theme_stylebox_override("panel", sb)
    add_child(_ease_pop)


func set_model(lanes: Array, sel: Dictionary, playhead: float, preview: Dictionary) -> void:
    _lanes = lanes
    _sel = sel
    _playhead = playhead
    _preview = preview
    _refresh_badge()
    _refresh_tree()
    var sig := ",".join(_sorted_ids()) + "/" + ",".join(lanes.map(func(l): return l["id"]))
    if sig != _field_sig:
        _field_sig = sig
        _build_fields()
    _refresh_fields()


# ---------------------------------------------------------------- model reads

func _sorted_ids() -> Array:
    var ids := _sel.keys()
    ids.sort()
    return ids


static func split_id(id: String) -> Array:
    var p := id.rsplit("|", true, 1)
    return [p[0], int(p[1])]


func _lane(lane_id: String) -> Dictionary:
    for l in _lanes:
        if l["id"] == lane_id: return l
    return {}


## lane id -> [idx ascending], only lanes still in the model.
func _by_lane() -> Dictionary:
    var out := {}
    for id in _sel:
        var p := split_id(id)
        var ln := _lane(p[0])
        if ln.is_empty() or p[1] >= (ln["keys"] as Array).size(): continue
        if not out.has(p[0]): out[p[0]] = []
        (out[p[0]] as Array).append(p[1])
    for k in out: (out[k] as Array).sort()
    return out


## Every selected key as {lane, idx, t, v, ease}.
func _selected() -> Array:
    var out: Array = []
    var by := _by_lane()
    for lane_id in by:
        var ln := _lane(lane_id)
        for i in by[lane_id]:
            var k: Dictionary = ln["keys"][i]
            out.append({"lane": ln, "idx": i, "t": float(k["t"]), "v": k["v"], "ease": String(k["ease"])})
    return out


func _earliest() -> float:
    var t := INF
    for k in _selected(): t = minf(t, k["t"])
    return t


static func _fmt_v(prop: String, v: Variant, ln: Dictionary) -> String:
    if v is Color: return "#" + (v as Color).to_html(false)
    if prop == "string":
        for s in ln.get("strings", []):
            if int(s[0]) == int(roundf(float(v))): return String(s[1])
        return "#%d" % int(roundf(float(v)))
    if ZenProps.is_stepped(prop): return "%d" % int(roundf(float(v)))
    return "%.3f" % float(v)


# ---------------------------------------------------------------- badge + list

func _refresh_badge() -> void:
    var by := _by_lane()
    var n := 0
    for k in by: n += (by[k] as Array).size()
    if n == 0:
        _badge.text = "no keys selected - pick one below or on the timeline"
        _badge.add_theme_color_override("font_color", ZenUI.DIM)
    else:
        _badge.text = "%d key%s" % [n, "" if n == 1 else "s"] + \
            ("" if by.size() < 2 else "  ·  %d props" % by.size())
        _badge.add_theme_color_override("font_color", ZenUI.TITLE)


## Rebuilt only when lanes or key counts change; otherwise the rows are
## updated in place, so a double-click lands on the row it started on.
func _refresh_tree() -> void:
    var sig := ""
    for l in _lanes: sig += "%s#%d;" % [l["id"], (l["keys"] as Array).size()]
    if sig != _tree_sig:
        _tree_sig = sig
        _tree.clear()
        var root := _tree.create_item()
        for l in _lanes:
            var li := _tree.create_item(root)
            li.set_metadata(0, "lane:" + String(l["id"]))
            for j in (l["keys"] as Array).size():
                var ki := _tree.create_item(li)
                ki.set_metadata(0, "%s|%d" % [l["id"], j])
    var lane_item := _tree.get_root().get_first_child() if _tree.get_root() != null else null
    var first_sel: TreeItem = null
    for l in _lanes:
        if lane_item == null: break
        var keys: Array = l["keys"]
        var nsel := 0
        var ki := lane_item.get_first_child()
        for j in keys.size():
            var k: Dictionary = keys[j]
            var on := _sel.has("%s|%d" % [l["id"], j])
            if on:
                nsel += 1
                if first_sel == null: first_sel = ki
            var here := absf(float(k["t"]) - _playhead) < T_EPS
            ki.set_text(0, ("▸ " if here else "   ") + "%.3fs" % float(k["t"]))
            ki.set_text(1, _fmt_v(String(l["prop"]), k["v"], l))
            ki.set_text(2, String(k["ease"]))
            ki.set_custom_color(2, ZenTimelineView.ease_color(String(k["ease"])))
            ki.set_custom_color(1, (k["v"] as Color) if k["v"] is Color else ZenUI.TEXT)
            for c in 3:
                if on: ki.set_custom_bg_color(c, Color(ZenUI.LABEL, 0.25))
                else: ki.clear_custom_bg_color(c)
            ki = ki.get_next()
        lane_item.set_text(0, String(l["label"]))
        lane_item.set_text(2, "%d sel" % nsel if nsel > 0 else "%d keys" % keys.size())
        lane_item.set_custom_color(0, ZenUI.TITLE if nsel > 0 else ZenUI.LABEL)
        lane_item.set_custom_color(2, ZenUI.DIM)
        lane_item = lane_item.get_next()
    # Bring a new pick into view - only when the pick changes, so it never
    # fights the user scrolling the list.
    var ssig := ",".join(_sorted_ids())
    if ssig != _scroll_sig:
        _scroll_sig = ssig
        # By id, not by item: a TreeItem handed to a deferred call dangles
        # if the tree is rebuilt first.
        if first_sel != null: _scroll_to.call_deferred(String(first_sel.get_metadata(0)))


func _scroll_to(id: String) -> void:
    if _tree.get_root() == null: return
    var lane := _tree.get_root().get_first_child()
    while lane != null:
        var ki := lane.get_first_child()
        while ki != null:
            if String(ki.get_metadata(0)) == id:
                _tree.scroll_to_item(ki, true)
                return
            ki = ki.get_next()
        lane = lane.get_next()


func _on_row_clicked() -> void:
    var it := _tree.get_selected()
    if it == null: return
    var meta := String(it.get_metadata(0))
    _tree.deselect_all.call_deferred()
    var mods := ZenUI.held_modifiers()
    var additive: bool = mods["shift"] or mods["ctrl"]
    if meta.begins_with("lane:"):
        var ln := _lane(meta.substr(5))
        var ids: Array = []
        for j in (ln.get("keys", []) as Array).size(): ids.append("%s|%d" % [ln["id"], j])
        select_requested.emit(ids, additive)
        return
    var now := Time.get_ticks_msec()
    var again: bool = _last_click[0] == meta and now - int(_last_click[1]) < DOUBLE_CLICK * 1000.0
    _last_click = [meta, now]
    if again:
        var p := split_id(meta)
        seek_requested.emit(float(_lane(p[0])["keys"][p[1]]["t"]))
        return
    select_requested.emit([meta], additive)


# ---------------------------------------------------------------- fields

func _build_fields() -> void:
    for c in _fields.get_children():
        _fields.remove_child(c)
        c.queue_free()
    _value_rows.clear()
    _time = null
    _stretch = null
    _ease_btn = null
    _graph = null
    _btns.clear()
    var sel := _selected()
    if sel.is_empty():
        _fields.add_child(ZenUI.label("click a row (Shift / Ctrl adds), a lane row for all its keys,\n"
            + "double-click to move the playhead there", ZenUI.DIM, 11))
        return
    _fields.add_child(HSeparator.new())
    var g := GridContainer.new()
    g.columns = 2
    g.add_theme_constant_override("h_separation", 6)
    _fields.add_child(g)

    # Time: the selection moves as a block.
    g.add_child(ZenUI.label("time" if sel.size() == 1 else "time (first)", ZenUI.LABEL))
    _time = SpinBox.new()
    _time.min_value = 0.0
    _time.max_value = 3600.0
    _time.step = 0.001
    _time.suffix = "s"
    _time.size_flags_horizontal = SIZE_EXPAND_FILL
    _time.tooltip_text = "Move the selected keys so the first one sits at this time"
    _time.value_changed.connect(func(v): if not _syncing: time_shift.emit(v - _earliest()))
    g.add_child(_time)
    g.add_child(Control.new())
    var trow := HBoxContainer.new()
    g.add_child(trow)
    for spec in [["-f", "Back one frame", func(): time_shift.emit(-FRAME)],
                 ["+f", "Forward one frame", func(): time_shift.emit(FRAME)],
                 ["to playhead", "Move the first selected key to the playhead",
                  func(): time_shift.emit(_playhead - _earliest())]]:
        var b := ZenEditorPanel._tool_button(spec[0], spec[1])
        b.flat = false
        b.pressed.connect(spec[2])
        trow.add_child(b)
    if sel.size() > 1:
        g.add_child(ZenUI.label("stretch", ZenUI.LABEL))
        _stretch = SpinBox.new()
        _stretch.min_value = 1.0
        _stretch.max_value = 1000.0
        _stretch.step = 1.0
        _stretch.suffix = "%"
        _stretch.value = 100.0
        _stretch_last = 100.0
        _stretch.tooltip_text = "Scale the gaps between the selected keys, about the first one"
        _stretch.size_flags_horizontal = SIZE_EXPAND_FILL
        _stretch.value_changed.connect(func(v):
            if _syncing: return
            var f: float = v / _stretch_last
            _stretch_last = v
            time_stretch.emit(f))
        g.add_child(_stretch)

    # One value row per selected lane.
    var by := _by_lane()
    for lane_id in by:
        var ln := _lane(lane_id)
        var prop := String(ln["prop"])
        var lab := ZenUI.label(String(ln["label"]), ZenUI.LABEL)
        lab.clip_text = true
        lab.custom_minimum_size = Vector2(80, 0)
        g.add_child(lab)
        var row := HBoxContainer.new()
        row.size_flags_horizontal = SIZE_EXPAND_FILL
        g.add_child(row)
        var ed: Control
        if ZenProps.is_color(prop):
            var cp := ColorPickerButton.new()
            cp.edit_alpha = false
            cp.custom_minimum_size = Vector2(90, 24)
            cp.color_changed.connect(func(c): if not _syncing: value_set.emit(lane_id, Color(c.r, c.g, c.b, 1.0)))
            ed = cp
        elif prop == "string":
            var ob := OptionButton.new()
            ob.clip_text = true
            ob.fit_to_longest_item = false
            for s in ln.get("strings", []): ob.add_item(String(s[1]), int(s[0]))
            ob.item_selected.connect(func(ix): if not _syncing: value_set.emit(lane_id, float(ob.get_item_id(ix))))
            ed = ob
        else:
            var r: Array = ln.get("range", [-1000.0, 1000.0, 0.01])
            var s := SpinBox.new()
            s.min_value = r[0]
            s.max_value = r[1]
            s.step = r[2]
            s.allow_greater = true
            s.allow_lesser = true
            s.value_changed.connect(func(v): if not _syncing: value_set.emit(lane_id, v))
            ed = s
        # The tag goes first: an expanding editor would push it off the edge.
        var mixed := ZenUI.label("mixed", ZenUI.WARN, 11)
        mixed.tooltip_text = "The selected keys differ - an edit sets them all to one value"
        row.add_child(mixed)
        ed.size_flags_horizontal = SIZE_EXPAND_FILL
        ed.custom_minimum_size.x = 0.0
        row.add_child(ed)
        _value_rows[lane_id] = {"editor": ed, "mixed": mixed, "prop": prop}

    # Ease of the segment INTO each key.
    g.add_child(ZenUI.label("ease", ZenUI.LABEL))
    _ease_btn = Button.new()
    _ease_btn.focus_mode = FOCUS_NONE
    _ease_btn.size_flags_horizontal = SIZE_EXPAND_FILL
    _ease_btn.tooltip_text = "The curve into this key, from the previous one"
    _ease_btn.pressed.connect(_open_ease_picker)
    g.add_child(_ease_btn)
    _ease_note = ZenUI.label("", ZenUI.DIM, 11)
    _fields.add_child(_ease_note)
    _graph = ZenEaseGraph.new()
    _graph.custom_minimum_size = Vector2(0, 64)
    _fields.add_child(_graph)

    var acts := HFlowContainer.new()
    _fields.add_child(acts)
    for spec in [["prev", "Select the key before each selected one", func(): step_requested.emit(-1)],
                 ["next", "Select the key after each selected one", func(): step_requested.emit(1)],
                 ["+key", "Key the selected props at the playhead", func(): key_here_requested.emit()],
                 ["dup", "Copy the selected key to the playhead", func(): duplicate_requested.emit()],
                 ["delete", "Delete the selected keys (DEL)", func(): delete_requested.emit()]]:
        var b := ZenEditorPanel._tool_button(spec[0], spec[1])
        b.flat = false
        b.pressed.connect(spec[2])
        acts.add_child(b)
        _btns[spec[0]] = b


## Field values from the model, without replacing a control (one may be
## under the cursor mid-drag).
func _refresh_fields() -> void:
    var sel := _selected()
    if sel.is_empty() or _time == null: return
    _syncing = true
    _time.set_value_no_signal(_earliest())
    var by := _by_lane()
    for lane_id in _value_rows:
        var row: Dictionary = _value_rows[lane_id]
        var ln := _lane(lane_id)
        if ln.is_empty() or not by.has(lane_id): continue
        var idxs: Array = by[lane_id]
        var first: Variant = ln["keys"][idxs[0]]["v"]
        var same := true
        for i in idxs:
            var v: Variant = ln["keys"][i]["v"]
            same = same and ((v as Color).is_equal_approx(first) if v is Color
                             else absf(float(v) - float(first)) < 1e-6)
        (row["mixed"] as Label).visible = not same
        var ed: Control = row["editor"]
        if ed is ColorPickerButton: (ed as ColorPickerButton).color = first
        elif ed is OptionButton:
            var ob := ed as OptionButton
            ob.select(ob.get_item_index(int(roundf(float(first)))) if same else -1)
            if not same: ob.text = "mixed"
        else: (ed as SpinBox).set_value_no_signal(float(first))

    # Ease: stepped keys and first keys have none to speak of.
    var eases := {}
    var stepped_only := true
    var first_only := true
    for k in sel:
        if ZenProps.is_stepped(String(k["lane"]["prop"])): continue
        stepped_only = false
        if int(k["idx"]) > 0: first_only = false
        eases[k["ease"]] = true
    _ease_btn.disabled = stepped_only
    if stepped_only:
        _ease_btn.text = "steps - no easing"
        _ease_note.text = "a stepped prop snaps at each key and holds until the next"
    else:
        _ease_btn.text = String(eases.keys()[0]) if eases.size() == 1 else "mixed (%d)" % eases.size()
        _ease_note.text = "first key: its ease is not used (nothing comes before it)" if first_only \
            else "the curve into the key, from the one before it"
    var e := String(eases.keys()[0]) if eases.size() == 1 else "linear"
    _graph.samples = _preview.get("samples", PackedFloat32Array())
    _graph.ease = "step" if stepped_only else e
    _graph.caption = "segment into the key" if _graph.samples.size() > 1 \
        else ("%s" % e if eases.size() <= 1 else "mixed - showing linear")

    # Actions: prev/next only where there is a key to go to; the playhead ones
    # not where a key already sits there.
    var ph_free := false
    var ph_taken := false
    for lane_id in by:
        var taken := false
        for k in _lane(lane_id)["keys"]:
            if absf(float(k["t"]) - _playhead) < T_EPS: taken = true
        ph_taken = ph_taken or taken
        ph_free = ph_free or not taken
    (_btns["+key"] as Button).disabled = not ph_free
    (_btns["dup"] as Button).disabled = ph_taken
    _syncing = false


# ---------------------------------------------------------------- ease picker

func _open_ease_picker() -> void:
    if _ease_btn == null or _ease_btn.disabled: return
    for c in _ease_pop.get_children():
        _ease_pop.remove_child(c)
        c.queue_free()
    var grid := GridContainer.new()
    grid.columns = 6
    grid.add_theme_constant_override("h_separation", 4)
    grid.add_theme_constant_override("v_separation", 4)
    _ease_pop.add_child(grid)
    var names: Array = ZenEasing.all_names().duplicate()
    names.append(ZenAnimBuilder.EASE_RAW)
    var cur := _ease_btn.text
    for n in names:
        var b := Button.new()
        b.focus_mode = FOCUS_NONE
        b.custom_minimum_size = Vector2(76, 50)
        b.toggle_mode = true
        b.button_pressed = n == cur
        b.tooltip_text = String(n)
        b.pressed.connect(func():
            _ease_pop.hide()
            ease_set.emit(String(n)))
        var g := ZenEaseGraph.new()
        g.ease = "linear" if n == ZenAnimBuilder.EASE_RAW else String(n)
        g.line_color = ZenTimelineView.ease_color(String(n))
        g.caption = String(n)
        g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        b.add_child(g)
        b.mouse_entered.connect(func():
            if _graph == null: return
            _graph.samples = PackedFloat32Array()
            _graph.ease = g.ease
            _graph.caption = String(n))
        grid.add_child(b)
    _ease_pop.popup_hide.connect(func(): if _graph != null: _refresh_fields(), CONNECT_ONE_SHOT)
    _ease_pop.reset_size()
    # The panel sits at the right edge: keep the grid on screen.
    var vp := get_viewport_rect().size
    var at := _ease_btn.get_screen_position() + Vector2(0, _ease_btn.size.y)
    at.x = clampf(at.x, 0.0, maxf(vp.x - _ease_pop.size.x, 0.0))
    if at.y + _ease_pop.size.y > vp.y: at.y = maxf(_ease_btn.get_screen_position().y - _ease_pop.size.y, 0.0)
    _ease_pop.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
