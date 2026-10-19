@tool
class_name ZenOptions
extends Control
##
## Options screen, reachable from the gallery with O (zen_options). Two
## settings live here, both through ZenSettings so they persist to
## user://zen_settings.cfg and so other entry points (the exporter) pick them
## up without this screen ever having run:
##
##   - FONT: applied process-wide via ZenText's static override, so every
##     element with no per-element `font` picks it up with no .tscn edit.
##     "Default" is the bundled Source Sans 3; everything else is a real
##     installed font looked up by family name through Godot's SystemFont -
##     no bundling needed to offer actual choice.
##   - EXPORT SCALE: the multiplier tools/export_scene.gd uses when --scale
##     is not given on the command line. Shown resolved against the 320x180
##     design canvas every current animation uses (ZenCanvas.design_size's
##     own default) so the number on screen is the number ffmpeg will see.
##

signal closed

## ZenCanvas.design_size's own default - shown here so the resolution line
## means something; a document with a different canvas will export at a
## different size regardless, this is just the common case.
const CANVAS_SIZE := Vector2(320, 180)

@onready var _font_list: VBoxContainer = $Margin/Rows/Body/FontCol/FontScroll/FontList
@onready var _preview: Label = $Margin/Rows/Body/PreviewCol/Preview
@onready var _res_label: Label = $Margin/Rows/Body/PreviewCol/Resolution
@onready var _scale_value: Label = $Margin/Rows/Body/PreviewCol/ScaleRow/Value
@onready var _hint: Label = $Margin/Rows/Foot/Hint

## "" is the bundled default; the rest are whatever OS.get_system_fonts()
## reports on this machine, so the list is never stale against what the font
## picker can actually resolve.
var _fonts: Array = []
var _sel := 0


func _ready() -> void:
    _fonts = [""]
    _fonts.append_array(OS.get_system_fonts())
    _build_font_list()
    _select(maxi(_fonts.find(ZenSettings.font_name()), 0))
    _update_scale_label()
    _hint.text = "  UP/DOWN  font      LEFT/RIGHT  export scale      ESC  back"


func _build_font_list() -> void:
    for ch in _font_list.get_children(): ch.queue_free()
    for i in _fonts.size():
        var nm: String = _fonts[i]
        var b := Button.new()
        b.text = "  Default (Source Sans 3)" if nm == "" else "  %s" % nm
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.focus_mode = Control.FOCUS_NONE
        b.toggle_mode = true
        b.pressed.connect(_select.bind(i))
        _font_list.add_child(b)


## Selecting a row applies the font immediately - a static override on
## ZenText, so the preview label (and every animation played after this)
## picks it up with no further wiring.
func _select(i: int) -> void:
    if _fonts.is_empty(): return
    _sel = clampi(i, 0, _fonts.size() - 1)
    for j in _font_list.get_child_count():
        (_font_list.get_child(j) as Button).button_pressed = j == _sel
    ZenSettings.set_font_name(_fonts[_sel])
    _preview.add_theme_font_override("font", ZenText.default_font())


func _bump_scale(delta: int) -> void:
    ZenSettings.set_export_scale(ZenSettings.export_scale() + delta)
    _update_scale_label()


func _update_scale_label() -> void:
    var s := ZenSettings.export_scale()
    _scale_value.text = "x%d" % s
    _res_label.text = "export resolution  %d x %d  (320x180 canvas x%d)" % [
        int(CANVAS_SIZE.x) * s, int(CANVAS_SIZE.y) * s, s]


func _unhandled_input(ev: InputEvent) -> void:
    if ev.is_echo(): return
    if ev.is_action_pressed("zen_back"):
        closed.emit()
        get_viewport().set_input_as_handled()
    elif ev.is_action_pressed("zen_prev"):
        _select(_sel - 1)
        get_viewport().set_input_as_handled()
    elif ev.is_action_pressed("zen_next"):
        _select(_sel + 1)
        get_viewport().set_input_as_handled()
    elif ev.is_action_pressed("zen_scale_down"):
        _bump_scale(-1)
        get_viewport().set_input_as_handled()
    elif ev.is_action_pressed("zen_scale_up"):
        _bump_scale(1)
        get_viewport().set_input_as_handled()
