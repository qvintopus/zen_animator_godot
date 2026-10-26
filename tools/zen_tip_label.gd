class_name ZenTipLabel
extends Label
## A Label whose hover tooltip is a ZenTooltip (it takes the mouse to show one).

var tip := {}:
    set(v):
        tip = v
        tooltip_text = ZenTooltip.text(v)


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_PASS


func _make_custom_tooltip(_for_text: String) -> Object:
    return ZenTooltip.build(tip)
