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
## (optionally) `on_double_click` are called with the row index;
## `on_context` with the row index and the screen position of a right-click.
static func fill_list(list: VBoxContainer, labels: Array, on_pressed: Callable,
                      on_double_click := Callable(), on_context := Callable()) -> void:
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
        if on_double_click.is_valid() or on_context.is_valid():
            b.gui_input.connect(_on_row_input.bind(b,
                on_double_click.bind(i) if on_double_click.is_valid() else Callable(),
                on_context.bind(i) if on_context.is_valid() else Callable()))
        list.add_child(b)


static func _on_row_input(ev: InputEvent, b: Button, fn: Callable, ctx := Callable()) -> void:
    var mb := ev as InputEventMouseButton
    if mb == null or not mb.pressed: return
    if mb.button_index == MOUSE_BUTTON_RIGHT and ctx.is_valid():
        ctx.call(b.get_screen_transform() * mb.position)
        b.accept_event()
        return
    if mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click or not fn.is_valid(): return
    # `pressed` already fired for the first click, so the row is selected.
    fn.call()
    b.accept_event()


# ---------------------------------------------------------------- actions
#
# An action is {label, fn: Callable, key: hotkey action name or "",
# enabled := true, toggle := false, on := false, tip: what it does,
# note: live state}; {} is a separator. One
# list of them can fill a button bar and a context menu alike, so a screen
# describes what it can do once and the mouse and the keys stay in step.

## The ZenTooltip of action `a`.
static func action_tip(a: Dictionary) -> Dictionary:
    return {"title": String(a["label"]), "text": String(a.get("tip", "")),
            "key": String(a.get("key", "")), "note": String(a.get("note", "")),
            "warn": not bool(a.get("enabled", true))}


## A flat bar button for `a`, its tooltip saying what it does and its keys.
static func bar_button(a: Dictionary) -> Button:
    var b := ZenTipButton.new()
    b.text = String(a["label"])
    b.flat = true
    b.focus_mode = Control.FOCUS_NONE
    b.disabled = not bool(a.get("enabled", true))
    b.tip = action_tip(a)
    b.add_theme_color_override("font_color", TEXT)
    b.add_theme_color_override("font_hover_color", TITLE)
    b.add_theme_color_override("font_disabled_color", DIM)
    if bool(a.get("toggle", false)):
        b.toggle_mode = true
        b.button_pressed = bool(a.get("on", false))
        b.add_theme_color_override("font_pressed_color", LABEL)
        b.add_theme_color_override("font_hover_pressed_color", LABEL)
    var fn: Callable = a["fn"]
    # Deferred: the action usually rebuilds this very bar.
    b.pressed.connect(func(): if fn.is_valid(): fn.call_deferred())
    return b


## Replace `box`'s children with a button per action, a separator per {}.
static func fill_bar(box: HBoxContainer, actions: Array) -> void:
    for ch in box.get_children():
        box.remove_child(ch)
        ch.queue_free()
    for a in actions:
        if (a as Dictionary).is_empty(): box.add_child(VSeparator.new())
        else: box.add_child(bar_button(a))


## Fill `pm` with `actions` and pop it up at screen position `at`. The menu
## keeps the callables in its "fns" meta, read back by `menu_pressed`.
static func popup_actions(pm: PopupMenu, actions: Array, at: Vector2) -> void:
    pm.clear()
    for ch in pm.get_children():
        pm.remove_child(ch)
        ch.queue_free()
    popup_fill(pm, actions)
    pm.reset_size()
    pm.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


## Fill `pm` without popping it up: an item per action (its key after the
## label), a separator per {} (never a leading one), a submenu per action
## with `sub`. The caller connects id_pressed to `menu_pressed`.
static func popup_fill(pm: PopupMenu, actions: Array) -> void:
    var fns: Array = []
    for a in actions:
        if (a as Dictionary).is_empty():
            if pm.item_count > 0: pm.add_separator()
            continue
        var label := String(a["label"])
        if (a as Dictionary).has("sub"):
            var sub := PopupMenu.new()
            pm.add_child(sub)
            sub.id_pressed.connect(menu_pressed.bind(sub))
            popup_fill(sub, a["sub"])
            pm.add_submenu_node_item(label, sub)
            _item_extras(pm, a)
            continue
        var key := String(a.get("key", ""))
        if key != "": label += "    (%s)" % ZenHotkeyHelp.key(key)
        pm.add_item(label, fns.size())
        _item_extras(pm, a)
        fns.append(a["fn"])
    pm.set_meta("fns", fns)


## Disabled state and a plain-text tooltip (PopupMenu has no custom one).
static func _item_extras(pm: PopupMenu, a: Dictionary) -> void:
    var i := pm.item_count - 1
    pm.set_item_disabled(i, not bool(a.get("enabled", true)))
    var t := action_tip(a)
    t.erase("title")
    t.erase("key")
    var s := ZenTooltip.text(t)
    if s != "": pm.set_item_tooltip(i, s)


## Connect to a PopupMenu's id_pressed (bound with the menu) to run the
## action `popup_actions` stored for that id.
static func menu_pressed(id: int, pm: PopupMenu) -> void:
    var fns: Array = pm.get_meta("fns", [])
    if id >= 0 and id < fns.size() and (fns[id] as Callable).is_valid(): (fns[id] as Callable).call()


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
