class_name ZenHotkeyHelp
extends PanelContainer
##
## The hold-H hotkey sheet. The footer of each screen names only the
## essential keys - a full legend in one Label sets the window's minimum
## width and pushed the gallery off both sides of the screen - and this lists
## every key for the screen it is shown over.
##
## Keys are read from the live InputMap, so a binding changed in Project
## Settings > Input Map is what the sheet shows.
##
## Rows are [action_or_keys, description]: an InputMap action name is
## resolved to its keys; anything else (mouse gestures, "1-9") is shown as is.
##

var _grid: GridContainer
var _title: Label


func _init() -> void:
    visible = false
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_CENTER)
    grow_horizontal = Control.GROW_DIRECTION_BOTH
    grow_vertical = Control.GROW_DIRECTION_BOTH
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.11, 0.12, 0.145, 1)
    sb.border_color = Color(0.38, 0.686, 0.937, 0.6)
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(6)
    sb.set_content_margin_all(18)
    add_theme_stylebox_override("panel", sb)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    add_child(col)
    _title = Label.new()
    _title.add_theme_color_override("font_color", ZenUI.LABEL)
    col.add_child(_title)
    _grid = GridContainer.new()
    _grid.columns = 2
    _grid.add_theme_constant_override("h_separation", 24)
    _grid.add_theme_constant_override("v_separation", 4)
    col.add_child(_grid)


## Show the sheet for `title` with `rows`, centred over the parent.
func show_rows(title: String, rows: Array) -> void:
    _title.text = "%s  -  hotkeys" % title
    for ch in _grid.get_children():
        _grid.remove_child(ch)
        ch.queue_free()
    for r in rows:
        var k := Label.new()
        k.text = keys(String(r[0]))
        k.add_theme_color_override("font_color", ZenUI.TITLE)
        _grid.add_child(k)
        var d := Label.new()
        d.text = String(r[1])
        d.add_theme_color_override("font_color", ZenUI.TEXT)
        _grid.add_child(d)
    reset_size()
    visible = true
    # Re-centre on the content's new size.
    position = ((get_parent_area_size() - size) * 0.5).floor()


## The keys bound to `action`, "A / B" for several; non-actions pass through.
static func keys(action: String) -> String:
    var out := _key_names(action)
    return " / ".join(out) if not out.is_empty() else action


## Only the first key of `action` - for the one-line footers.
static func key(action: String) -> String:
    var out := _key_names(action)
    return out[0] if not out.is_empty() else action


## A compact footer: "KEY  what      KEY  what ..." from [action, what] pairs.
static func footer(pairs: Array) -> String:
    var parts: PackedStringArray = []
    for p in pairs: parts.append("%s  %s" % [key(String(p[0])), String(p[1])])
    return "  " + "      ".join(parts)


static func _key_names(action: String) -> PackedStringArray:
    var out: PackedStringArray = []
    if not InputMap.has_action(action): return out
    for ev in InputMap.action_get_events(action):
        var k := ev as InputEventKey
        if k == null: continue
        var code := k.get_physical_keycode_with_modifiers() if k.physical_keycode != 0 \
                    else k.get_keycode_with_modifiers()
        out.append(OS.get_keycode_string(code))
    return out


func _notification(what: int) -> void:
    # Releasing H in another window never reaches us: drop the sheet instead
    # of leaving it stuck open.
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT: visible = false
