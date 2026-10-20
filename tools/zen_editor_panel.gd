class_name ZenEditorPanel
extends PanelContainer
##
## One summonable panel of the scene editor: a title bar with a pin and a
## close button over a `body` the owner fills.
##
## A panel is hidden until summoned (top-bar button, View menu or its F-key).
## UNPINNED it floats over the canvas and goes away on its own - ESC, a click
## on the canvas, or another unpinned panel opening on the same side. PINNED
## it stays until closed and reserves its edge, so the canvas shrinks to make
## room instead of being covered. Where it sits is the owner's job
## (ZenSceneEditor._layout); this only holds the state and the chrome.
##

signal state_changed      ## open or pinned flipped

enum Edge { LEFT, RIGHT, BOTTOM }

var panel_id := ""
var side: Edge = Edge.LEFT
## Width of a side panel, height of a bottom one.
var extent := 260.0
var is_open := false
var pinned := false
var body: VBoxContainer

var _pin: Button
var _title: Label


func _init(id: String, title: String, s: int, ext: float) -> void:
    panel_id = id
    side = s as Edge
    extent = ext
    visible = false
    mouse_filter = MOUSE_FILTER_STOP
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(ZenUI.BG, 0.97)
    sb.border_color = ZenUI.DIM
    sb.set_border_width_all(1)
    sb.set_content_margin_all(6)
    add_theme_stylebox_override("panel", sb)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 4)
    add_child(col)
    var head := HBoxContainer.new()
    col.add_child(head)
    _title = ZenUI.label(title, ZenUI.LABEL)
    _title.size_flags_horizontal = SIZE_EXPAND_FILL
    head.add_child(_title)
    _pin = _tool_button("pin", "Pin: keep this panel open and make room for it")
    _pin.toggle_mode = true
    _pin.toggled.connect(func(on): set_pinned(on))
    head.add_child(_pin)
    var close := _tool_button("x", "Close")
    close.pressed.connect(func(): set_open(false))
    head.add_child(close)
    body = VBoxContainer.new()
    body.size_flags_vertical = SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 4)
    col.add_child(body)


static func _tool_button(text: String, tip: String) -> Button:
    var b := Button.new()
    b.text = text
    b.tooltip_text = tip
    b.focus_mode = FOCUS_NONE
    b.flat = true
    return b


func set_open(on: bool) -> void:
    if on == is_open: return
    is_open = on
    visible = on
    state_changed.emit()


func set_pinned(on: bool) -> void:
    if on == pinned: return
    pinned = on
    _pin.set_pressed_no_signal(on)
    _pin.text = "pinned" if on else "pin"
    state_changed.emit()


func toggle() -> void:
    set_open(not is_open)


func state() -> Dictionary:
    return {"open": is_open, "pinned": pinned}


func apply_state(d: Dictionary) -> void:
    set_pinned(bool(d.get("pinned", false)))
    # Only a pinned panel comes back open: an unpinned one is a transient.
    set_open(bool(d.get("open", false)) and pinned)
