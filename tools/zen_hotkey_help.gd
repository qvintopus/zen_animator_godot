class_name ZenHotkeyHelp
extends PanelContainer
##
## The H hotkey sheet: H shows it, H (or ESC) hides it. The footer of each
## screen names only the essential keys - a full legend in one Label sets the
## window's minimum width and pushed the gallery off both sides of the screen -
## and this lists every key for the screen it is shown over.
##
## Long lists are split into pages, one tab each; the screen opens the page
## for what the user is pointing at, and Left/Right or Tab flips through the
## rest. The sheet never grows past its parent: a page that still does not fit
## scrolls.
##
## Keys are read from the live InputMap, so a binding changed in Project
## Settings > Input Map is what the sheet shows.
##
## Rows are [action_or_keys, description]: an InputMap action name is
## resolved to its keys; anything else (mouse gestures, "1-9") is shown as is.
##

const MARGIN := 24.0                     ## kept free around the sheet

var _title: Label
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _stack: MarginContainer              ## the pages, one shown at a time
var _grids: Array = []                   ## one GridContainer per page
var _page := 0


func _init() -> void:
    visible = false
    mouse_filter = Control.MOUSE_FILTER_STOP
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
    _tabs = HBoxContainer.new()
    _tabs.add_theme_constant_override("separation", 4)
    col.add_child(_tabs)
    _scroll = ScrollContainer.new()
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    col.add_child(_scroll)
    _stack = MarginContainer.new()
    _scroll.add_child(_stack)


## Show a one-page sheet for `title` with `rows`, centred over the parent.
func show_rows(title: String, rows: Array) -> void:
    show_pages(title, [{"name": "", "rows": rows}])


## Show the sheet with `pages` ({name, rows} each), open on page `start`.
func show_pages(title: String, pages: Array, start := 0) -> void:
    _title.text = "%s  -  hotkeys" % title
    for ch in _tabs.get_children() + _stack.get_children():
        ch.get_parent().remove_child(ch)
        ch.queue_free()
    _grids.clear()
    for i in pages.size():
        _grids.append(_grid(pages[i]["rows"]))
        _stack.add_child(_grids[i])
        var b := Button.new()
        b.text = String(pages[i]["name"])
        b.flat = true
        b.focus_mode = Control.FOCUS_NONE
        b.pressed.connect(set_page.bind(i))
        _tabs.add_child(b)
    _tabs.visible = pages.size() > 1
    if _tabs.visible:
        var hint := ZenUI.label("Left / Right  pages      H  close", ZenUI.DIM)
        hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        _tabs.add_child(hint)
    # Sized for the biggest page (all are shown while measuring), so flipping
    # pages does not jump the sheet.
    var need := _stack.get_combined_minimum_size()
    need.x = maxf(need.x, _tabs.get_combined_minimum_size().x)
    var chrome := 36.0 + 10.0 + _title.get_combined_minimum_size().y
    if _tabs.visible: chrome += 10.0 + _tabs.get_combined_minimum_size().y
    var room := get_parent_area_size().y - 2.0 * MARGIN - chrome
    _scroll.custom_minimum_size = Vector2(need.x, clampf(need.y, 40.0, maxf(room, 40.0)))
    _page = -1
    set_page(clampi(start, 0, pages.size() - 1))
    visible = true
    reset_size()
    position = ((get_parent_area_size() - size) * 0.5).floor()


func page() -> int:
    return _page


func page_count() -> int:
    return _grids.size()


func set_page(i: int) -> void:
    if i == _page or i < 0 or i >= _grids.size(): return
    _page = i
    _scroll.scroll_vertical = 0
    for j in _grids.size():
        (_grids[j] as Control).visible = j == i
        (_tabs.get_child(j) as Button).add_theme_color_override("font_color",
            ZenUI.TITLE if j == i else ZenUI.DIM)


## Keys while the sheet is open, ahead of the screen's own: Left/Right and
## Tab flip pages, H and ESC close it, everything else is swallowed. Returns
## false when the sheet is hidden and the key is the screen's.
func handle_key(ev: InputEvent) -> bool:
    if not visible: return false
    if not (ev is InputEventKey) or not ev.is_pressed(): return true
    var k := ev as InputEventKey
    var n := _grids.size()
    if ev.is_action_pressed("zen_help") or ev.is_action_pressed("zen_back"):
        if not k.echo: visible = false
    elif k.keycode == KEY_RIGHT or (k.keycode == KEY_TAB and not k.shift_pressed):
        set_page((_page + 1) % n)
    elif k.keycode == KEY_LEFT or k.keycode == KEY_TAB:
        set_page((_page + n - 1) % n)
    return true


func _grid(rows: Array) -> GridContainer:
    var g := GridContainer.new()
    g.columns = 2
    g.add_theme_constant_override("h_separation", 24)
    g.add_theme_constant_override("v_separation", 4)
    for r in rows:
        var k := Label.new()
        k.text = keys(String(r[0]))
        k.add_theme_color_override("font_color", ZenUI.TITLE)
        g.add_child(k)
        var d := Label.new()
        d.text = String(r[1])
        d.add_theme_color_override("font_color", ZenUI.TEXT)
        g.add_child(d)
    return g


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
