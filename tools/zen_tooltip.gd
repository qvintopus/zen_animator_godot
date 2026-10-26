class_name ZenTooltip
extends RefCounted
##
## A hover tooltip that says what something DOES, not only its key: a title,
## a sentence or two, an optional live note (the queue's contents, why a
## button is greyed out) and every key bound to it.
##
## A tip is {title, text, key: InputMap action or "", note, warn: bool}. Any
## Control can show one by overriding _make_custom_tooltip - ZenTipButton and
## ZenTipLabel do - and `text()` flattens it for the places that only take
## plain text (PopupMenu items).
##

const WIDTH := 300


static func build(tip: Dictionary) -> Control:
    var panel := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = ZenUI.BG
    sb.border_color = ZenUI.DIM
    sb.set_border_width_all(1)
    sb.set_content_margin_all(8)
    panel.add_theme_stylebox_override("panel", sb)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 4)
    panel.add_child(col)
    var title := String(tip.get("title", ""))
    if title != "": col.add_child(ZenUI.label(title, ZenUI.TITLE))
    for part in [["text", ZenUI.TEXT], ["note", ZenUI.WARN if bool(tip.get("warn", false)) else ZenUI.DIM]]:
        var s := String(tip.get(part[0], ""))
        if s == "": continue
        var l := ZenUI.label(s, part[1])
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        l.custom_minimum_size.x = WIDTH
        col.add_child(l)
    var keys := _keys(tip)
    if keys != "": col.add_child(ZenUI.label(keys, ZenUI.LABEL))
    return panel


## The same tip as plain text, one part per line.
static func text(tip: Dictionary) -> String:
    var lines: PackedStringArray = []
    for k in ["title", "text", "note"]:
        if String(tip.get(k, "")) != "": lines.append(String(tip[k]))
    var keys := _keys(tip)
    if keys != "": lines.append(keys)
    return "\n".join(lines)


## "Key: A / B" for every binding of the tip's action; a non-action key
## (a label such as "1-3") passes through.
static func _keys(tip: Dictionary) -> String:
    var key := String(tip.get("key", ""))
    return "" if key == "" else "Key: " + ZenHotkeyHelp.keys(key)
