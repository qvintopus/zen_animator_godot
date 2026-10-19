class_name ZenUI
extends RefCounted
##
## The pieces every tool screen shares - palette, the screen shell, and the
## selectable-row list - so the gallery, Options, Export and the shape editor
## stop each carrying their own copy.
##
## The row list is plain toggle Buttons in a VBox inside a ScrollContainer,
## not an ItemList: the screens drive selection with UP/DOWN actions rather
## than keyboard focus, and the pressed state of a toggle IS the highlight.
##

const BG := Color(0.0862745, 0.0941176, 0.1137255, 1)
const TITLE := Color(0.898, 0.753, 0.482, 1)
const LABEL := Color(0.38, 0.686, 0.937, 1)
const TEXT := Color(0.816, 0.835, 0.867, 1)
const DIM := Color(0.36, 0.39, 0.44, 1)
const WARN := Color(0.878, 0.424, 0.459, 1)


## Fill `owner` with the standard screen: background panel, margins, and a
## VBox of rows, which is returned for the caller to populate.
static func build_shell(owner: Control, separation := 8) -> VBoxContainer:
    owner.anchor_right = 1.0
    owner.anchor_bottom = 1.0
    owner.grow_horizontal = Control.GROW_DIRECTION_BOTH
    owner.grow_vertical = Control.GROW_DIRECTION_BOTH

    var bg := Panel.new()
    bg.anchor_right = 1.0
    bg.anchor_bottom = 1.0
    var sb := StyleBoxFlat.new()
    sb.bg_color = BG
    bg.add_theme_stylebox_override("panel", sb)
    owner.add_child(bg)

    var margin := MarginContainer.new()
    margin.anchor_right = 1.0
    margin.anchor_bottom = 1.0
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_bottom", 12)
    owner.add_child(margin)

    var rows := VBoxContainer.new()
    rows.add_theme_constant_override("separation", separation)
    margin.add_child(rows)
    return rows


static func label(text: String, color := TEXT, font_size := 0) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", color)
    if font_size > 0: l.add_theme_font_size_override("font_size", font_size)
    return l


## Replace `list`'s rows with one toggle button per label. `on_pressed` and
## (optionally) `on_double_click` are called with the row index.
static func fill_list(list: VBoxContainer, labels: Array, on_pressed: Callable,
                      on_double_click := Callable()) -> void:
    for ch in list.get_children():
        # remove_child first: a queued-but-present row would still count in
        # get_child_count() and shift every index read this frame.
        list.remove_child(ch)
        ch.queue_free()
    for i in labels.size():
        var b := Button.new()
        b.text = "  %s" % String(labels[i])
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.focus_mode = Control.FOCUS_NONE
        b.toggle_mode = true
        b.pressed.connect(on_pressed.bind(i))
        if on_double_click.is_valid():
            b.gui_input.connect(_on_row_input.bind(b, on_double_click.bind(i)))
        list.add_child(b)


static func _on_row_input(ev: InputEvent, b: Button, fn: Callable) -> void:
    var mb := ev as InputEventMouseButton
    if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click: return
    # `pressed` already fired for the first click, so the row is selected.
    fn.call()
    b.accept_event()


## Highlight row `i` (and only it); -1 clears the highlight.
static func mark_selected(list: VBoxContainer, i: int) -> void:
    for j in list.get_child_count():
        (list.get_child(j) as Button).button_pressed = j == i


## Highlight every row a multi-row selection shows as selected.
static func show_selection(list: VBoxContainer, sel: ZenListSelection) -> void:
    for j in list.get_child_count():
        (list.get_child(j) as Button).button_pressed = sel.shows(j)


## Shift / Ctrl as held right now, for a row's `pressed` (which carries no
## modifiers of its own).
static func held_modifiers() -> Dictionary:
    return {"shift": Input.is_key_pressed(KEY_SHIFT),
            "ctrl": Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)}


## Scroll row `i` into view. Waits a frame: rows built this frame have no
## layout yet, and ensure_control_visible would aim at zero.
static func scroll_to(scroll: ScrollContainer, list: VBoxContainer, i: int) -> void:
    if not scroll.is_inside_tree(): return
    await scroll.get_tree().process_frame
    if is_instance_valid(scroll) and i >= 0 and i < list.get_child_count():
        scroll.ensure_control_visible(list.get_child(i))
